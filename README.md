# DeekWeb

A typed HTTP client for Dart and Flutter. Define a request and its response
parser together, then reuse the client for your application's lifetime.
Requires Dart 3.4 or later. The runtime depends on `http: ^1.6.0` and has no
Flutter dependency.

## Quick start

Add `deekweb: ^2.0.0` to your dependencies. This complete example fetches a todo
from JSONPlaceholder and parses its response into a Dart object:

```dart
import 'dart:convert';
import 'package:deekweb/deekweb.dart';

class Todo {
  const Todo({required this.id, required this.title});
  final int id;
  final String title;
}

class TodoRequest extends DeekWebRequest<Todo> {
  const TodoRequest(this.id);
  final int id;

  @override
  Method get method => Method.get;

  @override
  Uri get uri => Uri.https('jsonplaceholder.typicode.com', '/todos/$id');

  @override
  Todo? parseResponse(DeekWebHttpResponse response) {
    if (response.statusCode != 200) {
      return null;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Todo(id: json['id'] as int, title: json['title'] as String);
  }
}

Future<void> main() async {
  final client = DeekWebClient();
  try {
    final todo = await client.send(const TodoRequest(1));
    print(todo?.title);
  } finally {
    client.close();
  }
}
```

`send<T>` returns nullable successful data and throws on failure. To inspect
status and structured failures directly, use `executeRequest` instead:

```dart
final response = await client.executeRequest(const TodoRequest(1));
if (response.wasSuccessful) {
  print(response.data?.title);
}
```

## Requests and outcomes

Request subclasses supply `method`, `uri`, optional headers/body/encoding, and a
synchronous `parseResponse`. GET, HEAD and DELETE ignore bodies. POST, PUT and
PATCH use HTTP's string, byte and form serialization, including its encoding and
content-type rules. Caller headers are copied before adding an optional unique
correlation ID (`includeCvHeader: true`, header name `cv-in` by default).

`wasSuccessful` means no exception and HTTP 200–399. Unsuccessful HTTP responses
retain their status and parsed data. A successful response, including HTTP 204,
may have null data. No HTTP status is fabricated when no response exists.

| Failure | `executeRequest` behavior |
|---|---|
| Transport `Exception` | Failed response with cause, stack and measured latency |
| Parser `TypeError` | `DeekWebParseException` in a failed response, retaining HTTP status |
| Other parser exception or thrown object | Terminal failure notification, then original object/stack rethrown |
| Preparation/programming failure | Terminal failure notification, then rethrown |
| Timeout, cancellation or active closure | Typed failed response |

`DeekWebException` exposes `cause`, `stackTrace` and `errorType`. Its existing
constructors and `toString()` behavior remain available. Response `fromError`
accepts optional `latencyMs`, defaulting to zero.

The legacy generic execution signature is unchanged. `send` calls that virtual
method, so existing legacy client overrides remain effective. Configurable
execution has a separate override point: `executeRequestWithOptions` does not
route through a legacy `executeRequest` override.

## Client ownership and listeners

A client lazily creates one reusable owned HTTP transport. There is no global
pool. Passing `DeekWebClient(client: httpClient)` borrows that transport and never
closes it. Keep the wrapper alive for its owning app/service lifetime.

`close()` is idempotent and immediately rejects subsequent execution with
`StateError`, before any start callback. Before returning, it synchronously
settles active logical requests with `DeekWebClientClosedException`, delivers
eligible terminal callbacks and releases logical timers/subscriptions. It then
closes its owned transport. Close while listener dependencies are alive, then
detach listeners and dispose their dependencies. UI owners should guard updates
during disposal. Cancellation or closure cannot undo server-side effects.

Listeners are snapshotted at execution start. Only listeners whose start callback
began can receive completion. Added listeners affect later requests; removal
relinquishes outstanding notifications, even if re-added. Each execution settles
once, before terminal callbacks. Success uses `requestCompleted`; every other
outcome uses `requestCompletedWithError`, retaining known HTTP status.

Observer `Exception`s are isolated and logged safely. Start observer Errors or
other thrown objects stop additional starts and propagate after settling started
listeners. Terminal observer failures allow remaining callbacks and bookkeeping
to finish before propagating. An existing thrown execution failure takes
precedence. Structured response failures do not suppress terminal observer
Errors. During `close()`, request Futures keep their typed closed responses;
`close()` rethrows the first observer failure after completing all settlements
and owned transport closure.

## Logging and privacy

