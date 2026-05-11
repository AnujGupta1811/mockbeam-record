// Programmatic usage of MockBeam Record.
//
// For the typical use case the CLI is simpler:
//   mockbeam_record record --target https://api.example.com
//
// Use the library API when you need to embed the proxy in a test harness,
// a custom tool, or a CI script that records and saves in one step.

import 'dart:io';

import 'package:mockbeam_record/mockbeam_record.dart';

Future<void> main() async {
  final target = Uri.parse('https://jsonplaceholder.typicode.com');

  final server = ProxyServer(
    targetBase: target,
    port: 8080,
  );

  await server.start();
  print('Proxy running on http://localhost:8080');
  print('Press Ctrl+C to stop and save.');

  // Keep running until Ctrl+C.
  await ProcessSignal.sigint.watch().first;

  final count = await server.stop();
  print('\nStopping... $count route(s) captured.');

  final serializer = RouteSerializer();
  final yaml = serializer.toYaml(
    server.routeStore.routes,
    target: target,
  );
  await serializer.writeTo('mocks/recorded.yaml', yaml);
  print('Wrote mocks/recorded.yaml');
}
