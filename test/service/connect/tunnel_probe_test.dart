import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/tunnel_probe.dart';

void main() {
  late HttpServer server;
  late List<int> ports;

  // Holds the first request back by [firstDelay] and records the client port
  // of each, so the same port means the same connection.
  Future<Uri> serve({required Duration firstDelay}) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ports = [];
    server.listen((request) async {
      ports.add(request.connectionInfo!.remotePort);
      if (ports.length == 1) await Future<void>.delayed(firstDelay);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/');
  }

  tearDown(() => server.close(force: true));

  test('times the second request on the first one\'s connection', () async {
    final url = await serve(firstDelay: const Duration(milliseconds: 300));

    final delay = await timeWarmHead(url);

    expect(delay, lessThan(300));
    expect(ports, hasLength(2));
    expect(ports.toSet(), hasLength(1));
  });

  test('gives no delay when the answers outlast the timeout', () async {
    final url = await serve(firstDelay: const Duration(seconds: 2));

    final delay = await timeWarmHead(
      url,
      timeout: const Duration(milliseconds: 500),
    );

    expect(delay, isNull);
  });
}
