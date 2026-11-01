import 'dart:async';
import 'package:deekweb/deekweb.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Reuse DeekWeb's existing transport dependency for this repository-only test.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';

void main() {
  testWidgets('active example disposal settles callbacks without UI updates',
      (tester) async {
    final pending = Completer<http.Response>();
    final sent = Completer<void>();
    final transport = MockClient((_) {
      sent.complete();
      return pending.future;
    });
    late DeekWebClient client;
    await http.runWithClient(() async {
      await tester.pumpWidget(const ExampleApp());
      // Read the public state client through the State object used by the UI.
      final dynamic state = tester.state(find.byType(ExampleAppHomePage));
      client = state.client as DeekWebClient;
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(sent.isCompleted, true);
      await tester.pumpWidget(const SizedBox.shrink());
      final listener = state as DeekWebListener;
      listener.requestStarted(requestId: 'late', requestType: 'late');
      listener.requestCompleted(requestId: 'late', statusCode: 200);
      listener.requestCompletedWithError(requestId: 'late', error: 'late');
      pending.complete(http.Response('{}', 200));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
          () =>
              client.executeRequest(ExampleRequest(latitude: 0, longitude: 0)),
          throwsStateError);
    }, () => transport);
  });
}
