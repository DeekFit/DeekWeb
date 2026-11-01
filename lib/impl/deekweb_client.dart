import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'deekweb_http_response.dart';
import 'deekweb_execution_options.dart';
import 'deekweb_interceptor.dart';
import 'deekweb_listener.dart';
import 'deekweb_logger.dart';
import 'deekweb_request.dart';
import 'deekweb_request_exception.dart';
import 'deekweb_response.dart';

/// An app-scoped client. Injected transports remain owned by the caller.
class DeekWebClient {
  final DeekWebLogger? _logger;
  final http.Client? _borrowedClient;
  final List<DeekWebInterceptor> interceptors;
  http.Client? _ownedClient;
  bool _closed = false;
  final Set<DeekWebListener> _listeners = {};
  final Set<_Active> _active = {};
  bool includeCvHeader;
  String cvHeader;

  DeekWebClient(
      {DeekWebLogger? logger,
      http.Client? client,
      this.includeCvHeader = false,
      this.cvHeader = 'cv-in',
      List<DeekWebInterceptor> interceptors = const []})
      : _logger = logger,
        _borrowedClient = client,
        interceptors = List.unmodifiable(interceptors);

  Future<DeekWebResponse<RequestType, ResponseType>>
      executeRequest<RequestType extends DeekWebRequest, ResponseType>(
              DeekWebRequest<ResponseType> request) =>
          executeRequestWithOptions<RequestType, ResponseType>(request,
              options: DeekWebExecutionOptions());

  /// Does not route through legacy executeRequest overrides.
  Future<DeekWebResponse<RequestType, ResponseType>> executeRequestWithOptions<
          RequestType extends DeekWebRequest,
          ResponseType>(DeekWebRequest<ResponseType> request,
      {required DeekWebExecutionOptions options}) {
    if (_closed) {
      throw StateError('DeekWebClient is closed');
    }
    final execution =
        _Execution<RequestType, ResponseType>(this, request, options);
    _active.add(execution);
    execution.run();
    return execution.completer.future;
  }

  Future<T?> send<T>(DeekWebRequest<T> request) async =>
      _data(await executeRequest<DeekWebRequest<T>, T>(request));

  Future<T?> sendWithOptions<T>(DeekWebRequest<T> request,
          {required DeekWebExecutionOptions options}) async =>
      _data(await executeRequestWithOptions<DeekWebRequest<T>, T>(request,
          options: options));

  T? _data<T>(DeekWebResponse<DeekWebRequest<T>, T> response) {
    if (response.exception != null) {
      throw response.exception!;
    }
    if (!response.wasSuccessful) {
      throw DeekWebHttpException(
          statusCode: response.statusCode, data: response.data);
    }
    return response.data;
  }

  void addListener(DeekWebListener listener) => _listeners.add(listener);

  bool removeListener(DeekWebListener listener) {
    for (final execution in _active) {
      execution.relinquish(listener);
    }
    return _listeners.remove(listener);
  }

  /// Settles logical work and callbacks synchronously. Does not undo server work.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _ObserverFailure? failure;
    for (final execution in _active.toList()) {
      final observerFailure = execution.close();
      failure ??= observerFailure;
    }
    try {
      _ownedClient?.close();
    } catch (e, s) {
      failure ??= _ObserverFailure(e, s);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
  }

  http.Client get _transport =>
      _borrowedClient ?? (_ownedClient ??= http.Client());

  void _log(String Function() message, {_LogLevel level = _LogLevel.info}) {
    final logger = _logger;
    if (logger == null) {
      return;
    }
    // Logging-only getters retain their preparation-failure semantics when
    // enabled; only the logger's own Exceptions are isolated below.
    final line = message();
    try {
      switch (level) {
        case _LogLevel.info:
          logger.info(line);
        case _LogLevel.warn:
          logger.warn(line);
        case _LogLevel.error:
          logger.error(line);
      }
    } on Exception {
      // A logger failure cannot recursively log itself.
    }
  }

  static String _escape(String text) => text.replaceAllMapped(
      RegExp(
          r'[\x00-\x1f\x7f-\x9f\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff]'),
      (match) =>
          '\\u${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}');
}

enum _LogLevel { info, warn, error }

class _ObserverFailure {
  final Object error;
  final StackTrace stack;
  _ObserverFailure(this.error, this.stack);
}

abstract class _Active {
  final Set<DeekWebListener> started = {};
  _ObserverFailure? close();
  void relinquish(DeekWebListener listener);
}

