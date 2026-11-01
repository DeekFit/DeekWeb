## 1.1.0

### Reliability, privacy and ownership

* Require Dart 3.4 or later and `http: ^1.6.0`.
* Reuse a lazy owned transport per client, support borrowed HTTP clients, and add
  idempotent close with synchronous settlement of active logical requests.
* Notify listeners exactly once; unsuccessful HTTP responses now use the error
  callback. Isolate observer Exceptions and preserve propagation of observer Errors.
* Default to origin-only logging with escaped fields and safe failure categories;
  omit raw exceptions, bodies and headers. Skip logging-only getters without a logger.

### APIs and reliability

* Preserve transport/parser causes, stacks, status and latency while retaining
  legacy synchronous parser exception propagation and execution overrides.
* Add execution options for whole-operation deadlines, cancellation and optional
  parser Exception capture, plus typed failures and nullable send helpers.
* Add immutable prepared requests, explicit interceptor chains and abortable
  attempts, with sequential retries supported and no automatic retry/auth policy.
* Share unchanged immutable payload storage across internal hops and header-only
  changes while preserving defensive copies at mutable ownership boundaries.
* Add asynchronous request parsers and portable JSON decoding with explicit
  native isolate selection.

## 1.0.6

* Update to new dependency versions

## 1.0.5

* Add `DeekWebLogger` to the main export

## 1.0.4

* Fix missing errors on bad connections on web

## 1.0.3

* Manually specify platforms to ensure web and UWP are detected

## 1.0.2

* Nothing important, just trying to make pub.dev happy

## 1.0.1

* Remove dependency on Flutter
* Some pubspec cleanup

## 1.0.0

### First release!
* Create custom requests by extending `deekweb_rest_request`
* Process them with `deekweb_rest_client`
