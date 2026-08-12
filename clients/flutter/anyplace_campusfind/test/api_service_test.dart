// Phase 7.5 — ApiService endpoint calls, JSON parsing and error mapping.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/services/api_service.dart';

void main() {
  group('ApiService', () {
    late Dio dio;
    late ApiService api;

    setUp(() {
      dio = Dio();
      api = ApiService(dio: dio);
    });

    void stubPost(String url, Object? response,
        {int status = 200, Object? error}) {
      dio.httpClientAdapter = FakeAdapter(
        onPost: (requestUrl, body, headers) => (requestUrl, status, response, error),
      );
    }

    void stubBadResponse(String url, int status, String body) {
      dio.httpClientAdapter = FakeAdapter(
        onPost: (requestUrl, body, headers) => (requestUrl, status, body, null),
      );
    }

    void stubNetworkError(String url) {
      dio.httpClientAdapter = FakeAdapter(
        onPost: (requestUrl, body, headers) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: requestUrl),
          reason: 'Connection refused',
        ),
      );
    }

    test('fetchPublicSpaces parses the spaces list', () async {
      stubPost(
        '/api/mapping/space/public',
        {
          'spaces': [
            {
              'buid': 'b1',
              'name': 'Main Building',
              'coordinates_lat': 30.85,
              'coordinates_lon': 29.59,
              'type': 'building',
            },
          ],
        },
      );

      final spaces = await api.fetchPublicSpaces();
      expect(spaces, hasLength(1));
      expect(spaces.single.buid, 'b1');
      expect(spaces.single.name, 'Main Building');
    });

    test('fetchPublicSpaces tolerates a missing spaces key', () async {
      stubPost('/api/mapping/space/public', <String, dynamic>{});
      expect(await api.fetchPublicSpaces(), isEmpty);
    });

    test('fetchFloors parses floors', () async {
      stubPost('/api/mapping/floor/all', {
        'floors': [
          {'buid': 'b1', 'floor_number': '1'},
        ],
      });
      final floors = await api.fetchFloors('b1');
      expect(floors.single.fuid, 'b1_1');
    });

    test('fetchCampus sets cuid from the request', () async {
      stubPost('/api/mapping/campus/get', {'name': 'E-JUST'});
      final campus = await api.fetchCampus('c1');
      expect(campus.cuid, 'c1');
    });

    test('estimatePosition sends APs as a JSON string', () async {
      Object? sentBody;
      dio.httpClientAdapter = FakeAdapter(
        onPost: (requestUrl, body, headers) {
          sentBody = body;
          return (requestUrl, 200, {'lat': '30.8', 'long': '29.5'}, null);
        },
      );

      final estimate = await api.estimatePosition(
        buid: 'b1',
        floor: '1',
        accessPoints: [
          {'bssid': 'aa:bb', 'rss': -60},
        ],
      );

      expect(sentBody, isA<String>());
      final decoded = jsonDecode(sentBody! as String) as Map<String, dynamic>;
      expect(decoded['APs'], contains('aa:bb'));
      expect(estimate.lat, 30.8);
      expect(estimate.long, 29.5);
      expect(estimate.hasFix, isTrue);
    });

    test('fetchFloorTilesZip returns raw bytes', () async {
      dio.httpClientAdapter = FakeAdapter(
        onPost: (requestUrl, body, headers) =>
            (requestUrl, 200, Uint8List.fromList([1, 2, 3]), null),
      );
      final bytes = await api.fetchFloorTilesZip('b1', '2');
      expect(bytes, [1, 2, 3]);
    });

    test('maps non-2xx status to ApiException with statusCode', () async {
      stubBadResponse('/api/mapping/space/public', 500, 'boom');
      await expectLater(
        api.fetchPublicSpaces(),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('maps connection errors to ApiException', () async {
      stubNetworkError('/api/mapping/space/public');
      await expectLater(
        api.fetchPublicSpaces(),
        throwsA(isA<ApiException>().having(
            (e) => e.statusCode, 'statusCode', isNull)),
      );
    });
  });
}

/// Minimal Dio adapter that lets tests control the response per-request.
typedef FakeResponse = (String, int, Object?, Object?);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({required this.onPost});

  final FutureOr<FakeResponse> Function(
      String url, Object? body, Map<String, dynamic> headers) onPost;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (url, status, data, error) = await onPost(
      options.path,
      options.data,
      options.headers,
    );
    if (error != null) throw error;
    final bytes = _encode(data);
    return ResponseBody.fromBytes(bytes, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  Uint8List _encode(Object? data) {
    if (data is Uint8List) return data;
    if (data == null) return Uint8List(0);
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }

  @override
  void close({bool force = false}) {}
}