class _Execution<R extends DeekWebRequest, T> extends _Active {
  final DeekWebClient client;
  final DeekWebRequest<T> request;
  final DeekWebExecutionOptions options;
  final abort = Completer<void>();
  Timer? timeoutTimer;
  final Set<Timer> delayTimers = {};
  void Function()? detach;
  DeekWebException? stopReason;
  final DateTime? deadline;
  final completer = Completer<DeekWebResponse<R, T>>();
  final watch = Stopwatch()..start();
  final String id = const Uuid().v4();
  final List<DeekWebListener> candidates;
  bool settled = false;
  int? status;

  _Execution(this.client, this.request, this.options)
      : candidates = client._listeners.toList(),
        deadline = options.timeout == null
            ? null
            : DateTime.now().add(options.timeout!);

  @override
  void relinquish(DeekWebListener listener) {
    candidates.remove(listener);
    started.remove(listener);
  }

  _ObserverFailure? stop(DeekWebException reason, {bool closing = false}) {
    if (settled) {
      return null;
    }
    stopReason = reason;
    return settle(
        closing: closing,
        result: DeekWebResponse<R, T>.fromCode(
            request: request,
            exception: reason,
            statusCode: status,
            latencyMs: watch.elapsedMilliseconds));
  }

  void check() {
    if (!settled && options.cancellationToken?.isCancelled == true) {
      stop(DeekWebCancelledException());
    }
    final timeout = options.timeout;
    if (!settled && timeout != null && watch.elapsed >= timeout) {
      stop(DeekWebTimeoutException());
    }
    if (settled) {
      throw stopReason ?? DeekWebClientClosedException();
    }
  }

  Future<DeekWebHttpResponse> dispatch(
      int index, DeekWebPreparedRequest prepared) async {
    check();
    if (index < client.interceptors.length) {
      return client.interceptors[index]
          .intercept(prepared, _Chain(this, index + 1));
    }
    final attempt = http.AbortableRequest(prepared.method, prepared.uri,
        abortTrigger: abort.future);
    attempt.headers.addAll(prepared.headers);
    attempt.bodyBytes = serializedBodyForTransport(prepared);
    final response =
        await http.Response.fromStream(await client._transport.send(attempt));
    check();
    return DeekWebHttpResponse.fromResponse(response);
  }

  void _observe(void Function() callback) {
    try {
      callback();
    } on Exception {
      client._log(() => 'request=$id failure=observer', level: _LogLevel.error);
    }
  }

  void run() async {
    try {
      final name = request.name;
      for (final listener in candidates.toList()) {
        if (settled) {
          return;
        }
        if (candidates.contains(listener) &&
            client._listeners.contains(listener)) {
          started.add(listener);
          _observe(
              () => listener.requestStarted(requestId: id, requestType: name));
        }
      }
      if (settled) {
        return;
      }
      detach = options.cancellationToken
          ?.attach(() => stop(DeekWebCancelledException()));
      check();
      final timeout = options.timeout;
      if (timeout != null) {
        timeoutTimer = Timer(
            timeout - watch.elapsed, () => stop(DeekWebTimeoutException()));
      }
      // Preparation has a separate boundary from transport and parsing.
      final method = request.method;
      final prepared = http.Request(method.name.toUpperCase(), request.uri);
      prepared.headers.addAll(Map<String, String>.of(request.headers));
      if (client.includeCvHeader) {
        prepared.headers[client.cvHeader] = id;
      }
      if (method == Method.post ||
          method == Method.put ||
          method == Method.patch) {
        final encoding = request.encoding;
        if (encoding != null) {
          prepared.encoding = encoding;
        }
        final body = request.body;
        if (body is String) {
          prepared.body = body;
        } else if (body is List) {
          prepared.bodyBytes = body.cast<int>();
        } else if (body is Map) {
          prepared.bodyFields = body.cast<String, String>();
        } else if (body != null) {
          throw ArgumentError('Unsupported request body');
        }
      }
      client._log(() =>
          'request=$id method=${prepared.method} name=${DeekWebClient._escape(name)} origin=${DeekWebClient._escape(request.uriForLogging)}');
      if (settled) {
        return;
      }
      final snapshot = DeekWebPreparedRequest(
          method: prepared.method,
          uri: prepared.url,
          headers: prepared.headers,
          bodyBytes: prepared.bodyBytes);
      late DeekWebHttpResponse response;
      try {
        response = await dispatch(0, snapshot);
      } on Exception catch (e, s) {
        if (!settled) {
          settle(
              result: DeekWebResponse<R, T>.fromError(
                  request: request,
                  exception: DeekWebException.fromException(e, stackTrace: s),
                  latencyMs: watch.elapsedMilliseconds));
        }
        return;
      }
      if (settled) {
        return;
      }
      status = response.statusCode;
      T? data;
      try {
        if (request is DeekWebAsyncRequest<T>) {
          data = await (request as DeekWebAsyncRequest<T>)
              .parseResponseAsync(response);
        } else {
          data = request.parseResponse(response);
        }
        check();
      } on Exception catch (e, s) {
        if (!options.captureParserExceptions) {
          rethrow;
        }
        if (!settled) {
          settle(
              result: DeekWebResponse<R, T>.fromCode(
                  request: request,
                  statusCode: status,
                  exception: DeekWebParseException(e, s),
                  latencyMs: watch.elapsedMilliseconds));
        }
        return;
      } on TypeError catch (e, s) {
        settle(
            result: DeekWebResponse<R, T>.fromCode(
                request: request,
                statusCode: status,
                exception: DeekWebParseException(e, s),
                latencyMs: watch.elapsedMilliseconds));
        return;
      }
      if (!settled) {
        settle(
            result: DeekWebResponse<R, T>.fromResponse(
                request: request,
                data: data,
                statusCode: status,
                latencyMs: watch.elapsedMilliseconds));
      }
    } catch (e, s) {
      if (!settled) {
        settle(error: e, stack: s);
      }
    }
  }

