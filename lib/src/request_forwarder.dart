import 'dart:io';
import 'dart:typed_data';

import 'response_capture.dart';

/// Headers stripped when forwarding the client request upstream.
///
/// `host` — dart:io sets this automatically from the target URI.
/// `content-length` — set explicitly from the collected body length.
/// `expect` — absorbed at the proxy boundary; upstream gets body directly.
/// The rest are hop-by-hop headers that must not cross a proxy boundary.
const _skipOnRequest = {
  'host',
  'content-length',
  'expect',
  'connection',
  'keep-alive',
  'transfer-encoding',
  'te',
  'trailer',
  'upgrade',
  'proxy-authorization',
  'proxy-authenticate',
};

/// Headers stripped when forwarding the upstream response back to the client.
///
/// `content-length` — set from the actual body byte count after collection.
/// `content-encoding` — dart:io decompresses when `autoUncompress = true`;
///   forwarding the original `gzip` label would cause double-decompression.
/// `transfer-encoding` — dart:io manages framing automatically.
const _skipOnResponse = {
  'content-length',
  'content-encoding',
  'transfer-encoding',
  'connection',
  'keep-alive',
  'te',
  'trailer',
  'upgrade',
  'proxy-authorization',
  'proxy-authenticate',
};

/// Forwards incoming [HttpRequest]s to an upstream [targetBase], relays the
/// response to the client, and optionally captures JSON responses.
///
/// Logs one line per request to stdout showing method, path, status, and
/// capture outcome.
class RequestForwarder {
  /// The base URL of the upstream API.
  final Uri targetBase;

  /// When `true`, TLS certificate errors are ignored for HTTPS targets.
  final bool insecure;

  /// Optional capture pipeline. When non-null every response is inspected and
  /// JSON bodies are stored in the backing [RouteStore].
  final ResponseCapture? capture;

  /// Creates a [RequestForwarder].
  RequestForwarder({
    required this.targetBase,
    this.insecure = false,
    this.capture,
  });

  /// Creates a fresh [HttpClient] for each request.
  ///
  /// A shared client pools connections. When the upstream closes a keep-alive
  /// connection on its end the pooled socket is stale — the next request
  /// reuses it and receives "Connection reset by peer" (errno 54/104). A
  /// per-request client has no pool, so every connection is always fresh.
  ///
  /// `autoUncompress = true` lets dart:io decompress gzip/deflate responses.
  /// We strip `content-encoding` from the response headers so the client does
  /// not try to decompress an already-plain body.
  HttpClient _newClient() => HttpClient()
    ..autoUncompress = true
    ..badCertificateCallback = (_, __, ___) => insecure;

  /// Forwards [incoming] to the upstream target and relays the response.
  ///
  /// Retries once on a transient [SocketException] (e.g. a cold-start
  /// connection reset from a CDN upstream) before returning a 502.
  Future<void> forward(HttpRequest incoming) async {
    final stopwatch = Stopwatch()..start();

    final targetUri = targetBase.replace(
      path: incoming.uri.path,
      query: incoming.uri.hasQuery ? incoming.uri.query : null,
    );

    // Collect body before the retry loop — we need the bytes in memory to
    // resend them on a second attempt without re-reading the stream.
    final reqBody = await _readRequestBody(incoming);

    for (var attempt = 0; attempt < 2; attempt++) {
      final client = _newClient();
      try {
        final retry = await _attempt(
          incoming,
          reqBody,
          targetUri,
          client,
          stopwatch,
          isLastAttempt: attempt == 1,
        );
        if (!retry) return;
        // retry == true: transient SocketException on first attempt; loop.
      } finally {
        client.close(force: true);
      }
    }
  }

