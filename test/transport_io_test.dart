@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'package:deekweb/deekweb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'core_test.dart' show Request;
import 'support/probe.dart';

void main() {
  test('default IO transport posts immutable prepared bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.binary;
      await request.response.addStream(request);
      await request.response.close();
    });
    final client = DeekWebClient();
    try {
      expect(
          await client.send(Request(
              url: 'http://127.0.0.1:${server.port}',
              verb: Method.post,
              payload: <int>[0, 128, 255],
              parse: (response) => response.bodyBytes.join(','))),
          '0,128,255');
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('owned IO client reuses a loopback connection within one wrapper',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ports = <int>[];
    server.listen((request) async {
      ports.add(request.connectionInfo!.remotePort);
      await request.drain<void>();
      request.response.write('ok');
      await request.response.close();
    });
    final client = DeekWebClient();
    try {
      final request = Request(url: 'http://127.0.0.1:${server.port}');
      expect(await client.send(request), 'ok');
      expect(await client.send(request), 'ok');
      expect(ports.length, 2);
      expect(ports.toSet().length, 1);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  for (final download in [false, true]) {
    test(
        'owned IO aborts ${download ? 'download' : 'before headers'} without closing sibling request',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final arrived = Completer<void>();

      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/ok') {
          request.response.write('ok');
          await request.response.close();
          return;
        }
        final response = request.response;
        if (download) {
          response.write('partial');
          await response.flush();
        }
        arrived.complete();
      });
      final probe = Probe();
      final client = DeekWebClient(client: probe);
      final token = DeekWebCancellationToken();
      try {
        final result = client.executeRequestWithOptions(
            Request(url: 'http://127.0.0.1:${server.port}/stall'),
            options: DeekWebExecutionOptions(cancellationToken: token));
        await arrived.future;
        if (download) {
          await probe.headers.future;
          await Future<void>.delayed(Duration.zero);
        }
        token.cancel();
        expect((await result).exception, isA<DeekWebCancelledException>());
        expect(await probe.aborted.future.timeout(const Duration(seconds: 3)),
            isA<http.RequestAbortedException>());
        expect(
            await client
                .send(Request(url: 'http://127.0.0.1:${server.port}/ok')),
            'ok');
      } finally {
        client.close();
        probe.close();
        await server.close(force: true);
      }
    });
  }
}
