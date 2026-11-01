import 'dart:typed_data';
import 'dart:collection';
import 'deekweb_http_response.dart';

/// Serialized request data. Headers are case-insensitive with lowercase keys.
/// Every byte-buffer read is a defensive copy.
final class DeekWebPreparedRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List _bytes;

  DeekWebPreparedRequest(
      {required this.method,
      required this.uri,
      Map<String, String> headers = const {},
      List<int> bodyBytes = const []})
      : headers = UnmodifiableMapView(_HeaderMap(headers)),
        _bytes = Uint8List.fromList(bodyBytes).asUnmodifiableView();

  DeekWebPreparedRequest._(this.method, this.uri, this.headers, this._bytes);

  /// A mutable defensive copy for callers that need to inspect or edit bytes.
  Uint8List get bodyBytes => Uint8List.fromList(_bytes);

  /// Unchanged data shares the existing immutable snapshot. New caller-owned
  /// headers or bytes are copied at this ownership boundary.
  DeekWebPreparedRequest copyWith(
          {String? method,
          Uri? uri,
          Map<String, String>? headers,
          List<int>? bodyBytes}) =>
      DeekWebPreparedRequest._(
        method ?? this.method,
        uri ?? this.uri,
        headers == null
            ? this.headers
            : UnmodifiableMapView(_HeaderMap(headers)),
        bodyBytes == null
            ? _bytes
            : Uint8List.fromList(bodyBytes).asUnmodifiableView(),
      );
}

/// @nodoc
// Implementation-only access across Dart libraries. The main export hides this
// helper. The returned view and its buffer are read-only, including to custom
// transports; package:http requires replacing rather than mutating bodyBytes.
Uint8List serializedBodyForTransport(DeekWebPreparedRequest request) =>
    request._bytes;

abstract class DeekWebInterceptor {
  Future<DeekWebHttpResponse> intercept(
      DeekWebPreparedRequest request, DeekWebInterceptorChain chain);
}

abstract class DeekWebInterceptorChain {
  bool get isCancelled;
  DateTime? get deadline;
  Duration? get remaining;
  void throwIfCancelled();
  Future<void> delay(Duration duration);
  Future<DeekWebHttpResponse> proceed(DeekWebPreparedRequest request);
}

// HTTP field names are case-insensitive. Expose canonical keys so spreading
// followed by an explicit differently-cased replacement has last-write wins.
class _HeaderMap extends MapBase<String, String> {
  final Map<String, String> _values = {};
  _HeaderMap(Map<String, String> source) {
    addAll(source);
  }
  @override
  String? operator [](Object? key) =>
      key is String ? _values[key.toLowerCase()] : null;
  @override
  void operator []=(String key, String value) {
    _values[key.toLowerCase()] = value;
  }

  @override
  bool containsKey(Object? key) =>
      key is String && _values.containsKey(key.toLowerCase());
  @override
  Iterable<String> get keys => _values.keys;
  @override
  void clear() => _values.clear();
  @override
  String? remove(Object? key) =>
      key is String ? _values.remove(key.toLowerCase()) : null;
}
