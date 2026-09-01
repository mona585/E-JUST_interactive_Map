import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anyplace_campusfind/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';

// ---------------------------------------------------------------------------
// Regression tests for the floorplan download failure mode:
// LOADING -> LOADING -> FAILURE on slow links.
//
// Root cause: a fixed total-time timeout cannot distinguish a slow-but-alive
// trickle (the backend streams ~10 MB of Base64 at ~70-105 KB/s wired, and
// mobile links measured ~24 KB/s) from a dead connection. The client now
// streams the response with a STALL watchdog (inter-chunk silence) plus a
// generous overall budget. These tests pin both behaviors.
// ---------------------------------------------------------------------------

const _base = 'https://floorplan-backend.test';

class _ScriptedClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request) handler;
  int calls = 0;
  List<int>? lastRequestBody;
  Uri? lastRequestUrl;

  _ScriptedClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    lastRequestUrl = request.url;
    if (request is http.Request) lastRequestBody = request.bodyBytes;
    return handler(request);
  }
}

Stream<List<int>> _trickle(List<List<int>> chunks, Duration gap) async* {
  for (final chunk in chunks) {
    await Future<void>.delayed(gap);
    yield chunk;
  }
}

http.StreamedResponse _response(
  Stream<List<int>> body,
  int statusCode, {
  Map<String, String> headers = const {},
}) =>
    http.StreamedResponse(body, statusCode, headers: headers);

void main() {
  group('fetchFloorplanImage stall-watchdog download', () {
    test('A. slow-but-alive trickle completes intact (never trips the '
        'stall watchdog)', () async {
      final payload = List.generate(5, (i) => List<int>.filled(16, i + 1));
      final client = _ScriptedClient((request) async => _response(
            _trickle(payload, const Duration(milliseconds: 30)),
            200,
          ));
      final api = AnyplaceApiClient(client: client, baseUrl: _base);

      final bytes = await api.fetchFloorplanImage(
        'b1',
        '0',
        stallTimeout: const Duration(milliseconds: 200),
      );

      // Whole body received in order despite inter-chunk gaps.
      final expected = <int>[for (final c in payload) ...c];
      expect(bytes, expected);
      expect(client.calls, 1, reason: 'a healthy trickle is not retried');
      expect(client.lastRequestUrl!.path,
          '/api/floorplans64/b1/0');
      expect(utf8.decode(client.lastRequestBody!), '{}');
    });

    test('B. a stalled connection fails fast and is mapped to an explicit '
        'timeout error after the single retry (no endless loading)', () async {
      Future<http.StreamedResponse> stalledHandler(http.BaseRequest _) async {
        return _response(
          () async* {
            yield [1, 2, 3];
            // Dead silence far beyond the stall watchdog limit.
            await Future<void>.delayed(const Duration(seconds: 5));
            yield [4];
          }(),
          200,
        );
      }

      final stalled = _ScriptedClient(stalledHandler);
      final api = AnyplaceApiClient(client: stalled, baseUrl: _base);

      await expectLater(
        api.fetchFloorplanImage(
          'b1',
          '0',
          stallTimeout: const Duration(milliseconds: 150),
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Connection to Anyplace backend timed out.',
        )),
      );
      expect(stalled.calls, 2,
          reason: 'the existing single-retry policy is preserved');
    });

    test('C. non-200 response raises an explicit ApiException with the '
        'status code', () async {
      final client = _ScriptedClient(
          (request) async => _response(
                _trickle([
                  utf8.encode('{"status":"error","message":"not found"}')
                ], Duration.zero),
                404,
              ));
      final api = AnyplaceApiClient(client: client, baseUrl: _base);

      await expectLater(
        api.fetchFloorplanImage(
          'b1',
          '9',
          stallTimeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', contains('HTTP 404'))),
      );
    });

    test('D. an empty 200 payload raises an explicit error (never a silent '
        'success)', () async {
      final client = _ScriptedClient((request) async => _response(
            _trickle([
              utf8.encode('   ')
            ], Duration.zero),
            200,
          ));
      final api = AnyplaceApiClient(client: client, baseUrl: _base);

      await expectLater(
        api.fetchFloorplanImage(
          'b1',
          '0',
          stallTimeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Floorplan image data is empty.',
        )),
      );
    });

    test('overall budget constant covers the measured slow-link case '
        '(10.5 MB at ~24 KB/s needs ~7.5 min)', () {
      expect(ApiConfig.floorplanImageTimeout, greaterThan(const Duration(minutes: 8)));
      expect(ApiConfig.floorplanStallTimeout,
          lessThan(const Duration(minutes: 2)),
          reason: 'a dead connection must fail fast relative to the budget');
    });
  });
}
