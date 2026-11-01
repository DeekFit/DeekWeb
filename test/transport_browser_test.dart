@TestOn('browser')
library;

import 'package:deekweb/deekweb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'core_test.dart' show Request;
import 'support/probe.dart';

class _HeaderOnly extends DeekWebInterceptor {
  @override
  Future<DeekWebHttpResponse> intercept(
          DeekWebPreparedRequest request, DeekWebInterceptorChain chain) =>
      chain.proceed(
          request.copyWith(headers: {...request.headers, 'x-test': 'echo'}));
}

void main() {
  test(
      'default browser transport posts immutable prepared bytes after a header-only change',
      () async {
    final client = DeekWebClient(interceptors: [_HeaderOnly()]);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final response = await client.send(Request(
            url: 'http://127.0.0.1:18764/echo',
            verb: Method.post,
            payload: <int>[0, 128, 255],
            parse: (response) => response.bodyBytes.join(',')));
        expect(response, '0,128,255');
      }
    } finally {
      client.close();
    }
  });

  for (final download in [false, true]) {
    test(
        'default browser transport aborts ${download ? 'download' : 'headers'} and remains reusable',
        () async {
      final probe = Probe();
      final client = DeekWebClient(client: probe);
      final token = DeekWebCancellationToken();
      try {
        final future = client.executeRequestWithOptions(
            Request(url: 'http://127.0.0.1:18764/stall?download=$download'),
            options: DeekWebExecutionOptions(cancellationToken: token));
        if (download) {
          await probe.headers.future.timeout(const Duration(seconds: 5));
        } else {
          // A bounded local fixture delay allows fetch to enter header waiting.
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        token.cancel();
        expect((await future).exception, isA<DeekWebCancelledException>());
        expect(await probe.aborted.future.timeout(const Duration(seconds: 5)),
            isA<http.RequestAbortedException>());
        expect(
            await client.send(Request(url: 'http://127.0.0.1:18764/ok')), 'ok');
      } finally {
        client.close();
        probe.close();
      }
    });
  }
}
