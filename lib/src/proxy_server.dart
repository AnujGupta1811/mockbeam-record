import 'dart:io';

import 'request_forwarder.dart';
import 'response_capture.dart';
import 'route_store.dart';

/// Binds an [HttpServer] on [port], captures JSON responses into a
/// [RouteStore], and delegates every request to [RequestForwarder].
class ProxyServer {
  /// The base URL of the upstream API (e.g. `https://jsonplaceholder.typicode.com`).
  final Uri targetBase;

  /// Local port to listen on.
  final int port;

  /// When `true`, TLS certificate errors are ignored for HTTPS targets.
  final bool insecure;

  /// When `true`, 4xx and 5xx responses are captured in addition to 2xx.
  final bool captureErrors;

  /// Optional glob pattern; only paths that match are captured.
  ///
  /// `null` means capture all paths. Controlled by the `--filter` CLI flag.
  final String? filter;

  final _routeStore = RouteStore();

  HttpServer? _server;

  /// Creates a [ProxyServer].
  ProxyServer({
    required this.targetBase,
    required this.port,
    this.insecure = false,
    this.captureErrors = false,
    this.filter,
  });

  /// All routes captured so far (live reference — grows as requests arrive).
  RouteStore get routeStore => _routeStore;

  /// Starts the proxy server and prints the startup banner.
  ///
  /// Returns once the server is bound and listening. Use [stop] to shut down.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

    stdout.writeln('MockBeam Record v1.0.0');
    stdout.writeln('Proxying $targetBase → localhost:$port');
    stdout.writeln('');
    stdout.writeln('Waiting for requests... (Ctrl+C to stop and save)');
    stdout.writeln('');

    final capture = ResponseCapture(
      _routeStore,
      captureErrors: captureErrors,
      filter: filter,
    );
    final forwarder = RequestForwarder(
      targetBase: targetBase,
      insecure: insecure,
      capture: capture,
    );

    _server!.listen(forwarder.forward);
  }

  /// Stops the server and returns the number of routes captured.
  Future<int> stop() async {
    await _server?.close(force: true);
    return _routeStore.length;
  }
}
