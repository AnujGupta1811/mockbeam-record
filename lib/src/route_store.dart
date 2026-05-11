/// A single captured API route ready for YAML serialization.
class CapturedRoute {
  /// HTTP method, normalised to upper-case (e.g. `GET`, `POST`).
  final String method;

  /// URL path without query string (e.g. `/users/1`).
  final String path;

  /// HTTP status code from the upstream response.
  final int statusCode;

  /// Parsed JSON response body — a [Map], [List], [String], [num], [bool],
  /// or `null`, exactly as returned by `dart:convert`'s `jsonDecode`.
  final Object? data;

  /// Creates a [CapturedRoute] with the given fields.
  const CapturedRoute({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.data,
  });
}

/// In-memory table of captured routes, keyed by `METHOD:path`.
///
/// Deduplication rule: a second call to [tryAdd] for the same method+path
/// combination is silently discarded — the first capture wins.
/// Query strings are intentionally excluded from the key so that paginated
/// endpoints like `/posts?page=1` and `/posts?page=2` resolve to the same
/// mock entry.
class RouteStore {
  final _routes = <String, CapturedRoute>{};

  /// Adds [route] if no entry for its `method:path` key exists yet.
  ///
  /// Returns `true` when the route is stored, `false` when it is a duplicate.
  bool tryAdd(CapturedRoute route) {
    final key = '${route.method.toUpperCase()}:${route.path}';
    if (_routes.containsKey(key)) return false;
    _routes[key] = route;
    return true;
  }

  /// All captured routes in insertion order (immutable snapshot).
  List<CapturedRoute> get routes => List.unmodifiable(_routes.values);

  /// Number of routes stored so far.
  int get length => _routes.length;
}