  _ObserverFailure? settle(
      {DeekWebResponse<R, T>? result,
      Object? error,
      StackTrace? stack,
      bool closing = false}) {
    if (settled) {
      return null;
    }
    settled = true;
    watch.stop();
    timeoutTimer?.cancel();
    detach?.call();
    for (final timer in delayTimers) {
      timer.cancel();
    }
    delayTimers.clear();
    if (!abort.isCompleted) {
      abort.complete();
    }
    Object? observerError;
    StackTrace? observerStack;
    void notify(void Function() callback) {
      try {
        _observe(callback);
      } catch (e, s) {
        observerError ??= e;
        observerStack ??= s;
      }
    }

    final failure = result?.exception;
    final category = error != null
        ? 'execution'
        : failure is DeekWebCancelledException
            ? 'cancelled'
            : failure is DeekWebClientClosedException
                ? 'closed'
                : failure is DeekWebTimeoutException
                    ? 'timeout'
                    : failure != null
                        ? 'structured'
                        : result?.wasSuccessful == true
                            ? 'none'
                            : 'http';
    final level = category == 'none'
        ? _LogLevel.info
        : category == 'http' || category == 'cancelled' || category == 'closed'
            ? _LogLevel.warn
            : _LogLevel.error;
    notify(() => client._log(
        () =>
            'request=$id status=${result?.statusCode ?? status ?? '-'} failure=$category elapsedMs=${watch.elapsedMilliseconds}',
        level: level));
    for (final listener in started.toList()) {
      if (!started.contains(listener) ||
          !client._listeners.contains(listener)) {
        continue;
      }
      notify(() {
        if (result?.wasSuccessful == true) {
          listener.requestCompleted(
              requestId: id, statusCode: result!.statusCode!);
        } else {
          listener.requestCompletedWithError(
              requestId: id,
              statusCode: result?.statusCode ?? status,
              error: error != null
                  ? 'execution'
                  : result?.exception != null
                      ? 'structured'
                      : 'http');
        }
      });
    }
    started.clear();
    client._active.remove(this);
    if (error != null) {
      completer.completeError(error, stack!);
    } else if (observerError != null && !closing) {
      completer.completeError(observerError!, observerStack!);
    } else {
      completer.complete(result!);
    }
    if (closing && observerError != null) {
      return _ObserverFailure(observerError!, observerStack!);
    }
    return null;
  }

  @override
  _ObserverFailure? close() =>
      stop(DeekWebClientClosedException(), closing: true);
}

class _Chain extends DeekWebInterceptorChain {
  final _Execution execution;
  final int next;
  bool _busy = false;
  _Chain(this.execution, this.next);

  @override
  bool get isCancelled =>
      execution.settled ||
      execution.options.cancellationToken?.isCancelled == true;
  @override
  DateTime? get deadline => execution.deadline;
  @override
  Duration? get remaining {
    final timeout = execution.options.timeout;
    if (timeout == null) {
      return null;
    }
    final value = timeout - execution.watch.elapsed;
    return value < Duration.zero ? Duration.zero : value;
  }

  @override
  void throwIfCancelled() => execution.check();

  @override
  Future<void> delay(Duration duration) async {
    throwIfCancelled();
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    execution.delayTimers.add(timer);
    try {
      await Future.any([done.future, execution.abort.future]);
      throwIfCancelled();
    } finally {
      timer.cancel();
      execution.delayTimers.remove(timer);
    }
  }

  @override
  Future<DeekWebHttpResponse> proceed(DeekWebPreparedRequest request) async {
    if (_busy) {
      throw StateError('Overlapping proceed calls are not supported');
    }
    _busy = true;
    try {
      throwIfCancelled();
      return await execution.dispatch(next, request);
    } finally {
      _busy = false;
    }
  }
}
