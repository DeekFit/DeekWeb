// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

import 'dart:typed_data';
import 'package:http/http.dart';

/// The raw response returned from the server, with no processing or parsing.
class DeekWebHttpResponse {
  final Response _response;

  /// Creates a new *DeekWebHttpResponse* from an *http.Response* object.
  DeekWebHttpResponse.fromResponse(Response response) : _response = response;

  /// Gets the HTTP status code for the response.
  int get statusCode => _response.statusCode;

  /// Gets the HTTP reason phrase for the status.
  String? get reasonPhrase => _response.reasonPhrase;

  /// Gets the content length in bytes for the body of the response.
  /// If no body or size is unknown, returns null.
  int? get contentLength => _response.contentLength;

  /// Gets the headers for the response message.
  Map<String, String> get headers => _response.headers;

  /// Gets the body of the response, represented as a list of bytes.
  Uint8List get bodyBytes => _response.bodyBytes;

  /// Gest the body of the response, represented as a String.
  String get body => _response.body;
}