  /// Attempts one full request/response cycle.
  ///
  /// Returns `true` when the caller should retry (transient [SocketException]
  /// and this was not the last attempt). Returns `false` when done — either
  /// the response was delivered or a permanent error was sent as a 502.
  Future<bool> _attempt(
    HttpRequest incoming,
    Uint8List reqBody,
    Uri targetUri,
    HttpClient client,
    Stopwatch stopwatch, {
    required bool isLastAttempt,
  }) async {
    HttpClientRequest outgoing;
    try {
      outgoing = await client.openUrl(incoming.method, targetUri);
    } on SocketException catch (e) {
      if (!isLastAttempt) return true;
      await _send502(incoming, 'cannot reach target: $e');
      _logError(incoming, 502, stopwatch);
      return false;
    } catch (e) {
      await _send502(incoming, 'cannot reach target: $e');
      _logError(incoming, 502, stopwatch);
      return false;
    }

    outgoing.contentLength = reqBody.length;

    incoming.headers.forEach((name, values) {
      if (!_skipOnRequest.contains(name.toLowerCase())) {
        for (final v in values) {
          outgoing.headers.add(name, v);
        }
      }
    });

    if (reqBody.isNotEmpty) outgoing.add(reqBody);

    HttpClientResponse response;
    try {
      response = await outgoing.close();
    } on SocketException catch (e) {
      if (!isLastAttempt) return true;
      await _send502(incoming, 'upstream error: $e');
      _logError(incoming, 502, stopwatch);
      return false;
    } catch (e) {
      await _send502(incoming, 'upstream error: $e');
      _logError(incoming, 502, stopwatch);
      return false;
    }

    incoming.response.statusCode = response.statusCode;

    response.headers.forEach((name, values) {
      if (!_skipOnResponse.contains(name.toLowerCase())) {
        for (final v in values) {
          try {
            incoming.response.headers.add(name, v);
          } catch (_) {
            // dart:io manages a few headers internally; skip conflicts.
          }
        }
      }
    });

    final respBody = await _collectResponseBody(response);
    incoming.response.contentLength = respBody.length;
    if (respBody.isNotEmpty) incoming.response.add(respBody);
    await incoming.response.close();

    stopwatch.stop();

    if (capture != null) {
      final outcome = capture!.process(
        method: incoming.method,
        path: incoming.uri.path,
        statusCode: response.statusCode,
        contentType: response.headers.contentType?.mimeType,
        bodyBytes: respBody,
      );
      _logOutcome(incoming, response.statusCode, outcome, respBody.length, stopwatch);
    } else {
      _log(
        '  ✓  ${incoming.method.padRight(6)} ${incoming.uri.path.padRight(30)} '
        '${response.statusCode}  ${stopwatch.elapsedMilliseconds}ms',
      );
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _send502(HttpRequest req, String reason) async {
    try {
      req.response.statusCode = HttpStatus.badGateway;
      req.response.write('[MockBeam] $reason');
      await req.response.close();
    } catch (_) {}
  }

  void _logError(HttpRequest req, int status, Stopwatch sw) {
    sw.stop();
    _log(
      '  ✗  ${req.method.padRight(6)} ${req.uri.path.padRight(30)} '
      '$status  ${sw.elapsedMilliseconds}ms',
    );
  }

  void _logOutcome(
    HttpRequest req,
    int statusCode,
    CaptureOutcome outcome,
    int bodyLength,
    Stopwatch sw,
  ) {
    final String icon;
    final String tail;

    switch (outcome) {
      case CaptureOutcome.captured:
      case CaptureOutcome.non2xx:
      case CaptureOutcome.filtered:
        icon = '  ✓';
        tail = '${sw.elapsedMilliseconds}ms';
      case CaptureOutcome.duplicate:
        icon = '  ✓';
        tail = '[duplicate — skipped]';
      case CaptureOutcome.binary:
        icon = '  ⚠';
        tail = '[binary — skipped]';
      case CaptureOutcome.tooLarge:
        final mb = (bodyLength / (1024 * 1024)).toStringAsFixed(1);
        icon = '  ⚠';
        tail = '[body too large ($mb MB) — skipped]';
      case CaptureOutcome.invalidJson:
        icon = '  ⚠';
        tail = '[invalid JSON — skipped]';
    }

    _log(
      '$icon  ${req.method.padRight(6)} ${req.uri.path.padRight(30)} '
      '$statusCode  $tail',
    );
  }

  /// Returns body bytes for methods that carry a body (POST, PUT, PATCH …).
  ///
  /// Returns an empty [Uint8List] for GET, HEAD, DELETE, OPTIONS, and TRACE.
  /// On a keep-alive connection dart:io does not close the request body stream
  /// for body-less methods — awaiting it would hang indefinitely.
  Future<Uint8List> _readRequestBody(HttpRequest req) async {
    const noBodyMethods = {'GET', 'HEAD', 'DELETE', 'OPTIONS', 'TRACE'};
    if (noBodyMethods.contains(req.method.toUpperCase())) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  /// Collects the full response body.
  ///
  /// Because `autoUncompress = true`, dart:io has already decompressed the
  /// bytes. The collected length is used for the outgoing `content-length`.
  Future<Uint8List> _collectResponseBody(HttpClientResponse res) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  void _log(String message) => stdout.writeln(message);
}
