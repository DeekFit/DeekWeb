import 'dart:async';
import 'package:deekweb/deekweb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class Request extends DeekWebRequest<String> {
  Request(
      {this.parse,
      this.verb = Method.get,
      this.payload,
      this.extraHeaders = const {},
      this.url =
          'https://user:password@example.com:8443/path-secret?q=query-secret#fragment-secret'});
  final String? Function(DeekWebHttpResponse)? parse;
  final Method verb;
  final Object? payload;
  final Map<String, String> extraHeaders;
  final String url;
  @override
  Method get method => verb;
  @override
  Uri get uri => Uri.parse(url);
  @override
  Object? get body => payload;
  @override
  Map<String, String> get headers => extraHeaders;
  @override
  String? parseResponse(DeekWebHttpResponse response) =>
      parse == null ? response.body : parse!(response);
}

class Listener implements DeekWebListener {
  int starts = 0;
  final List<int?> successes = [];
  final List<int?> errors = [];
  void Function()? onStart;
  void Function()? onEnd;
  @override
  void requestStarted(
      {required String requestId, required String requestType}) {
    starts++;
    onStart?.call();
  }

  @override
  void requestCompleted({required String requestId, required int statusCode}) {
    successes.add(statusCode);
    onEnd?.call();
  }

  @override
  void requestCompletedWithError(
      {required String requestId, int? statusCode, String? error}) {
    errors.add(statusCode);
    onEnd?.call();
  }
}

class Logger implements DeekWebLogger {
  final List<String> lines = [];
  @override
  void verbose(String line) {
    lines.add(line);
  }

  @override
  void info(String line) {
    lines.add(line);
  }

  @override
  void warn(String line) {
    lines.add(line);
  }

  @override
  void error(String line, {Exception? e}) {
    lines.add(line);
  }
}

class Borrowed extends MockClient {
  Borrowed(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
  }
}

class Legacy extends DeekWebClient {
  @override
  Future<DeekWebResponse<R, T>> executeRequest<R extends DeekWebRequest, T>(
      DeekWebRequest<T> request) async {
    return DeekWebResponse.fromResponse(
        request: request, data: null, statusCode: 204, latencyMs: 0);
  }
}

