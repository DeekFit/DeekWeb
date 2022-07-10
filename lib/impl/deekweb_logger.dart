// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

/// A logger abstraction used by *DeekWebClient*.
///
/// Note that you do not specifiy a minimum log level to *DeekWebClient*,
/// that logic is up to your implementation.
abstract class DeekWebLogger {
  /// Logs a verbose/debug level message.
  verbose(String logLine);

  /// Logs an informational level message.
  info(String logLine);

  /// Logs a warning message.
  warn(String logLine);

  /// Logs an error message. If there is an exception included, it will be
  /// provided in *e*.
  error(String logLine, {Exception? e});
}
