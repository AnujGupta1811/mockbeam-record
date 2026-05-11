import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:mockbeam_record/src/response_capture.dart';
import 'package:mockbeam_record/src/route_store.dart';

/// Encodes [json] string to UTF-8 bytes as a [Uint8List].
Uint8List _bytes(String json) => Uint8List.fromList(utf8.encode(json));

void main() {
  group('ResponseCapture.process', () {
    late RouteStore store;
    late ResponseCapture capture;

    setUp(() {
      store = RouteStore();
      capture = ResponseCapture(store);
    });

    // --- Happy path -----------------------------------------------------------

    test('captures a valid JSON 2xx response', () {
      final outcome = capture.process(
        method: 'GET',
        path: '/users/1',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: _bytes('{"id":1}'),
      );
      expect(outcome, CaptureOutcome.captured);
      expect(store.length, 1);
    });

    test('parses nested JSON into the stored route', () {
      capture.process(
        method: 'GET',
        path: '/users/1',
        statusCode: 200,
        contentType: 'application/json; charset=utf-8',
        bodyBytes: _bytes('{"id":1,"address":{"city":"NYC"}}'),
      );
      final data = store.routes.first.data as Map;
      expect((data['address'] as Map)['city'], 'NYC');
    });

    // --- Binary skip ----------------------------------------------------------

    test('skips a response with non-JSON Content-Type', () {
      final outcome = capture.process(
        method: 'GET',
        path: '/avatar.png',
        statusCode: 200,
        contentType: 'image/png',
        bodyBytes: [0x89, 0x50, 0x4E, 0x47],
      );
      expect(outcome, CaptureOutcome.binary);
      expect(store.length, 0);
    });

    test('skips a response with null Content-Type', () {
      final outcome = capture.process(
        method: 'GET',
        path: '/unknown',
        statusCode: 200,
        contentType: null,
        bodyBytes: _bytes('{}'),
      );
      expect(outcome, CaptureOutcome.binary);
    });

    // --- Non-2xx handling -----------------------------------------------------

    test('skips non-2xx by default', () {
      final outcome = capture.process(
        method: 'GET',
        path: '/not-found',
        statusCode: 404,
        contentType: 'application/json',
        bodyBytes: _bytes('{"error":"not found"}'),
      );
      expect(outcome, CaptureOutcome.non2xx);
      expect(store.length, 0);
    });

    test('captures non-2xx when captureErrors is true', () {
      final cap = ResponseCapture(store, captureErrors: true);
      final outcome = cap.process(
        method: 'GET',
        path: '/not-found',
        statusCode: 404,
        contentType: 'application/json',
        bodyBytes: _bytes('{"error":"not found"}'),
      );
      expect(outcome, CaptureOutcome.captured);
      expect(store.length, 1);
    });

    // --- Deduplication --------------------------------------------------------

    test('returns duplicate for a repeated method+path', () {
      final args = (
        method: 'GET',
        path: '/posts',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: _bytes('[]'),
      );
      capture.process(
        method: args.method,
        path: args.path,
        statusCode: args.statusCode,
        contentType: args.contentType,
        bodyBytes: args.bodyBytes,
      );
      final outcome = capture.process(
        method: args.method,
        path: args.path,
        statusCode: args.statusCode,
        contentType: args.contentType,
        bodyBytes: args.bodyBytes,
      );
      expect(outcome, CaptureOutcome.duplicate);
      expect(store.length, 1);
    });

    // --- Oversized body -------------------------------------------------------

    test('skips body larger than maxBodyBytes', () {
      final big = Uint8List(ResponseCapture.maxBodyBytes + 1);
      final outcome = capture.process(
        method: 'GET',
        path: '/big',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: big,
      );
      expect(outcome, CaptureOutcome.tooLarge);
    });

    // --- Invalid JSON ---------------------------------------------------------

    test('skips a body that cannot be decoded as JSON', () {
      final outcome = capture.process(
        method: 'GET',
        path: '/broken',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: _bytes('not valid json {{{'),
      );
      expect(outcome, CaptureOutcome.invalidJson);
    });

    // --- Filter / glob --------------------------------------------------------

    test('returns filtered when path does not match the glob', () {
      final cap = ResponseCapture(store, filter: '/api/*');
      final outcome = cap.process(
        method: 'GET',
        path: '/other/resource',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: _bytes('{}'),
      );
      expect(outcome, CaptureOutcome.filtered);
      expect(store.length, 0);
    });

    test('captures when path matches the glob', () {
      final cap = ResponseCapture(store, filter: '/api/*');
      final outcome = cap.process(
        method: 'GET',
        path: '/api/users',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: _bytes('[]'),
      );
      expect(outcome, CaptureOutcome.captured);
    });

    test('** glob matches across path segments', () {
      final cap = ResponseCapture(store, filter: '/api/**');
      final outcome = cap.process(
        method: 'GET',
        path: '/api/v1/users/42',
        statusCode: 200,
        contentType: 'application/json',
        bodyBytes: _bytes('{}'),
      );
      expect(outcome, CaptureOutcome.captured);
    });
  });
}
