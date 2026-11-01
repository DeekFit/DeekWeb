/// A sticky, shareable signal. Cancelling one token cancels all attached work.
class DeekWebCancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _callbacks = {};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }

  /// Returns a detach callback. Registration itself does not invoke callbacks.
  /// Already-cancelled tokens do not retain registrations; check [isCancelled]
  /// after attaching to observe sticky cancellation.
  void Function() attach(void Function() callback) {
    if (_cancelled) {
      return () {};
    }
    _callbacks.add(callback);
    return () {
      _callbacks.remove(callback);
    };
  }
}

class DeekWebExecutionOptions {
  final Duration? timeout;
  final DeekWebCancellationToken? cancellationToken;
  final bool captureParserExceptions;

  DeekWebExecutionOptions(
      {this.timeout,
      this.cancellationToken,
      this.captureParserExceptions = false}) {
    if (timeout != null && timeout! <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
  }
}
