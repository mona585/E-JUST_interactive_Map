// CampusLoader auto-discovery: when no CAMPUS_IDS are configured, a single
// default campus is derived from space/public so a zero-config build shows the
// E-JUST campus on first launch instead of dead-ending.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/config/constants.dart';
import 'package:anyplace_campusfind/providers/campus_provider.dart';
import 'package:anyplace_campusfind/services/api_service.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';

void main() {
  group('CampusLoader.loadConfigured', () {
    late Dio dio;
    late ApiService api;
    late CacheService cache;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dio = Dio();
      api = ApiService(dio: dio);
      cache = CacheService();
    });

    void stub(FutureOr<FakeResponse> Function(
        String url, Object? body, Map<String, dynamic> headers) onPost) {
      dio.httpClientAdapter = FakeAdapter(onPost: onPost);
    }

    test('derives the default campus from space/public when no cuids given',
        () async {
      stub((url, body, headers) => (
            url,
            200,
            {
              'spaces': [
                {'buid': 'b1', 'name': 'Building A'},
                {'buid': 'b2', 'name': 'Building B'},
              ],
            },
            null,
          ));

      final loader = CampusLoader(api, cache);
      final campuses = await loader.loadConfigured();

      expect(campuses, hasLength(1));
      expect(campuses.single.cuid, AppConstants.defaultCampusCuid);
      expect(campuses.single.name, AppConstants.defaultCampusName);
      expect(campuses.single.spaces, hasLength(2));
      expect(cache.spaces, hasLength(2));
      expect(cache.campuses, hasLength(1));
    });

    test('returns empty without throwing when auto-discovery fetch fails',
        () async {
      stub((url, body, headers) =>
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: url),
            reason: 'Connection refused',
          ));

      final loader = CampusLoader(api, cache);
      final campuses = await loader.loadConfigured();

      expect(campuses, isEmpty);
    });

    test('fetches each configured cuid via campus/get', () async {
      final responses = <Map<String, dynamic>>[
        {'name': 'Campus One'},
        {'name': 'Campus Two'},
      ];
      stub((url, body, headers) {
        final resp = responses.isEmpty ? const <String, dynamic>{} : responses.removeAt(0);
        return (url, 200, resp, null);
      });

      final loader = CampusLoader(api, cache);
      final campuses = await loader.loadConfigured(cuids: ['c1', 'c2']);

      expect(campuses, hasLength(2));
      expect(campuses.map((c) => c.cuid), ['c1', 'c2']);
      expect(campuses.map((c) => c.name), ['Campus One', 'Campus Two']);
    });

    test('skips a configured cuid whose campus/get fails', () async {
      var calls = 0;
      stub((url, body, headers) {
        calls++;
        if (calls == 1) {
          return (url, 500, 'boom', null);
        }
        return (url, 200, {'name': 'Good Campus'}, null);
      });

      final loader = CampusLoader(api, cache);
      final campuses = await loader.loadConfigured(cuids: ['bad', 'good']);

      expect(campuses, hasLength(1));
      expect(campuses.single.cuid, 'good');
    });
  });
}

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
    final bytes = data is Uint8List
        ? data
        : Uint8List.fromList(utf8.encode(jsonEncode(data)));
    return ResponseBody.fromBytes(bytes, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