Pass a `DeekWebLogger` to enable logging. With no logger, logging-only getters
such as `uriForLogging` are never evaluated. Normal lifecycle logs use info;
HTTP failures, cancellation and closure use warn; execution, structured and
observer failures use error. Logger Exceptions are isolated at every severity.

Default `uriForLogging` contains only scheme, host and explicit port, preserving
IPv6 brackets. Credentials, path, query and fragment are omitted. Relative URIs,
missing hosts and unsupported schemes use `[unavailable-origin]`. Overrides
remain caller-controlled privacy boundaries. Control characters in names and
logging overrides are escaped. Client logs contain only request ID, method,
name, safe origin, status, failure category and measured timing—never raw
exceptions, headers or bodies. There is no body/header debug escape hatch.

## Options, cancellation and deadlines

```dart
final token = DeekWebCancellationToken();
final response = await client.executeRequestWithOptions(
  const TodoRequest(1),
  options: DeekWebExecutionOptions(
    timeout: const Duration(seconds: 10),
    cancellationToken: token,
    captureParserExceptions: true,
  ),
);
// token.cancel(); // Cancels all executions sharing this sticky, idempotent token.
```

Timeout is null by default; supplied durations must be positive. It covers the
whole logical operation: interceptors, retries, delays, download and async
parsing. It does not reset between attempts. Capture mode additionally converts
parser `Exception`s into `DeekWebParseException`; other Errors and arbitrary
thrown objects still propagate.

Pre-cancelled requests emit start and one cancellation event without dispatch.
Execution returns typed `DeekWebTimeoutException`, `DeekWebCancelledException`
or `DeekWebClientClosedException` failures. `sendWithOptions(request, options:
options)` throws these failures. Both send helpers throw `DeekWebHttpException`
with status/data for ordinary unsuccessful HTTP responses.

Each attempt uses a fresh `http.AbortableRequest`. Default IO/browser transports
honor abort while awaiting headers or downloading. Custom transports may ignore
abort; logical settlement remains prompt and late results/errors are consumed
without duplicate callbacks. Cancelling one request never closes a shared
transport. Synchronous parsing cannot be interrupted; cancellation/deadline is
checked again before accepting its result. Cancelling isolate parsing discards
the result without promising termination of worker execution.

## Interceptors and asynchronous parsing

The constructor snapshots its optional interceptor list. Implement
`DeekWebInterceptor.intercept(request, chain)` and call `chain.proceed(request)`
to continue. Prepared requests are immutable values with case-insensitive
headers (lowercase enumerated keys). Supplied headers and bytes are copied at
ownership boundaries. `copyWith` shares unchanged immutable storage; the public
`bodyBytes` getter returns a mutable defensive copy. Transport attempts share a
read-only byte view; custom HTTP clients that change bodies should assign a
replacement `bodyBytes` value rather than edit it in place.

Sequential `proceed` calls rerun downstream interceptors and create fresh
transport attempts. Overlapping calls on the same continuation throw
`StateError`. Only the final response is parsed, with one logical listener
lifecycle. Chain state exposes `isCancelled`, `deadline`, `remaining`,
`throwIfCancelled()` and cancellation-aware `delay()`. Synthetic responses use
`DeekWebHttpResponse(statusCode: ..., bodyBytes: ..., headers: ...)` without
requiring an HTTP package import.

The [tested auth and bounded GET retry examples](test/examples/policies.dart)
show explicit policies; none is installed automatically. Restrict credentials
to a trusted HTTPS origin, including redirects/downstream URI changes. Mutation
retries require a server idempotency contract. There is no default retry,
authentication or timeout policy.

Extend `DeekWebAsyncRequest<T>` and implement `parseResponseAsync` for async
parsing. Directly invoking its synchronous parser throws `UnsupportedError`.
`decodeJsonAsync(text)` decodes synchronously behind a Future API; selecting
`background: true` uses native `Isolate.run` through a `dart.library.io`
conditional import. Browsers use the portable decoder. Only text enters the
worker. Model construction stays with the caller; there is no payload threshold
or frame-rate promise.

## Upgrading from 1.x

Version 2.0.0 raises the minimum Dart SDK to 3.4 and routes unsuccessful HTTP
responses through the listener error callback. These changes warrant a major
release. It also adds optional execution, interceptor and asynchronous parsing APIs.
Existing request subclasses, synchronous parsers, constructor arguments, mutable
default headers, legacy execution overrides and logger implementations remain
supported.

Review the documented behavior changes: unsuccessful HTTP responses use the
listener error callback, default logs contain only safe origins, and each client
reuses its owned transport until explicitly closed. Dart 3.4 or later is required.
Close clients at their owner’s disposal and review custom logging overrides.
