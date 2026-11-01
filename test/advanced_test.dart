import 'dart:async';
import 'dart:convert';
import 'package:deekweb/deekweb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'examples/policies.dart';
import 'core_test.dart' show Request, Listener, Legacy, Logger;

class Interceptor extends DeekWebInterceptor {
  Interceptor(this.callback);
  final Future<DeekWebHttpResponse> Function(
      DeekWebPreparedRequest, DeekWebInterceptorChain) callback;
  @override
  Future<DeekWebHttpResponse> intercept(
          DeekWebPreparedRequest request, DeekWebInterceptorChain chain) =>
      callback(request, chain);
}

class AsyncRequest extends DeekWebAsyncRequest<String> {
  AsyncRequest(this.parse);
  final Future<String?> Function(DeekWebHttpResponse) parse;
  @override
  Method get method => Method.get;
  @override
  Uri get uri => Uri.parse('https://example.com');
  @override
  Future<String?> parseResponseAsync(DeekWebHttpResponse response) =>
      parse(response);
}

class EncodedRequest extends Request {
  EncodedRequest(Object? payload, this.codec, Map<String, String> headers)
      : super(payload: payload, verb: Method.post, extraHeaders: headers);
  final Encoding codec;
  @override
  Encoding get encoding => codec;
}

class NamedRequest extends Request {
  @override
  String get name => 'secret\nforged';
  @override
  String get uriForLogging => 'custom\r\norigin';
}

