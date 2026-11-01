import 'package:deekweb/deekweb.dart';

/// Credential injection is restricted to one trusted HTTPS origin.
class OriginAuth extends DeekWebInterceptor {
  final Uri trustedOrigin;
  final Future<String> Function() loadToken;
  OriginAuth(this.trustedOrigin, this.loadToken);

  @override
  Future<DeekWebHttpResponse> intercept(
      DeekWebPreparedRequest request, DeekWebInterceptorChain chain) async {
    if (request.uri.scheme != 'https' ||
        request.uri.origin != trustedOrigin.origin) {
      throw StateError('Credentials require the trusted HTTPS origin');
    }
    final token = await loadToken();
    chain.throwIfCancelled();
    return chain.proceed(request.copyWith(
      headers: {...request.headers, 'Authorization': 'Bearer $token'},
    ));
  }
}

/// Explicit bounded GET policy. Mutation retries require server idempotency.
class BoundedGetRetry extends DeekWebInterceptor {
  @override
  Future<DeekWebHttpResponse> intercept(
      DeekWebPreparedRequest request, DeekWebInterceptorChain chain) async {
    var response = await chain.proceed(request);
    if (request.method == 'GET' && response.statusCode == 503) {
      await chain.delay(const Duration(milliseconds: 100));
      response = await chain.proceed(request);
    }
    return response;
  }
}
