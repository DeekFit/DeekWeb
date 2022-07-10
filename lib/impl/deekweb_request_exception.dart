// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

/// An exception generated while making a request with *DeekWebClient*.
class DeekWebException implements Exception {
  final Exception? _exception;
  final Error? _error;

  /// Creates an empty exception object
  DeekWebException()
      : _exception = null,
        _error = null;

  /// Creates a *DeekWebException* from a generic Flutter exception
  DeekWebException.fromException(Exception e)
      : _exception = e,
        _error = null;

  /// Creates a *DeekWebException* from an error.
  /// Generally you should consider Errors to be fatal, hence they are separate
  /// from Exceptions. However, parsing errors will result in a TypeError,
  /// and the app shouldn't crash if the server turns an unexpected value.
  DeekWebException.fromError(Error e)
      : _error = e,
        _exception = null;

  /// Gets the underlying type of the error that generated the
  /// *DeekWebException*
  Type get errorType =>
      _exception?.runtimeType ?? _error?.runtimeType ?? runtimeType;

  /// Returns the String format of the error
  @override
  String toString() {
    if (_exception != null) {
      return _exception.toString();
    } else if (_error != null) {
      return _error.toString();
    } else {
      return runtimeType.toString();
    }
  }
}
