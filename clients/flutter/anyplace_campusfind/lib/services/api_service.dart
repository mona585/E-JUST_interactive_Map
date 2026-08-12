import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/campus.dart';
import '../models/floor.dart';
import '../models/poi.dart';
import '../models/position.dart';
import '../models/route.dart';
import '../models/space.dart';

/// Thrown when the backend returns a non-success status or the payload
/// cannot be parsed.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// HTTP client for the Anyplace backend with typed methods for every public
/// endpoint the app uses.
///
/// Handles:
///  * JSON body construction for POST endpoints
///  * gzip-compressed responses (Play is configured to gzip by default;
///    [Dio] negotiates `Accept-Encoding: gzip` and decompresses transparently)
///  * timeouts and typed error mapping
class ApiService {
  ApiService({Dio? dio, String? baseUrl})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: baseUrl ?? ApiConfig.serverUrl,
          connectTimeout: ApiConfig.requestTimeout,
          receiveTimeout: ApiConfig.requestTimeout,
        ));

  final Dio _dio;

  /// POST /api/mapping/space/public — all published buildings.
  Future<List<Space>> fetchPublicSpaces() async {
    final json = await _postJsonObject(ApiConfig.spacePublic, body: const {});
    final list = (json['spaces'] as List<dynamic>? ??
            json['buildings'] as List<dynamic>? ??
            const [])
        .cast<Map<String, dynamic>>();
    return list.map(Space.fromJson).toList();
  }

  /// POST /api/mapping/campus/get — one campus by cuid, with its spaces.
  Future<Campus> fetchCampus(String cuid) async {
    final json = await _postJsonObject(ApiConfig.campusGet,
        body: {'cuid': cuid});
    json['cuid'] = cuid;
    return Campus.fromJson(json);
  }

  /// POST /api/mapping/floor/all — all floors of a building.
  Future<List<Floor>> fetchFloors(String buid) async {
    final json = await _postJsonObject(ApiConfig.floorAll, body: {'buid': buid});
    final list = (json['floors'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return list.map(Floor.fromJson).toList();
  }

  /// POST /api/mapping/pois/space/all — all POIs of a building.
  Future<List<Poi>> fetchPois(String buid) async {
    final json = await _postJsonObject(ApiConfig.poisSpaceAll,
        body: {'buid': buid});
    final list = (json['pois'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return list.map(Poi.fromJson).toList();
  }

  /// POST /api/mapping/pois/search — search POIs of a building by letters.
  Future<List<Poi>> searchPois(
    String buid,
    String letters, {
    String? cuid,
    bool greeklish = false,
  }) async {
    final json = await _postJsonObject(ApiConfig.poisSearch, body: {
      'cuid': cuid ?? '',
      'letters': letters,
      'buid': buid,
      'greeklish': greeklish.toString(),
    });
    final list = (json['pois'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return list.map(Poi.fromJson).toList();
  }

  /// POST /api/navigation/route — POI-to-POI indoor route.
  Future<NavigationRoute> fetchNavigationRoute(String puidFrom, String puidTo) async {
    final json = await _postJsonObject(ApiConfig.navigationRoute, body: {
      'pois_from': puidFrom,
      'pois_to': puidTo,
    });
    return NavigationRoute.fromJson(json);
  }

  /// POST /api/navigation/route/coordinates — route from a coordinate on a floor.
  Future<NavigationRoute> fetchNavigationRouteFromCoords({
    required double coordinatesLat,
    required double coordinatesLon,
    required String floorNumber,
    required String poisTo,
  }) async {
    final json = await _postJsonObject(ApiConfig.navigationRouteCoordinates,
        body: {
          'coordinates_lat': coordinatesLat.toString(),
          'coordinates_lon': coordinatesLon.toString(),
          'floor_number': floorNumber,
          'pois_to': poisTo,
        });
    return NavigationRoute.fromJson(json);
  }

  /// POST /api/position/estimate — server-side Wi-Fi fingerprint positioning.
  ///
  /// [accessPoints] is a list of `{bssid, rss}` maps; the backend expects it
  /// as a JSON string under the `APs` key.
  Future<PositionEstimate> estimatePosition({
    required String buid,
    required String floor,
    required List<Map<String, dynamic>> accessPoints,
    int algorithmChoice = 2,
  }) async {
    final json = await _postJsonObject(ApiConfig.positionEstimate, body: {
      'buid': buid,
      'floor': floor,
      'APs': jsonEncode(accessPoints),
      'algorithm_choice': algorithmChoice.toString(),
    });
    return PositionEstimate.fromJson(json);
  }

  /// POST /api/floortiles/zip/:buid/:floor — raw zip bytes of floorplan tiles.
  Future<Uint8List> fetchFloorTilesZip(String buid, String floorNumber) async {
    try {
      final response = await _dio.post<List<int>>(
        ApiConfig.floorTilesZip(buid, floorNumber),
        data: '{}',
        options: Options(
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          responseType: ResponseType.bytes,
        ),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> _postJsonObject(
    String url, {
    Map<String, dynamic>? body,
  }) async {
    final data = await postJson(url, body: body);
    if (data is Map<String, dynamic>) return data;
    throw ApiException('Unexpected payload shape from $url');
  }

  /// Performs a POST request, sending [body] as JSON (or empty body when null),
  /// and returns the decoded JSON response.
  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? body,
    bool expectBytes = false,
  }) async {
    try {
      final response = await _dio.post(
        url,
        data: body == null ? null : jsonEncode(body),
        options: Options(
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.acceptHeader: 'application/json',
          },
          responseType: expectBytes
              ? ResponseType.bytes
              : ResponseType.json,
        ),
      );
      return _decodeResponse(response);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Performs a GET request and returns raw bytes (used for tile zips).
  Future<Uint8List> getBytes(String url) async {
    try {
      final response = await _dio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? Uint8List(0);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  dynamic _decodeResponse(Response<dynamic> response) {
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      return response.data;
    }
    throw ApiException(
      'Request failed with status ${response.statusCode}',
      statusCode: response.statusCode,
      body: response.data?.toString(),
    );
  }

  ApiException _mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException('Connection timed out', statusCode: 408);
      case DioExceptionType.connectionError:
        return ApiException('Cannot reach server: ${e.message}');
      case DioExceptionType.badResponse:
        return ApiException(
          'Server error ${e.response?.statusCode}',
          statusCode: e.response?.statusCode,
          body: e.response?.data?.toString(),
        );
      default:
        return ApiException('Network error: ${e.message}');
    }
  }
}
