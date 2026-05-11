import 'dart:convert';

import 'route_store.dart';

/// The outcome of attempting to capture a single upstream response.
enum CaptureOutcome {
  /// JSON response, newly stored in the [RouteStore].
  captured,

  /// The same `method:path` was already captured; this response was discarded.
  duplicate,

  /// `Content-Type` is not `application/json`; body was not inspected.
  binary,

  /// Response body exceeds [ResponseCapture.maxBodyBytes]; not stored.
  tooLarge,

  /// Status code is outside 2xx and `--capture-errors` was not passed.
  non2xx,

  /// `Content-Type` claimed JSON but the body could not be decoded.
  invalidJson,

  /// Path did not match the `--filter` glob pattern; not stored.
  filtered,
}

/// Inspects upstream responses, parses JSON bodies, and records them in a
/// [RouteStore].
///
/// Non-JSON bodies, oversized bodies, filtered paths, and (by default)
/// non-2xx responses are skipped; the caller receives a [CaptureOutcome] to
/// log appropriately.
class ResponseCapture {
  /// Maximum response body that will be captured (10 MB).
  static const maxBodyBytes = 10 * 1024 * 1024;

  final RouteStore _store;

  /// When `true`, 4xx and 5xx responses are stored in addition to 2xx.
  ///
  /// Controlled by the `--capture-errors` CLI flag.
  final bool captureErrors;

  /// Optional glob pattern; only paths that match are captured.
  ///
  /// `*` matches any characters except `/`. `**` matches across `/`.
  /// `null` means capture all paths.
  ///
  /// Controlled by the `--filter` CLI flag.
  final String? filter;

  /// Creates a [ResponseCapture] backed by [store].
  ResponseCapture(this._store, {this.captureErrors = false, this.filter});

  /// Inspects [bodyBytes] and conditionally adds a route to the store.
  ///
  /// [contentType] should be the MIME type only (e.g. `application/json`),
  /// not the full `Content-Type` header value. Pass `null` if the header was
  /// absent.
  ///
  /// Returns the [CaptureOutcome] so the caller can update its log line.
  CaptureOutcome process({
    required String method,
    required String path,
    required int statusCode,
    required String? contentType,
    required List<int> bodyBytes,
  }) {
    if (filter != null && !_globMatches(path, filter!)) {
      return CaptureOutcome.filtered;
    }

    if (!captureErrors && (statusCode < 200 || statusCode >= 300)) {
      return CaptureOutcome.non2xx;
    }

    if (contentType == null || !contentType.contains('application/json')) {
      return CaptureOutcome.binary;
    }

    if (bodyBytes.length > maxBodyBytes) {
      return CaptureOutcome.tooLarge;
    }

    Object? data;
    try {
      data = jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      return CaptureOutcome.invalidJson;
    }

    final route = CapturedRoute(
      method: method.toUpperCase(),
      path: path,
      statusCode: statusCode,
      data: data,
    );
    return _store.tryAdd(route) ? CaptureOutcome.captured : CaptureOutcome.duplicate;
  }
}

/// Returns `true` if [path] matches the glob [pattern].
///
/// `*`  matches any characters except `/` (single path segment wildcard).
/// `**` matches any characters including `/` (multi-segment wildcard).
bool _globMatches(String path, String pattern) {
  // Escape all regex special characters in the pattern first, then restore
  // glob wildcards as their regex equivalents.
  final escaped = pattern.replaceAllMapped(
    RegExp(r'[.+^${}()|[\]\\]'),
    (m) => '\\${m[0]}',
  );
  final regexStr = escaped
      .replaceAll('**', '\x00') // placeholder — must precede single-* replace
      .replaceAll('*', '[^/]*')
      .replaceAll('\x00', '.*');
  return RegExp('^$regexStr\$').hasMatch(path);
}
