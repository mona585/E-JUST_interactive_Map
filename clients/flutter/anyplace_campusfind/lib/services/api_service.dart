import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api_config.dart';

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

/// Base HTTP client for the Anyplace backend.
///
/// Handles:
///  * JSON body construction for POST endpoints
///  * gzip-compressed responses (Play is configured to gzip by default)
///  * timeouts and typed error mapping
///
/// The backend is reached over plain HTTP in the dev/illustrative setup;
/// cleartext must be allowed on Android for that case (see AndroidManifest).
class ApiService {
  ApiService({Dio? dio, String? baseUrl})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: baseUrl ?? ApiConfig.serverUrl,
          connectTimeout: ApiConfig.requestTimeout,
          receiveTimeout: ApiConfig.requestTimeout,
        ));

  final Dio _dio;

  /// Performs a POST request, sending [body] as JSON (or empty body when null),
  /// and returns the decoded JSON response.
  ///
  /// Play's GZipFilter decompresses transparently at the transport layer for
  /// clients that send `Accept-Encoding: gzip`; [Dio] does this automatically.
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
