import 'dart:async';
import 'package:deekweb/deekweb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'core_test.dart' show Request, Listener, Borrowed;
import 'examples/policies.dart';

class _Logger implements DeekWebLogger {
  final entries = <(String, String)>[];
  bool fail = false;
  void _record(String level, String line) {
    if (fail) {
      throw Exception('private logger failure');
    }
    // Model a production logger with a minimum level of info.
    if (level != 'verbose') {
      entries.add((level, line));
    }
  }

  @override
  void info(String line) => _record('info', line);
  @override
  void verbose(String line) => _record('verbose', line);
  @override
  void warn(String line) => _record('warn', line);
  @override
  void error(String line, {Exception? e}) => _record('error', line);
}

void main() {
  test('production-level logs retain lifecycle and safe failure severity',
      () async {
    final logger = _Logger();
    for (final status in [200, 302, 401, 503]) {
      final client = DeekWebClient(
          logger: logger,
          client:
              MockClient((_) async => http.Response('secret body', status)));
      await client.executeRequest(Request());
      expect(logger.entries.last.$1, status < 400 ? 'info' : 'warn');
      client.close();
    }
    final failed = DeekWebClient(
        logger: logger,
        client: MockClient((_) async {
          throw Exception('secret exception');
        }));
    await failed.executeRequest(Request());
    expect(logger.entries.last.$1, 'error');
    failed.close();
    final listener = Listener()
      ..onStart = () {
        throw Exception('secret observer');
      };
    final observed = DeekWebClient(
        logger: logger, client: MockClient((_) async => http.Response('', 200)))
      ..addListener(listener);
    await observed.executeRequest(Request());
    expect(
        logger.entries.any((entry) =>
            entry.$1 == 'error' && entry.$2.contains('failure=observer')),
        true);
    final lines = logger.entries.map((e) => e.$2).join();
    for (final secret in [
      'secret body',
      'secret exception',
      'secret observer',
      'password',
      'path-secret',
      'query-secret'
    ]) {
      expect(lines, isNot(contains(secret)));
    }
    observed.close();
  });

  test('logger Exceptions remain isolated at info warn and error', () async {
    for (final status in [200, 401]) {
      final logger = _Logger()..fail = true;
      final client = DeekWebClient(
          logger: logger,
          client: MockClient((_) async => http.Response('', status)));
      expect((await client.executeRequest(Request())).statusCode, status);
      client.close();
    }
    final client = DeekWebClient(
        logger: _Logger()..fail = true,
        client: MockClient((_) async {
          throw Exception('transport');
        }));
    expect((await client.executeRequest(Request())).exception, isNotNull);
    client.close();
  });

  test('prepared headers are case-insensitive copied immutable and canonical',
      () {
    final headers = {'Content-type': 'text/plain', 'authorization': 'old'};
    final prepared = DeekWebPreparedRequest(
        method: 'POST',
        uri: Uri.parse('https://example.com'),
        headers: headers);
    headers.clear();
    expect(prepared.headers['CONTENT-TYPE'], 'text/plain');
    expect(prepared.headers.containsKey('Authorization'), true);
    expect(() => prepared.headers['Authorization'] = 'bad',
        throwsUnsupportedError);
    expect(
        () => prepared.headers.remove('content-TYPE'), throwsUnsupportedError);
    final copy = prepared
        .copyWith(headers: {...prepared.headers, 'Authorization': 'new'});
    expect(copy.headers['AUTHORIZATION'], 'new');
    expect(
        copy.headers.keys.where((key) => key.toLowerCase() == 'authorization'),
        hasLength(1));
    expect(prepared.headers['Authorization'], 'old');
  });

  test('auth example replaces any caller casing exactly once on the wire',
      () async {
    for (final header in ['authorization', 'Authorization', 'AUTHORIZATION']) {
      final client = DeekWebClient(
          interceptors: [
            OriginAuth(Uri.parse('https://example.com'), () async => 'new')
          ],
          client: MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer new');
            expect(
                request.headers.keys
                    .where((key) => key.toLowerCase() == 'authorization'),
                hasLength(1));
            return http.Response('', 200);
          }));
      await client.executeRequest(Request(
          url: 'https://example.com', extraHeaders: {header: 'Bearer old'}));
      client.close();
    }
  });

  test(
      'terminal Errors propagate even when execution returns a structured failure',
      () async {
    for (final mode in ['transport', 'type', 'capture']) {
      final observerError = StateError('observer');
      final first = Listener()
        ..onEnd = () {
          throw observerError;
        };
      final remaining = Listener();
      final client = DeekWebClient(client: MockClient((_) async {
        if (mode == 'transport') {
          throw Exception('transport');
        }
        return http.Response('', 409);
      }))
        ..addListener(first)
        ..addListener(remaining);
      final request = Request(parse: (_) {
        if (mode == 'type') {
          return (42 as dynamic) as String;
        }
        throw const FormatException('parse');
      });
      await expectLater(
          client.executeRequestWithOptions(request,
              options: DeekWebExecutionOptions(
                  captureParserExceptions: mode == 'capture')),
          throwsA(same(observerError)));
      expect(remaining.errors, [mode == 'transport' ? null : 409]);
      client.close();
    }
  });

  testWidgets(
      'deadline and cancellation surface terminal observer Errors on their futures',
      (tester) async {
    for (final cancel in [false, true]) {
      final error = StateError('observer');
      final listener = Listener()
        ..onEnd = () {
          throw error;
        };
      final pending = Completer<http.Response>();
      final client = DeekWebClient(client: MockClient((_) => pending.future))
        ..addListener(listener);
      final token = DeekWebCancellationToken();
      final result = client.executeRequestWithOptions(Request(),
          options: DeekWebExecutionOptions(
              timeout: const Duration(seconds: 1), cancellationToken: token));
      final expected = expectLater(result, throwsA(same(error)));
      await tester.pump();
      if (cancel) {
        token.cancel();
      } else {
        await tester.pump(const Duration(seconds: 1));
      }
      await expected;
      pending.complete(http.Response('', 200));
      await tester.pump();
      expect(listener.errors, hasLength(1));
      client.close();
    }
  });

  test(
      'close settles every request and closes owned transport before rethrowing observer object',
      () async {
    final pending = Completer<http.Response>();
    final transport = Borrowed((_) => pending.future);
    final error = Object();
    final first = Listener()
      ..onEnd = () {
        throw error;
      };
    final second = Listener();
    await http.runWithClient(() async {
      final client = DeekWebClient()
        ..addListener(first)
        ..addListener(second);
      final requests = [
        client.executeRequest(Request()),
        client.executeRequest(Request())
      ];
      expect(() => client.close(), throwsA(same(error)));
      expect(second.errors, [null, null]);
      expect(transport.closed, true);
      for (final request in requests) {
        expect((await request).exception, isA<DeekWebClientClosedException>());
      }
      client.close();
      pending.complete(http.Response('late', 200));
      await Future<void>.delayed(Duration.zero);
      expect(second.errors.length, 2);
    }, () => transport);
  });

  test('post-cancel attachment is not registered and detachment is harmless',
      () {
    final token = DeekWebCancellationToken()..cancel();
    var calls = 0;
    final detach = token.attach(() {
      calls++;
    });
    token.cancel();
    detach();
    detach();
    expect(calls, 0);
  });
}
