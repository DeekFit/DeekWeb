// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

import 'dart:io';

import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'deekweb_listener.dart';
import 'deekweb_logger.dart';
import 'deekweb_http_response.dart';
import 'deekweb_request_exception.dart';
import 'deekweb_request.dart';
import 'deekweb_response.dart';

/// A strongly typed REST client.
class DeekWebClient {
  static const String _defaultCvHeader = "cv-in";

  final DeekWebLogger? _logger;
  final Set<DeekWebListener> _listeners = <DeekWebListener>{};

  /// Gets or sets whether or not a CV (Correleation Vector) header should
  /// be sent with requests. If true, the default header will be supplied.
  /// You can override the header name by setting the *cvHeader* property.
  bool includeCvHeader;

  /// Gets or sets the CV (Correleation Vector) header to be sent with every
  /// request. This header will only be sent if the *includeCvHeader* property
  /// is also set to true.
  String cvHeader;

  /// Creates a new instance of the *DeekWebClient* that can be used to
  /// execute *DeekWebRequest*s.
  ///
  /// Although you may re-use *DeekWebClient* for many requests, the class
  /// itself is not stateful so you can recreate it on demand when you
  /// need to make requests.
  ///
  /// You may include a *logger* which will be used to log information about
  /// request status.
  ///
  /// The *includeCvHeader* and *cvHeader* properties are used to request
  /// a unique Correlation Vector be sent with every request.
  DeekWebClient(
      {DeekWebLogger? logger,
      this.includeCvHeader = false,
      this.cvHeader = _defaultCvHeader})
      : _logger = logger;

  /// Executes a *DeekWebRequest* asynchronously.
  Future<DeekWebResponse<RequestType, ResponseType>>
      executeRequest<RequestType extends DeekWebRequest, ResponseType>(
          DeekWebRequest<ResponseType> request) async {
    // Generate a new CV and notify listeners.
    // TODO: Optionally pass in the CV with the request.
    String requestId = const Uuid().v4().toString();
    _notifyRequestStarted(requestId, request.name);

    var latencyTimer = Stopwatch();
    latencyTimer.start();

    late DeekWebResponse<RequestType, ResponseType> result;
    try {
      _logger?.info(
          "DeekWebClient: [$requestId] Starting ${request.method} request ${request.name} to ${request.uriForLogging}");

      // Execute the request and mark the time
      var response = await _executeRequest(request, requestId);
      int httpTime = latencyTimer.elapsedMilliseconds;
      _logger?.verbose(
          "DeekWebClient: [$requestId] http time: $httpTime ms, response code ${response.statusCode}");

      // Handle the response, including parsing it to the <ResponseType>
      result = _handleResponse(response, request, latencyTimer, requestId);
      int parseTime = latencyTimer.elapsedMilliseconds - httpTime;
      _logger?.verbose("DeekWebClient: [$requestId] parse time: $parseTime ms");

      // Notify listeners that the request is complete
      _logger?.verbose(
          "DeekWebClient: [$requestId] Completed ${request.name} in ${result.latencyMs} ms");
      _notifyRequestCompleted(requestId, response.statusCode);
    } on SocketException catch (e) {
      // SocketException typically happens when there is no / broken network
      // connection.
      _logger?.error("DeekWebClient: [$requestId] SocketException: $e");
      result = DeekWebResponse.fromError(
          request: request, exception: DeekWebException.fromException(e));
      _notifyRequestError(requestId, error: "SocketException");
    }
    return result;
  }

  /// Adds a new *listener* to be notified of request status.
  void addListener(DeekWebListener listener) => _listeners.add(listener);

  /// Removes a *listener* from further request status updates.
  /// Returns true if listener was found and removed, false if not found.
  bool removeListener(DeekWebListener listener) => _listeners.remove(listener);

  /// Executes the request.
  Future<Response> _executeRequest(DeekWebRequest request, String requestId) {
    var headers = request.headers;

    // If the includeCvHeader propert is set, include the requestId as a
    // header.
    if (includeCvHeader) {
      headers[cvHeader] = requestId;
    }

    // This switch statement is kinda ugly, but hey...it does its job.
    // Make the appropriate request based on the request method.
    switch (request.method) {
      case Method.delete:
        return http.delete(request.uri, headers: headers);
      case Method.get:
        return http.get(request.uri, headers: headers);
      case Method.head:
        return http.head(request.uri, headers: headers);
      case Method.patch:
        return http.patch(request.uri,
            headers: headers, body: request.body, encoding: request.encoding);
      case Method.post:
        return http.post(request.uri,
            headers: headers, body: request.body, encoding: request.encoding);
      case Method.put:
        return http.put(request.uri,
            headers: headers, body: request.body, encoding: request.encoding);
    }
  }

  /// Handles and parse ther esponse from the server.
  DeekWebResponse<RequestType, ResponseType>
      _handleResponse<RequestType extends DeekWebRequest, ResponseType>(
          Response response,
          DeekWebRequest<ResponseType> request,
          Stopwatch latencyTimer,
          String requestId) {
    late DeekWebResponse<RequestType, ResponseType> result;
    try {
      // Get the raw response and pass it to the request for parsing.
      _logger?.verbose("DeekWebClient: [$requestId] Parsing response");
      var wrappedResponse = DeekWebHttpResponse.fromResponse(response);
      ResponseType? parsedResponse = request.parseResponse(wrappedResponse);

      // Construct a respones with the parsed data.
      result = DeekWebResponse.fromResponse(
          request: request,
          data: parsedResponse,
          statusCode: response.statusCode,
          latencyMs: latencyTimer.elapsedMilliseconds);
    } on TypeError catch (e) {
      // This will be thrown if there is a parsing error in the *parseResponse*
      // method of the DeekWebRequest.
      _logger
          ?.error("DeekWebClient: [$requestId] TypeError parsing response: $e");
      result = DeekWebResponse.fromCode(
          request: request,
          statusCode: response.statusCode,
          exception: DeekWebException.fromError(e),
          latencyMs: latencyTimer.elapsedMilliseconds);
      _notifyRequestError(requestId,
          statusCode: response.statusCode, error: "Parsing error");
    }

    return result;
  }

  /// Notifies any listeners that a request has started executing.
  void _notifyRequestStarted(String requestId, String requestType) {
    for (var listener in _listeners) {
      listener.requestStarted(requestId: requestId, requestType: requestType);
    }
  }

  /// Notifies any listeners that a request has completed execution.
  void _notifyRequestCompleted(String requestId, int statusCode) {
    for (var listener in _listeners) {
      listener.requestCompleted(requestId: requestId, statusCode: statusCode);
    }
  }

  /// Notifies any listeners that a request has completed with an error.
  void _notifyRequestError(String requestId, {int? statusCode, String? error}) {
    for (var listener in _listeners) {
      listener.requestCompletedWithError(
          requestId: requestId, statusCode: statusCode, error: error);
    }
  }
}
