import 'dart:async';
import 'package:http/http.dart' as http;

class Probe extends http.BaseClient {
  final inner = http.Client();
  final aborted = Completer<Object>();
  final headers = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await inner.send(request);
      if (!headers.isCompleted) {
        headers.complete();
      }
      return http.StreamedResponse(
          response.stream.handleError((Object e, StackTrace s) {
        if (!aborted.isCompleted) {
          aborted.complete(e);
        }
        Error.throwWithStackTrace(e, s);
      }), response.statusCode, headers: response.headers);
    } catch (e) {
      if (!aborted.isCompleted) {
        aborted.complete(e);
      }
      rethrow;
    }
  }

  @override
  void close() => inner.close();
}
