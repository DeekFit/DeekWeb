/// A structured execution failure. Raw causes are never logged by the client.
class DeekWebException implements Exception {
  final Object? cause;
  final StackTrace? stackTrace;

  DeekWebException({this.cause, this.stackTrace});
  DeekWebException.fromException(Exception e, {this.stackTrace}) : cause = e;
  DeekWebException.fromError(Error e, {this.stackTrace}) : cause = e;

  Type get errorType => cause?.runtimeType ?? runtimeType;

  @override
  String toString() => cause?.toString() ?? runtimeType.toString();
}

class DeekWebParseException extends DeekWebException {
  DeekWebParseException(Object cause, StackTrace stackTrace)
      : super(cause: cause, stackTrace: stackTrace);
}

class DeekWebClientClosedException extends DeekWebException {}

class DeekWebTimeoutException extends DeekWebException {}

class DeekWebCancelledException extends DeekWebException {}

class DeekWebHttpException extends DeekWebException {
  final int? statusCode;
  final Object? data;
  DeekWebHttpException({required this.statusCode, this.data});
}
