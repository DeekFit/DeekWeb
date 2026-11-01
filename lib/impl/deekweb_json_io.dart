import 'dart:convert';
import 'dart:isolate';

Future<dynamic> decode(String text) => Isolate.run(() => jsonDecode(text));
