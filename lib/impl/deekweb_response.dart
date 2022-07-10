// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

import 'deekweb_request_exception.dart';
import 'deekweb_request.dart';

/// The response returned from the server from *DeekWebClient*.
/// Takes in two strongly typed entities, *DeekWebRequest* and *ResponseType*.
///
/// These represent the request used to call the service, as well as the
/// expected response type.
class DeekWebResponse<RequestType extends DeekWebRequest, ResponseType> {
  /// The parsed response from the server. Will be null if there was no
  /// response.
  final ResponseType? data;

  /// The request that was made to generate this response.
  final DeekWebRequest<ResponseType> request;

  /// The status code for the response, if any. Will be null if calling the
  /// server failed.
  final int? statusCode;

  /// The exception generated when calling the server, if any. This will be
  /// null for successful request or for standard server errors.
  final DeekWebException? exception;

  /// The amount of time, in milliseconds, that it took to call the server
  /// and parse the response.
  final int latencyMs;

  /// If the response from the server appears to be successful, as determined
  /// by there being no *exception* and a *statusCode* in the 200-300 range.
  bool get wasSuccessful {
    var status = statusCode;
    return exception == null && status != null && status >= 200 && status < 400;
  }

  /// Creates a *DeekWebResponse* from a response from the server.
  DeekWebResponse.fromResponse(
      {required this.request,
      required this.data,
      required this.statusCode,
      required this.latencyMs})
      : exception = null;

  /// Creates a *DeekWebResponse* from a status code, with no response data.
  DeekWebResponse.fromCode(
      {required this.request,
      this.statusCode,
      this.exception,
      required this.latencyMs})
      : data = null;

  /// Creates a *DeekWebResponse* from an error, with no other response data.
  DeekWebResponse.fromError({required this.request, required this.exception})
      : latencyMs = 0,
        data = null,
        statusCode = null;
}
