import 'dart:io';

import 'package:args/args.dart';

import 'proxy_server.dart';
import 'route_serializer.dart';

const _version = '1.0.0';

/// Parses command-line arguments and starts a [ProxyServer] recording session.
Future<void> runCli(List<String> args) async {
  final recordParser = ArgParser()
    ..addOption(
      'target',
      abbr: 't',
      mandatory: true,
      help: 'Upstream base URL to proxy (e.g. https://api.example.com)',
    )
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Local proxy port')
    ..addOption(
      'out',
      abbr: 'o',
      defaultsTo: 'mocks/recorded.yaml',
      help: 'Output file path',
    )
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ['yaml', 'json'],
      defaultsTo: 'yaml',
      help: 'Output format',
      allowedHelp: {'yaml': 'YAML (default)', 'json': 'JSON'},
    )
    ..addOption(
      'filter',
      help: 'Only capture paths matching this glob (e.g. /api/*)',
    )
    ..addFlag(
      'insecure',
      abbr: 'k',
      negatable: false,
      help: 'Skip TLS certificate verification for HTTPS targets',
    )
    ..addFlag(
      'capture-errors',
      negatable: false,
      help: 'Capture 4xx and 5xx responses in addition to 2xx',
    )
    ..addFlag(
      'append',
      abbr: 'a',
      negatable: false,
      help: 'Merge new routes into the existing output file instead of overwriting',
    );

  final parser = ArgParser()
    ..addCommand('record', recordParser)
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Print version and exit')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage and exit');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(_usage(parser));
    exit(1);
  }

  if (results['version'] as bool) {
    stdout.writeln('MockBeam Record v$_version');
    exit(0);
  }

  if (results['help'] as bool || results.command == null) {
    stdout.writeln(_usage(parser));
    exit(0);
  }

  final command = results.command!;
  if (command.name != 'record') {
    stderr.writeln(_usage(parser));
    exit(1);
  }

  final targetRaw = command['target'] as String;
  final port = int.tryParse(command['port'] as String) ?? 8080;
  final outPath = command['out'] as String;
  final format = command['format'] as String;
  final filter = command['filter'] as String?;
  final insecure = command['insecure'] as bool;
  final captureErrors = command['capture-errors'] as bool;
  final append = command['append'] as bool;

  final targetBase = Uri.tryParse(targetRaw);
  if (targetBase == null || !targetBase.hasScheme) {
    stderr.writeln('Error: --target must be a valid URL (e.g. https://api.example.com)');
    exit(1);
  }

  final server = ProxyServer(
    targetBase: targetBase,
    port: port,
    insecure: insecure,
    captureErrors: captureErrors,
    filter: filter,
  );

  try {
    await server.start();
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 48 || e.osError?.errorCode == 98) {
      stderr.writeln('Error: Port $port is already in use. Try --port ${port + 1}');
    } else {
      stderr.writeln('Error starting server: $e');
    }
    exit(1);
  }

  // Keep running until SIGINT (Ctrl+C).
  await ProcessSignal.sigint.watch().first;
  stdout.writeln('');
  stdout.writeln('Stopping...');
  final count = await server.stop();
  stdout.writeln('$count route${count == 1 ? '' : 's'} captured.');

  final serializer = RouteSerializer();
  var routes = server.routeStore.routes;

  if (append) {
    final existing = await serializer.loadExisting(outPath);
    routes = serializer.merge(routes, existing);
  }

  final content = format == 'json'
      ? serializer.toJson(routes)
      : serializer.toYaml(routes, target: targetBase);

  try {
    await serializer.writeTo(outPath, content);
    stdout.writeln('Wrote $outPath');
  } catch (e) {
    stderr.writeln('Error writing $outPath: $e');
    exit(1);
  }
}

String _usage(ArgParser parser) => '''
MockBeam Record v$_version — capture real API responses as mock YAML.

Usage:
  mockbeam_record record --target <url> [options]
  mockbeam_record --version
  mockbeam_record --help

${parser.commands['record']!.usage}''';
