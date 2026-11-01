# DeekWeb example

Run `flutter run` to explore the weather request UI. The app owns its client,
closes it during disposal while listeners remain attached, and guards UI updates
during teardown and after awaited results. Pressing Start calls an external
weather API; automated tests use a controlled local transport.

Requires Dart 3.4 or later. This example uses the library's existing relative
`path: ../` dependency. The main README contains a complete typed request/parser
quick start and the ownership, privacy and failure contracts.

Explicit auth and bounded GET retry examples live in
`../test/examples/policies.dart` and are exercised by the library tests. No policy
is automatically installed. Restrict credentials to a trusted HTTPS origin and
require server idempotency before retrying mutations. Cancellation cannot undo
server effects or terminate synchronous/isolate parsing.

Run `flutter test --no-pub` in this example to check active-request disposal.
Run the library's tests from the parent directory. For its browser abort checks,
start `dart tool/browser_fixture.dart` there in a second terminal, then run
`flutter test --no-pub --platform chrome`; the fixture binds only loopback port
18764. Stop it afterward.