void main() {
  test('HTTP errors retain body and have exactly one failure notification',
      () async {
    final listener = Listener();
    final client = DeekWebClient(
        client: MockClient((_) async => http.Response('denied', 401)))
      ..addListener(listener);
    final response = await client.executeRequest(Request());
    expect(response.statusCode, 401);
    expect(response.data, 'denied');
    expect(response.wasSuccessful, false);
    expect(listener.errors, [401]);
    expect(listener.successes, isEmpty);
    client.close();
  });
  test('legacy TypeError retains HTTP status, cause and stack', () async {
    final listener = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 202)))
          ..addListener(listener);
    final response = await client
        .executeRequest(Request(parse: (_) => (42 as dynamic) as String));
    expect(response.exception, isA<DeekWebParseException>());
    expect(response.exception!.cause, isA<TypeError>());
    expect(response.exception!.stackTrace, isNotNull);
    expect(response.statusCode, 202);
    expect(listener.errors, [202]);
    expect(listener.successes, isEmpty);
    client.close();
  });
  test('parser exception and arbitrary object propagate unchanged', () async {
    for (final failure in [
      const FormatException('secret'),
      StateError('secret'),
      Object()
    ]) {
      final stack = StackTrace.current;
      final listener = Listener();
      final client =
          DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
            ..addListener(listener);
      await expectLater(
          client.executeRequest(
              Request(parse: (_) => Error.throwWithStackTrace(failure, stack))),
          throwsA(same(failure)));
      expect(listener.errors, [200]);
      client.close();
    }
  });
  test('transport exception captures cause and elapsed time', () async {
    final failure = http.ClientException('private URI');
    final client = DeekWebClient(client: MockClient((_) async {
      throw failure;
    }));
    final result = await client.executeRequest(Request());
    expect(result.statusCode, isNull);
    expect(result.exception!.cause, same(failure));
    expect(result.exception!.stackTrace, isNotNull);
    expect(result.latencyMs, greaterThanOrEqualTo(0));
    client.close();
  });
  test('preparation failure propagates and settles listeners', () async {
    var sent = false;
    final listener = Listener();
    final client = DeekWebClient(client: MockClient((_) async {
      sent = true;
      return http.Response('', 200);
    }))
      ..addListener(listener);
    await expectLater(
        client.executeRequest(Request(verb: Method.post, payload: Object())),
        throwsArgumentError);
    expect(sent, false);
    expect(listener.errors, [null]);
    client.close();
  });
  test('headers copied, IDs unique, GET HEAD DELETE ignore body', () async {
    final ids = <String>{};
    final headers = Map<String, String>.unmodifiable({'x-test': 'value'});
    final client = DeekWebClient(
        includeCvHeader: true,
        client: MockClient((request) async {
          ids.add(request.headers['cv-in']!);
          expect(request.bodyBytes, isEmpty);
          return http.Response('', 204);
        }));
    await Future.wait([
      for (final verb in [Method.get, Method.head, Method.delete])
        client.executeRequest(
            Request(verb: verb, payload: 'ignored', extraHeaders: headers))
    ]);
    expect(ids.length, 3);
    expect(headers, {'x-test': 'value'});
    client.close();
  });
  test('origin omits private URI components and handles IPv6/invalid URIs',
      () async {
    final logger = Logger();
    final client = DeekWebClient(
        logger: logger,
        client: MockClient((_) async => http.Response('', 200)));
    await client.executeRequest(Request());
    expect(logger.lines.join(), contains('https://example.com:8443'));
    for (final secret in [
      'user',
      'password',
      'path-secret',
      'query-secret',
      'fragment-secret'
    ]) {
      expect(logger.lines.join(), isNot(contains(secret)));
    }
    expect(Request(url: '/relative').uriForLogging, '[unavailable-origin]');
    expect(
        Request(url: 'file:///secret').uriForLogging, '[unavailable-origin]');
    expect(Request(url: 'http://[::1]:8080/secret').uriForLogging,
        'http://[::1]:8080');
    client.close();
  });
  test(
      'close settles active requests synchronously and never closes borrowed client',
      () async {
    final pending = Completer<http.Response>();
    final transport = Borrowed((_) => pending.future);
    final listener = Listener();
    final client = DeekWebClient(client: transport)..addListener(listener);
    final future = client.executeRequest(Request());
    client.close();
    expect(listener.errors, [null]);
    expect((await future).exception, isA<DeekWebClientClosedException>());
    expect(transport.closed, false);
    client.close();
    expect(() => client.executeRequest(Request()), throwsStateError);
    expect(listener.starts, 1);
    pending.complete(http.Response('late', 200));
    await Future<void>.delayed(Duration.zero);
    expect(listener.errors.length, 1);
    expect(listener.successes, isEmpty);
  });
  test('listener mutation and reentrant closure settle once', () async {
    final first = Listener();
    final removed = Listener();
    final later = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
          ..addListener(first)
          ..addListener(removed);
    first.onStart = () {
      client.removeListener(removed);
      client.addListener(later);
    };
    first.onEnd = client.close;
    await client.executeRequest(Request());
    expect(removed.starts, 0);
    expect(later.starts, 0);
    expect(first.successes, [200]);
  });
  test('observer exceptions isolated; start Error stops additional starts',
      () async {
    for (final failure in [Exception('private'), StateError('private')]) {
      final first = Listener()
        ..onStart = () {
          throw failure;
        };
      final second = Listener();
      final client =
          DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
            ..addListener(first)
            ..addListener(second);
      final future = client.executeRequest(Request());
      if (failure is Exception) {
        expect((await future).wasSuccessful, true);
        expect(second.successes, [200]);
      } else {
        await expectLater(future, throwsA(same(failure)));
        expect(second.starts, 0);
        expect(first.errors, [null]);
      }
      client.close();
    }
  });
  test(
      'terminal Error propagates after remaining listeners; primary failure wins',
      () async {
    final error = StateError('observer');
    const primary = FormatException('primary');
    final first = Listener()
      ..onEnd = () {
        throw error;
      };
    final second = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
          ..addListener(first)
          ..addListener(second);
    await expectLater(client.executeRequest(Request()), throwsA(same(error)));
    expect(second.successes, [200]);
    await expectLater(client.executeRequest(Request(parse: (_) {
      throw primary;
    })), throwsA(same(primary)));
    expect(second.errors, [200]);
    client.close();
  });
  test('legacy generic override remains valid', () async {
    expect((await Legacy().executeRequest(Request())).statusCode, 204);
    expect(
        DeekWebException.fromException(const FormatException('x')).toString(),
        contains('x'));
  });
  test('removal and re-addition relinquish the current candidate snapshot',
      () async {
    final first = Listener();
    final later = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
          ..addListener(first)
          ..addListener(later);
    first.onStart = () {
      client.removeListener(later);
      client.addListener(later);
    };
    await client.executeRequest(Request());
    expect(later.starts, 0);
    first.onStart = null;
    await client.executeRequest(Request());
    expect(later.starts, 1);
    client.close();
  });
  test(
      'ordinary success range includes redirects; all other HTTP statuses fail',
      () async {
    for (final status in [199, 200, 204, 299, 300, 399, 400, 503]) {
      final listener = Listener();
      final client = DeekWebClient(
          client: MockClient((_) async => http.Response('body', status)))
        ..addListener(listener);
      final response = await client.executeRequest(Request());
      expect(response.wasSuccessful, status >= 200 && status < 400);
      expect(response.data, 'body');
      expect(listener.successes.length + listener.errors.length, 1);
      client.close();
    }
  });
  test(
      'terminal removal and re-addition do not restore outstanding notifications',
      () async {
    final first = Listener();
    final second = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
          ..addListener(first)
          ..addListener(second);
    first.onEnd = () {
      client.removeListener(second);
      client.addListener(second);
    };
    await client.executeRequest(Request());
    expect(second.starts, 1);
    expect(second.successes, isEmpty);
    client.close();
  });
  test('observer arbitrary objects propagate after bookkeeping', () async {
    final failure = Object();
    final observer = Listener()
      ..onEnd = () {
        throw failure;
      };
    final other = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
          ..addListener(observer)
          ..addListener(other);
    await expectLater(client.executeRequest(Request()), throwsA(same(failure)));
    expect(other.successes, [200]);
    client.close();
  });
  test('owned transport is lazy, reused, and closed exactly once', () async {
    var created = 0;
    final transport = Borrowed((_) async => http.Response('', 200));
    await http.runWithClient(() async {
      final unused = DeekWebClient();
      unused.close();
      expect(created, 0);
      final client = DeekWebClient();
      await client.executeRequest(Request());
      await client.executeRequest(Request());
      expect(created, 1);
      expect(transport.closed, false);
      client.close();
      client.close();
      expect(transport.closed, true);
    }, () {
      created++;
      return transport;
    });
  });
}
