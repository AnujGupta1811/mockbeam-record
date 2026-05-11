import 'package:test/test.dart';

import 'package:mockbeam_record/src/route_store.dart';

void main() {
  group('RouteStore', () {
    late RouteStore store;

    setUp(() => store = RouteStore());

    test('tryAdd returns true for a new route', () {
      final r = CapturedRoute(method: 'GET', path: '/users', statusCode: 200, data: null);
      expect(store.tryAdd(r), isTrue);
      expect(store.length, 1);
    });

    test('tryAdd returns false for a duplicate method+path', () {
      final r1 = CapturedRoute(method: 'GET', path: '/users', statusCode: 200, data: {'v': 1});
      final r2 = CapturedRoute(method: 'GET', path: '/users', statusCode: 200, data: {'v': 2});
      store.tryAdd(r1);
      expect(store.tryAdd(r2), isFalse);
      expect(store.length, 1);
    });

    test('first capture wins — later duplicate does not overwrite data', () {
      store.tryAdd(CapturedRoute(method: 'GET', path: '/a', statusCode: 200, data: 'first'));
      store.tryAdd(CapturedRoute(method: 'GET', path: '/a', statusCode: 200, data: 'second'));
      expect(store.routes.first.data, 'first');
    });

    test('same path with different methods are stored as separate routes', () {
      store.tryAdd(CapturedRoute(method: 'GET', path: '/posts', statusCode: 200, data: null));
      store.tryAdd(CapturedRoute(method: 'POST', path: '/posts', statusCode: 201, data: null));
      expect(store.length, 2);
    });

    test('method comparison is case-insensitive', () {
      store.tryAdd(CapturedRoute(method: 'GET', path: '/a', statusCode: 200, data: null));
      expect(
        store.tryAdd(CapturedRoute(method: 'get', path: '/a', statusCode: 200, data: null)),
        isFalse,
      );
    });

    test('routes preserves insertion order', () {
      for (final p in ['/a', '/b', '/c']) {
        store.tryAdd(CapturedRoute(method: 'GET', path: p, statusCode: 200, data: null));
      }
      expect(store.routes.map((r) => r.path).toList(), ['/a', '/b', '/c']);
    });

    test('routes getter returns an unmodifiable list', () {
      store.tryAdd(CapturedRoute(method: 'GET', path: '/a', statusCode: 200, data: null));
      final extra = CapturedRoute(method: 'GET', path: '/z', statusCode: 200, data: null);
      expect(
        // ignore: avoid_dynamic_calls
        () => (store.routes as dynamic).add(extra),
        throwsUnsupportedError,
      );
    });

    test('length reflects the number of unique routes', () {
      store.tryAdd(CapturedRoute(method: 'GET', path: '/a', statusCode: 200, data: null));
      store.tryAdd(CapturedRoute(method: 'GET', path: '/a', statusCode: 200, data: null)); // dup
      store.tryAdd(CapturedRoute(method: 'POST', path: '/a', statusCode: 201, data: null));
      expect(store.length, 2);
    });
  });
}
