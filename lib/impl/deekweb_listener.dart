// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

/// A listener to be invoked by the *DeekWebClient* when
/// a request starts or stops processing. Each request will be given a
/// unique ID which is represented by the *requestId* parameter.
abstract class DeekWebListener {
  /// Notifies the listener that a new request has started.
  /// *requestId* is a unique ID for the requset
  /// *requestType* is the name provided by the *DeekWebRequest*
  void requestStarted({required String requestId, required String requestType});

  /// Notifies the listneer that a request has completed succesfully.
  /// *requestId* is the unique ID for the request.
  /// *statusCode* is the HTTP response code returned from the server.
  void requestCompleted({required String requestId, required int statusCode});

  /// Notifies the listener that a request has completed with an error.
  /// *requestId* is the unique ID for the request. If there was a response
  /// from the server, it is included in *statusCode*, otherwise null.
  /// *error* is the error thrown by the sytem, if any.
  void requestCompletedWithError(
      {required String requestId, int? statusCode, String? error});
}
