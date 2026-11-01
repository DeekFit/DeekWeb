// Local-only fixture for browser transport abortion tests. Never proxies traffic.
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18764);
  stdout.writeln('Browser fixture listening on 127.0.0.1:18764');
  server.listen((request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Headers', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    if (request.method == 'OPTIONS') {
      await response.close();
      return;
    }
    if (request.uri.path == '/echo') {
      response.headers.contentType = ContentType.binary;
      await response.addStream(request);
      await response.close();
      return;
    }
    if (request.uri.path == '/ok') {
      response.write('ok');
      await response.close();
      return;
    }
    if (request.uri.queryParameters['download'] == 'true') {
      response.write('partial');
      await response.flush();
    }
    // Held open intentionally. Test cancellation must abort the real fetch.
  });
}
