import 'dart:convert';
import 'deekweb_json_default.dart' if (dart.library.io) 'deekweb_json_io.dart'
    as worker;

/// Background decoding is explicit. Model construction remains with the caller.
Future<dynamic> decodeJsonAsync(String text, {bool background = false}) async {
  if (background) {
    return worker.decode(text);
  }
  return jsonDecode(text);
}
