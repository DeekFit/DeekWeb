import 'dart:typed_data';
import 'package:deekweb/deekweb.dart';
import 'package:deekweb/impl/deekweb_interceptor.dart'
    show serializedBodyForTransport;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'core_test.dart' show Request, Logger;

class _LoggingRequest extends Request {
  int loggingReads = 0;
  final failure = StateError('logging getter');
  @override
  String get uriForLogging {
    loggingReads++;
    throw failure;
  }
}

class _PassThrough extends DeekWebInterceptor {
  _PassThrough(this.seen, {this.header = false, this.retry = false});
  final List<DeekWebPreparedRequest> seen;
  final bool header;
  final bool retry;
  @override
  Future<DeekWebHttpResponse> intercept(
      DeekWebPreparedRequest request, DeekWebInterceptorChain chain) async {
    seen.add(request);
    final next = header
        ? request.copyWith(headers: {...request.headers, 'x-test': 'value'})
        : request;
    if (retry) {
      await chain.proceed(next);
    }
    return chain.proceed(next);
  }
}

void main() {
  test('disabled logging never evaluates logging-only URI getters', () async {
    var dispatched = 0;
    final request = _LoggingRequest();
    final client = DeekWebClient(client: MockClient((_) async {
      dispatched++;
      return http.Response('ok', 200);
    }));
    expect((await client.executeRequest(request)).data, 'ok');
    expect(request.loggingReads, 0);
    expect(dispatched, 1);
    client.close();
  });

  test(
      'enabled logging retains original getter failure and preparation boundary',
      () async {
    var dispatched = false;
    final request = _LoggingRequest();
    final client = DeekWebClient(
        logger: Logger(),
        client: MockClient((_) async {
          dispatched = true;
          return http.Response('', 200);
        }));
    await expectLater(
        client.executeRequest(request), throwsA(same(request.failure)));
    expect(request.loggingReads, 1);
    expect(dispatched, false);
    client.close();
  });

  test(
      'header-only copies share immutable storage and public byte copies remain mutable',
      () {
    final original = Uint8List.fromList([1, 2, 3]);
    final request = DeekWebPreparedRequest(
        method: 'POST',
        uri: Uri.parse('https://example.com'),
        bodyBytes: original);
    original[0] = 99;
    final shared = serializedBodyForTransport(request);
    expect(shared, [1, 2, 3]);
    for (final copy in [
      request.copyWith(),
      request.copyWith(headers: {'x': 'y'}),
      request.copyWith(uri: Uri.parse('https://example.com/new'))
    ]) {
      expect(identical(serializedBodyForTransport(copy), shared), true);
    }
    expect(() => shared[0] = 8, throwsUnsupportedError);
    expect(() => shared.buffer.asUint8List()[0] = 8, throwsUnsupportedError);
    final exposed = request.bodyBytes;
    exposed[0] = 8;
    exposed.buffer.asUint8List()[1] = 9;
    expect(request.bodyBytes, [1, 2, 3]);

    final replacement = Uint8List.fromList([4, 5, 6]);
    final changed = request.copyWith(bodyBytes: replacement);
    replacement[0] = 0;
    expect(changed.bodyBytes, [4, 5, 6]);
    expect(identical(serializedBodyForTransport(changed), shared), false);
  });

  test(
      'large payload storage is shared across interceptor hops header changes and retries',
      () async {
    final seen = <DeekWebPreparedRequest>[];
    final attempts = <http.BaseRequest>[];
    final bodies = <Uint8List>[];
    final payload = Uint8List(20 * 1024 * 1024)..[0] = 42;
    final client = DeekWebClient(
      interceptors: [
        _PassThrough(seen, retry: true),
        _PassThrough(seen, header: true),
        _PassThrough(seen)
      ],
      client: MockClient.streaming((request, stream) async {
        attempts.add(request);
        final bytes = (request as http.Request).bodyBytes;
        bodies.add(bytes);
        expect(bytes.first, 42);
        expect(bytes.length, payload.length);
        expect(() => bytes[0] = 0, throwsUnsupportedError);
        await stream.drain<void>();
        return http.StreamedResponse(Stream<List<int>>.value(const []), 200);
      }),
    );
    expect(
        (await client
                .executeRequest(Request(verb: Method.post, payload: payload)))
            .wasSuccessful,
        true);
    expect(attempts, hasLength(2));
    expect(identical(attempts[0], attempts[1]), false);
    final storage = serializedBodyForTransport(seen.first);
    expect(identical(storage, payload), false);
    expect(
        seen.every((request) =>
            identical(serializedBodyForTransport(request), storage)),
        true);
    expect(bodies.every((body) => identical(body, storage)), true);
    expect(payload.first, 42);
    client.close();
  });
}
