// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'deekweb_http_response.dart';

/// Base class for a strongly-typed request to a server.
/// *<T>* is the type you expect the server to return for your request.
///
/// Your code should extend *DeekWebRequest* and override the properties
/// as appropriate.
///
/// *uri*, *method* are required overrides. All others are optional.
abstract class DeekWebRequest<T> {
  /// Creates a default *DeekWebRequest*.
  const DeekWebRequest();

  /// Gets a name for this request type. The *DeekWebClient* will use this
  /// name for logging and notifying listeners. By default, it will simply
  /// return the runtimeType name of your *DeekWebRequest* implementation.
  String get name => runtimeType.toString();

  /// Gets the HTTP method for this request, e.g. GET, POST, DELETE, etc.
  Method get method;

  /// Gets the absolute URI to use when making the request.
  Uri get uri;

  /// Gets a URI to be used in logging requests. By default just returns the
  /// *uri* property. If your URI contains any personal or identifiable
  /// information, consider overriding *uriForLogging* to avoid logging
  /// personal information.
  String get uriForLogging => uri.toString();

  /// Gets the body for the request. Null by default.
  dynamic get body => null;

  /// Gets the encoding to use for the request. Null by default.
  Encoding? get encoding => null;

  /// Gets the headers to include with the request. Empty by default.
  Map<String, String> get headers => {};

  /// Method that parses the response from the server. This method will be
  /// invoked by *DeekWebClient* when a respones completes with the
  /// raw response data from the server, which you can use to parse it
  /// into *<T>*.
  T? parseResponse(DeekWebHttpResponse response) => null;
}

/// Represents a REST request verb.
enum Method {
  /// DELETE request, includes a URI and headers.
  ///
  /// Deletes data on the server.
  delete,

  /// GET request, includes a URI and headers.
  ///
  /// Used to retrieve data from the server.
  get,

  /// HEAD request, includes a URI and headers.
  ///
  /// Retrieves headers for a request.
  head,

  /// PATCH request, includes a URI, headers, body, and encoding.
  ///
  /// Modifies an existing record on the server.
  patch,

  /// POST request, includes a URI, headers, body, and encoding.
  ///
  /// Creates new data on the server.
  post,

  /// PUT request, includes a URI, headers, body, and encoding.
  ///
  /// Updates or replaces existing data on the server.
  put
}

/// Extension method to convert a *Method* enum to a string.
extension MethodExt on Method {
  /// Gets the name of the HTTP method.
  String get name => describeEnum(this);
}