void main() {
  test(
      'send routes through legacy overrides; nullable success and structured failures',
      () async {
    expect(await Legacy().send(Request()), isNull);
    final client = DeekWebClient(
        client: MockClient((_) async => http.Response('error data', 418)));
    await expectLater(
        client.send(Request()),
        throwsA(isA<DeekWebHttpException>()
            .having((e) => e.statusCode, 'status', 418)
            .having((e) => e.data, 'body', 'error data')));
    await expectLater(
        client.sendWithOptions(Request(), options: DeekWebExecutionOptions()),
        throwsA(isA<DeekWebHttpException>()));
    client.close();
    final nullable =
        DeekWebClient(client: MockClient((_) async => http.Response('', 204)));
    expect(await nullable.send(Request(parse: (_) => null)), isNull);
    nullable.close();
  });
  test(
      'capture mode retains parser Exception and stack; other objects propagate',
      () async {
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 409)));
    const failure = FormatException('private');
    final result = await client.executeRequestWithOptions(Request(parse: (_) {
      throw failure;
    }), options: DeekWebExecutionOptions(captureParserExceptions: true));
    expect(result.exception, isA<DeekWebParseException>());
    expect(result.exception!.cause, same(failure));
    expect(result.exception!.stackTrace, isNotNull);
    expect(result.statusCode, 409);
    for (final error in [StateError('bug'), Object()]) {
      await expectLater(
          client.executeRequestWithOptions(Request(parse: (_) {
            throw error;
          }), options: DeekWebExecutionOptions(captureParserExceptions: true)),
          throwsA(same(error)));
    }
    await expectLater(
        client.sendWithOptions(Request(parse: (_) {
          throw failure;
        }), options: DeekWebExecutionOptions(captureParserExceptions: true)),
        throwsA(isA<DeekWebParseException>()));
    client.close();
  });
  test('convenience serialization matches HTTP 1.6 effective bytes and headers',
      () async {
    for (final verb in [Method.post, Method.put, Method.patch]) {
      for (final body in [
        'Unicode ☘ café',
        <int>[0, 128, 255],
        {'a': '☘ & café'}
      ]) {
        http.Request? baseline;
        final httpClient = MockClient((r) async {
          baseline = r;
          return http.Response('', 200);
        });
        switch (verb) {
          case Method.post:
            await httpClient.post(Uri.parse('https://example.com'), body: body);
          case Method.put:
            await httpClient.put(Uri.parse('https://example.com'), body: body);
          case Method.patch:
            await httpClient.patch(Uri.parse('https://example.com'),
                body: body);
          default:
            throw StateError('Unexpected verb');
        }
        final client = DeekWebClient(client: MockClient((r) async {
          expect(r.bodyBytes, baseline!.bodyBytes);
          expect(r.headers, baseline!.headers);
          expect(r.method, baseline!.method);
          return http.Response('', 200);
        }));
        await client.executeRequest(Request(verb: verb, payload: body));
        client.close();
        httpClient.close();
      }
    }
    final headers = {'content-type': 'text/plain'};
    http.Request? baseline;
    final transport = MockClient((r) async {
      baseline = r;
      return http.Response('', 200);
    });
    await transport.post(Uri.parse('https://example.com'),
        body: 'café', headers: headers, encoding: latin1);
    final client = DeekWebClient(client: MockClient((r) async {
      expect(r.bodyBytes, baseline!.bodyBytes);
      expect(r.headers, baseline!.headers);
      return http.Response('', 200);
    }));
    await client.executeRequest(EncodedRequest('café', latin1, headers));
    client.close();
  });
  test(
      'interceptor fixed continuation repeats downstream and parses final only',
      () async {
    final order = <String>[];
    var attempts = 0;
    var parses = 0;
    final first = Interceptor((r, c) async {
      order.add('outer');
      await c.proceed(r);
      return c.proceed(r.copyWith(headers: {...r.headers, 'retry': 'yes'}));
    });
    final second = Interceptor((r, c) async {
      order.add('inner');
      expect(() => r.headers['x'] = 'bad', throwsUnsupportedError);
      final bytes = r.bodyBytes;
      if (bytes.isNotEmpty) {
        bytes[0] = 0;
      }
      return c.proceed(r);
    });
    final source = [first, second];
    final client = DeekWebClient(
        interceptors: source,
        client: MockClient((r) async {
          attempts++;
          expect(r.body, 'payload');
          return http.Response('attempt $attempts', 200);
        }));
    source.clear();
    final listener = Listener();
    client.addListener(listener);
    final response = await client.executeRequest(Request(
        verb: Method.post,
        payload: 'payload',
        parse: (r) {
          parses++;
          return r.body;
        }));
    expect(response.data, 'attempt 2');
    expect(order, ['outer', 'inner', 'inner']);
    expect(parses, 1);
    expect(listener.starts, 1);
    expect(listener.successes.length, 1);
    client.close();
  });
  test('synthetic response and overlapping continuation rejection', () async {
    final client = DeekWebClient(interceptors: [
      Interceptor((r, c) async => DeekWebHttpResponse(
          statusCode: 201, bodyBytes: utf8.encode('synthetic')))
    ]);
    expect(await client.send(Request()), 'synthetic');
    client.close();
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final overlap =
        DeekWebClient(client: MockClient((_) => pending.future), interceptors: [
      Interceptor((r, c) async {
        final first = c.proceed(r);
        await expectLater(c.proceed(r), throwsStateError);
        started.complete();
        return first;
      })
    ]);
    final future = overlap.executeRequest(Request());
    await started.future;
    pending.complete(http.Response('', 200));
    expect((await future).wasSuccessful, true);
    overlap.close();
  });
  test('pre-cancelled and shared sticky token settle once without dispatch',
      () async {
    var dispatches = 0;
    final token = DeekWebCancellationToken()
      ..cancel()
      ..cancel();
    final listener = Listener();
    final client = DeekWebClient(client: MockClient((_) async {
      dispatches++;
      return http.Response('', 200);
    }))
      ..addListener(listener);
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        client.executeRequestWithOptions(Request(),
            options: DeekWebExecutionOptions(cancellationToken: token))
    ]);
    expect(dispatches, 0);
    expect(results.map((r) => r.exception),
        everyElement(isA<DeekWebCancelledException>()));
    expect(listener.starts, 2);
    expect(listener.errors.length, 2);
    client.close();
  });
  testWidgets('deadline covers retries and releases logical timers',
      (tester) async {
    var attempts = 0;
    final client = DeekWebClient(
        interceptors: [
          Interceptor((r, c) async {
            expect(c.deadline, isNotNull);
            expect(c.remaining, isNotNull);
            await c.proceed(r);
            await c.delay(const Duration(seconds: 10));
            return c.proceed(r);
          })
        ],
        client: MockClient((_) async {
          attempts++;
          return http.Response('', 503);
        }));
    final listener = Listener();
    client.addListener(listener);
    final future = client.executeRequestWithOptions(Request(),
        options: DeekWebExecutionOptions(timeout: const Duration(seconds: 5)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect((await future).exception, isA<DeekWebTimeoutException>());
    expect(attempts, 1);
    expect(listener.errors.length, 1);
    client.close();
  });
  test('ignored abort transport completion and late errors are consumed',
      () async {
    for (final lateError in [false, true]) {
      final pending = Completer<http.Response>();
      final listener = Listener();
      final token = DeekWebCancellationToken();
      var calls = 0;
      final arrived = Completer<void>();
      final client = DeekWebClient(client: MockClient((_) {
        if (++calls == 2) {
          arrived.complete();
        }
        return pending.future;
      }))
        ..addListener(listener);
      final first = client.executeRequestWithOptions(Request(),
          options: DeekWebExecutionOptions(cancellationToken: token));
      final second = client.executeRequestWithOptions(Request(),
          options: DeekWebExecutionOptions(cancellationToken: token));
      await arrived.future;
      token.cancel();
      expect((await first).exception, isA<DeekWebCancelledException>());
      expect((await second).exception, isA<DeekWebCancelledException>());
      if (lateError) {
        pending.completeError(Exception('late'));
      } else {
        pending.complete(http.Response('late', 200));
      }
      await Future<void>.delayed(Duration.zero);
      expect(listener.errors.length, 2);
      expect(listener.successes, isEmpty);
      client.close();
    }
  });
  test('cancellation during async parsing discards result and preserves status',
      () async {
    final parsing = Completer<void>();
    final parsed = Completer<String>();
    final token = DeekWebCancellationToken();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 202)));
    final listener = Listener();
    client.addListener(listener);
    final future = client.executeRequestWithOptions(AsyncRequest((_) {
      parsing.complete();
      return parsed.future;
    }), options: DeekWebExecutionOptions(cancellationToken: token));
    await parsing.future;
    token.cancel();
    final result = await future;
    expect(result.exception, isA<DeekWebCancelledException>());
    expect(result.statusCode, 202);
    parsed.complete('discard');
    await Future<void>.delayed(Duration.zero);
    expect(listener.errors, [202]);
    client.close();
  });
  test('async failure policy, portable JSON and synchronous hook', () async {
    final client = DeekWebClient(
        client: MockClient((_) async => http.Response('[]', 200)));
    const failure = FormatException('bad');
    final request = AsyncRequest((_) async {
      throw failure;
    });
    expect(() => request.parseResponse(DeekWebHttpResponse(statusCode: 200)),
        throwsUnsupportedError);
    await expectLater(client.executeRequest(request), throwsA(same(failure)));
    final result = await client.executeRequestWithOptions(request,
        options: DeekWebExecutionOptions(captureParserExceptions: true));
    expect(result.exception!.cause, same(failure));
    for (final background in [false, true]) {
      expect(await decodeJsonAsync('{"a":[1]}', background: background), {
        'a': [1]
      });
      await expectLater(decodeJsonAsync('bad', background: background),
          throwsFormatException);
    }
    client.close();
  });
  test('tested auth and bounded GET retry examples', () async {
    var attempts = 0;
    final client = DeekWebClient(
        interceptors: [
          BoundedGetRetry(),
          OriginAuth(Uri.parse('https://example.com'), () async => 'token')
        ],
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer token');
          return http.Response('response', ++attempts == 1 ? 503 : 200);
        }));
    expect(await client.send(Request(url: 'https://example.com/path')),
        'response');
    expect(attempts, 2);
    await expectLater(
        client.send(Request(url: 'https://other.example')), throwsStateError);
    client.close();
  });
  test('timeout validation and escaped caller-controlled logging', () async {
    expect(() => DeekWebExecutionOptions(timeout: Duration.zero),
        throwsArgumentError);
    expect(() => DeekWebExecutionOptions(timeout: const Duration(seconds: -1)),
        throwsArgumentError);
    final logger = Logger();
    final client = DeekWebClient(
        logger: logger,
        client: MockClient((_) async => http.Response('', 200)));
    await client.executeRequest(NamedRequest());
    expect(logger.lines.join(), contains(r'secret\u000aforged'));
    expect(logger.lines.join(), contains(r'custom\u000d\u000aorigin'));
    expect(logger.lines.join(), isNot(contains('\n')));
    client.close();
  });
  testWidgets(
      'cancelling retry delay releases its timer without a second attempt',
      (tester) async {
    final token = DeekWebCancellationToken();
    var attempts = 0;
    final listener = Listener();
    final client = DeekWebClient(
        interceptors: [
          Interceptor((r, c) async {
            await c.proceed(r);
            await c.delay(const Duration(hours: 1));
            return c.proceed(r);
          })
        ],
        client: MockClient((_) async {
          attempts++;
          return http.Response('', 503);
        }))
      ..addListener(listener);
    final result = client.executeRequestWithOptions(Request(),
        options: DeekWebExecutionOptions(cancellationToken: token));
    await tester.pump();
    token.cancel();
    expect((await result).exception, isA<DeekWebCancelledException>());
    await tester.pump();
    expect(attempts, 1);
    expect(listener.errors.length, 1);
    client.close();
  });
  testWidgets('deadline covers async parsing and close races settle once',
      (tester) async {
    final parsed = Completer<String>();
    final listener = Listener();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)))
          ..addListener(listener);
    final result = client.executeRequestWithOptions(
        AsyncRequest((_) => parsed.future),
        options: DeekWebExecutionOptions(timeout: const Duration(seconds: 2)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    client.close();
    expect((await result).exception, isA<DeekWebTimeoutException>());
    parsed.complete('late');
    await tester.pump();
    expect(listener.errors, [200]);
    expect(listener.successes, isEmpty);
  });
  test('synchronous parsing checks cancellation again before accepting data',
      () async {
    final token = DeekWebCancellationToken();
    final client =
        DeekWebClient(client: MockClient((_) async => http.Response('', 200)));
    final result = await client.executeRequestWithOptions(Request(parse: (_) {
      token.cancel();
      return 'discarded';
    }), options: DeekWebExecutionOptions(cancellationToken: token));
    expect(result.data, isNull);
    expect(result.exception, isA<DeekWebCancelledException>());
    expect(result.statusCode, 200);
    client.close();
  });
}
