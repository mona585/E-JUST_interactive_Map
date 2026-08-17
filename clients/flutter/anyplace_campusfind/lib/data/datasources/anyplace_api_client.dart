import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../models/floor_model.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';

/// Exception thrown when an API request fails.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  const ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}

/// HTTP API Client for Anyplace backend.
class AnyplaceApiClient {
  final http.Client _client;
  final String _baseUrl;

  AnyplaceApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  /// Fetches all public spaces from the Anyplace backend.
  /// Calls `POST /api/mapping/space/public` with body `{}`.
  Future<List<SpaceModel>> fetchPublicSpaces() async {
    final uri = Uri.parse('$_baseUrl${ApiConfig.endpointSpacesPublic}');
    debugPrint('[AnyplaceApi] --> POST $uri');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({}),
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for spaces (Length: ${response.bodyBytes.length} bytes)',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load public spaces from backend.',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final Map<String, dynamic> jsonResponse = _decodeJsonResponse(response);

      // Check for backend error payload format {"status": "error", "message": "..."}
      if (jsonResponse['status'] != null &&
          jsonResponse['status'].toString().toLowerCase() == 'error') {
        throw ApiException(
          jsonResponse['message']?.toString() ?? 'Unknown backend error',
        );
      }

      final List<dynamic>? spacesList =
          jsonResponse['spaces'] as List<dynamic>?;
      if (spacesList == null) {
        return <SpaceModel>[];
      }

      final spaces = spacesList
          .whereType<Map<String, dynamic>>()
          .map((spaceJson) => SpaceModel.fromJson(spaceJson))
          .where((space) => space.buid.isNotEmpty)
          .toList();

      debugPrint(
        '[AnyplaceApi] Successfully parsed ${spaces.length} public spaces',
      );
      return spaces;
    } on SocketException catch (e) {
      debugPrint('[AnyplaceApi] SocketException on spaces: ${e.message}');
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      debugPrint('[AnyplaceApi] Timeout on spaces request');
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      debugPrint('[AnyplaceApi] FormatException on spaces: ${e.message}');
      throw ApiException('Invalid response format from server: ${e.message}');
    }
  }

  /// Fetches details for a single space by its `buid`.
  /// Calls `POST /api/mapping/space/get` with body `{"buid": "<buid>"}`.
  Future<SpaceModel> fetchSpaceDetails(String buid) async {
    if (buid.trim().isEmpty) {
      throw const ApiException('Building ID (buid) cannot be empty.');
    }

    final uri = Uri.parse('$_baseUrl${ApiConfig.endpointSpaceGet}');
    debugPrint('[AnyplaceApi] --> POST $uri with buid=$buid');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'buid': buid}),
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for space details',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load space details for buid: $buid',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final Map<String, dynamic> jsonResponse = _decodeJsonResponse(response);

      if (jsonResponse['status'] != null &&
          jsonResponse['status'].toString().toLowerCase() == 'error') {
        throw ApiException(
          jsonResponse['message']?.toString() ?? 'Error retrieving space',
        );
      }

      return SpaceModel.fromJson(jsonResponse);
    } on SocketException catch (e) {
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      throw ApiException('Invalid response format from server: ${e.message}');
    }
  }

  /// Fetches all floors belonging to a specific building by its `buid`.
  /// Calls `POST /api/mapping/floor/all` with body `{"buid": "<buid>"}`.
  Future<List<FloorModel>> fetchFloorsForBuilding(String buid) async {
    final cleanBuid = buid.trim();
    if (cleanBuid.isEmpty) {
      throw const ApiException('Building ID (buid) cannot be empty.');
    }

    final uri = Uri.parse('$_baseUrl${ApiConfig.endpointFloorAll}');
    final requestBody = jsonEncode({'buid': cleanBuid});

    debugPrint('[AnyplaceApi] --> POST $uri');
    debugPrint('[AnyplaceApi] Request Body: $requestBody');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for buid=$cleanBuid (Raw Bytes: ${response.bodyBytes.length})',
      );

      if (response.statusCode != 200) {
        debugPrint(
          '[AnyplaceApi] Non-200 status code ${response.statusCode}: ${response.body}',
        );
        throw ApiException(
          'Failed to load floors for building buid: $cleanBuid (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final Map<String, dynamic> jsonResponse = _decodeJsonResponse(response);

      if (jsonResponse['status'] != null &&
          jsonResponse['status'].toString().toLowerCase() == 'error') {
        final errorMsg =
            jsonResponse['message']?.toString() ?? 'Error retrieving floors';
        debugPrint('[AnyplaceApi] Backend error response: $errorMsg');
        throw ApiException(errorMsg);
      }

      final List<dynamic>? floorsList =
          jsonResponse['floors'] as List<dynamic>?;
      if (floorsList == null || floorsList.isEmpty) {
        debugPrint('[AnyplaceApi] Zero floors mapped for buid=$cleanBuid');
        return <FloorModel>[];
      }

      final floors = <FloorModel>[];
      for (final dynamic item in floorsList) {
        if (item is Map<String, dynamic>) {
          try {
            final floorMap = Map<String, dynamic>.from(item);
            // Ensure parent buid is set if omitted by backend
            if (floorMap['buid'] == null ||
                floorMap['buid'].toString().trim().isEmpty) {
              floorMap['buid'] = cleanBuid;
            }
            floors.add(FloorModel.fromJson(floorMap));
          } catch (e) {
            debugPrint('[AnyplaceApi] Error parsing floor record: $e');
          }
        }
      }

      // Sort floors in natural numeric order (e.g. -1, 0, 1, 2)
      floors.sort();
      debugPrint(
        '[AnyplaceApi] Successfully parsed and sorted ${floors.length} floors for $cleanBuid: ${floors.map((f) => f.displayName).toList()}',
      );
      return floors;
    } on SocketException catch (e) {
      debugPrint('[AnyplaceApi] SocketException: ${e.message}');
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      debugPrint('[AnyplaceApi] TimeoutException fetching floors');
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      debugPrint('[AnyplaceApi] FormatException parsing floors: ${e.message}');
      throw ApiException('Invalid response format from server: ${e.message}');
    } catch (e) {
      debugPrint('[AnyplaceApi] Unexpected error fetching floors: $e');
      rethrow;
    }
  }

  /// Fetches radiomap metadata for a space and floor.
  /// Calls `POST /api/radiomap/space` with body `{"buid": "<buid>", "floor": "<floor>"}`.
  Future<String> fetchRadioMapMetadata(String buid, String floor) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    if (cleanBuid.isEmpty) {
      throw const ApiException('Building ID (buid) cannot be empty.');
    }
    if (cleanFloor.isEmpty) {
      throw const ApiException('Floor number cannot be empty.');
    }

    final uri = Uri.parse('$_baseUrl${ApiConfig.endpointRadiomapSpace}');
    final requestBody = jsonEncode({'buid': cleanBuid, 'floor': cleanFloor});

    debugPrint('[AnyplaceApi] --> POST $uri');
    debugPrint('[AnyplaceApi] Request Body: $requestBody');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for radiomap metadata (buid: $cleanBuid, floor: $cleanFloor)',
      );

      if (response.statusCode != 200) {
        try {
          final errJson = _decodeJsonResponse(response);
          final msg =
              errJson['message']?.toString() ??
              'Failed to retrieve radiomap metadata';
          throw ApiException(
            msg,
            statusCode: response.statusCode,
            details: response.body,
          );
        } catch (e) {
          if (e is ApiException) rethrow;
          throw ApiException(
            'Failed to retrieve radiomap metadata (HTTP ${response.statusCode})',
            statusCode: response.statusCode,
            details: response.body,
          );
        }
      }

      final Map<String, dynamic> jsonResponse = _decodeJsonResponse(response);

      if (jsonResponse['status'] != null &&
          jsonResponse['status'].toString().toLowerCase() == 'error') {
        final errorMsg =
            jsonResponse['message']?.toString() ?? 'Error retrieving radiomap';
        throw ApiException(errorMsg, statusCode: response.statusCode);
      }

      final mapUrlMean = jsonResponse['map_url_mean']?.toString();
      if (mapUrlMean == null || mapUrlMean.trim().isEmpty) {
        throw const ApiException(
          'Backend response did not contain map_url_mean.',
        );
      }

      return mapUrlMean;
    } on SocketException catch (e) {
      debugPrint('[AnyplaceApi] SocketException: ${e.message}');
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      debugPrint('[AnyplaceApi] TimeoutException fetching radiomap metadata');
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      debugPrint('[AnyplaceApi] FormatException: ${e.message}');
      throw ApiException('Invalid response format from server: ${e.message}');
    }
  }

  /// Downloads raw plaintext RadioMap file from the frozen radiomap endpoint.
  /// Calls normalized `POST /api/radiomaps_frozen/{space}/{floor}/{filename}` with body `{}`.
  Future<String> fetchRadioMapRaw(
    String buid,
    String floor, {
    String filename = ApiConfig.defaultRadiomapMeanFilename,
  }) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    final cleanFilename = filename.trim();

    final normalizedPath =
        '${ApiConfig.endpointRadiomapFrozen}/$cleanBuid/$cleanFloor/$cleanFilename';
    final uri = Uri.parse('$_baseUrl$normalizedPath');

    debugPrint('[AnyplaceApi] --> POST normalized radiomap download: $uri');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': '*/*'},
            body: jsonEncode({}),
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for raw radiomap download (Raw Bytes: ${response.bodyBytes.length})',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to download radiomap file (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final text = _decodePlainTextResponse(response);

      if (text.trim().isEmpty) {
        throw const ApiException('Downloaded radiomap is empty.');
      }

      // Check for backend error payload format in text
      if (text.startsWith('{') && text.contains('"status":"error"')) {
        try {
          final dynamic errJson = jsonDecode(text);
          if (errJson is Map<String, dynamic>) {
            throw ApiException(
              errJson['message']?.toString() ?? 'Error downloading radiomap',
            );
          }
        } catch (e) {
          if (e is ApiException) rethrow;
        }
      }

      debugPrint(
        '[AnyplaceApi] Successfully downloaded radiomap (${text.length} chars, ${text.split('\n').length} lines)',
      );
      return text;
    } on SocketException catch (e) {
      debugPrint('[AnyplaceApi] SocketException: ${e.message}');
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      debugPrint('[AnyplaceApi] TimeoutException downloading radiomap file');
      throw const ApiException('Connection to Anyplace backend timed out.');
    }
  }

  /// High-level method to fetch RadioMap: requests metadata and then downloads the normalized raw RadioMap text.
  Future<String> fetchRadioMap(String buid, String floor) async {
    // 1. Fetch metadata to verify floor radiomap exists and is supported
    await fetchRadioMapMetadata(buid, floor);

    // 2. Download the normalized mean radiomap plain text file
    return await fetchRadioMapRaw(buid, floor);
  }

  /// Downloads and decodes the official Base64 floorplan image for a building and floor.
  /// Calls `POST /api/floorplans64/{buid}/{floor}` with body `{}`.
  ///
  /// Returns decoded PNG [Uint8List] bytes.
  Future<Uint8List> fetchFloorplanImage(String buid, String floor) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    if (cleanBuid.isEmpty) {
      throw const ApiException('Building ID (buid) cannot be empty.');
    }
    if (cleanFloor.isEmpty) {
      throw const ApiException('Floor number cannot be empty.');
    }

    final uri = Uri.parse(
      '$_baseUrl${ApiConfig.endpointFloorplans64}/$cleanBuid/$cleanFloor',
    );
    debugPrint('[AnyplaceApi] --> POST floorplan image: $uri');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': '*/*'},
            body: jsonEncode({}),
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for floorplan image ($cleanBuid, floor $cleanFloor, raw bytes: ${response.bodyBytes.length})',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to download floorplan image (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      // Decode plaintext/GZIP body string
      final base64String = _decodePlainTextResponse(response).trim();
      if (base64String.isEmpty) {
        throw const ApiException('Floorplan image data is empty.');
      }

      // Check if server returned an error JSON message instead of image
      if (base64String.startsWith('{') &&
          base64String.contains('"status":"error"')) {
        try {
          final dynamic errJson = jsonDecode(base64String);
          if (errJson is Map<String, dynamic>) {
            final msg =
                errJson['message']?.toString() ?? 'Floorplan not found.';
            throw ApiException(msg, statusCode: 404);
          }
        } catch (e) {
          if (e is ApiException) rethrow;
        }
      }

      // Clean any potential data URL prefix ("data:image/png;base64,")
      String cleanBase64 = base64String;
      final commaIndex = cleanBase64.indexOf(',');
      if (commaIndex != -1 &&
          cleanBase64.substring(0, commaIndex).contains('base64')) {
        cleanBase64 = cleanBase64.substring(commaIndex + 1);
      }

      // Decode Base64 to image bytes
      final imageBytes = base64Decode(cleanBase64);
      if (imageBytes.isEmpty) {
        throw const ApiException('Decoded floorplan image is empty.');
      }

      debugPrint(
        '[AnyplaceApi] Successfully decoded floorplan image (${imageBytes.length} bytes)',
      );

      return imageBytes;
    } on SocketException catch (e) {
      debugPrint(
        '[AnyplaceApi] SocketException on floorplan image: ${e.message}',
      );
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      debugPrint('[AnyplaceApi] Timeout downloading floorplan image');
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      debugPrint(
        '[AnyplaceApi] FormatException decoding floorplan Base64: ${e.message}',
      );
      throw ApiException('Failed to decode floorplan image: ${e.message}');
    }
  }

  /// Fetches all POIs for a specific building and floor.
  /// Calls `POST /api/mapping/pois/floor/all` with body `{"buid": "<buid>", "floor_number": "<floor>"}`.
  Future<List<PoiModel>> fetchPoisByFloor(String buid, String floor) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    if (cleanBuid.isEmpty) {
      throw const ApiException('Building ID (buid) cannot be empty.');
    }
    if (cleanFloor.isEmpty) {
      throw const ApiException('Floor number cannot be empty.');
    }

    final uri = Uri.parse('$_baseUrl${ApiConfig.endpointPoisFloorAll}');
    final requestBody = jsonEncode({
      'buid': cleanBuid,
      'floor_number': cleanFloor,
    });
    debugPrint('[AnyplaceApi] --> POST POIs by floor: $uri');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': '*/*'},
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for POIs ($cleanBuid, floor $cleanFloor)',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch POIs for floor (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final jsonMap = _decodeJsonResponse(response);

      if (jsonMap.containsKey('status') && jsonMap['status'] == 'error') {
        final message = jsonMap['message']?.toString() ?? 'Failed to load POIs';
        throw ApiException(message, statusCode: response.statusCode);
      }

      final dynamic poisJson = jsonMap['pois'];
      if (poisJson is! List) {
        debugPrint(
          '[AnyplaceApi] No pois list found in response for $cleanBuid floor $cleanFloor',
        );
        return const [];
      }

      final pois = poisJson
          .whereType<Map<String, dynamic>>()
          .map((item) => PoiModel.fromJson(item))
          .toList();

      debugPrint(
        '[AnyplaceApi] Successfully parsed ${pois.length} POIs for $cleanBuid floor $cleanFloor',
      );

      return pois;
    } on SocketException catch (e) {
      debugPrint('[AnyplaceApi] SocketException fetching POIs: ${e.message}');
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      debugPrint('[AnyplaceApi] Timeout fetching POIs');
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      debugPrint(
        '[AnyplaceApi] FormatException parsing POIs JSON: ${e.message}',
      );
      throw ApiException('Invalid response format from server: ${e.message}');
    }
  }

  /// Fetches a route between two POIs using the Anyplace navigation API.
  Future<NavigationRouteModel> fetchNavigationRoute({
    required String fromPuid,
    required String toPuid,
  }) async {
    final cleanFromPuid = fromPuid.trim();
    final cleanToPuid = toPuid.trim();

    if (cleanFromPuid.isEmpty) {
      throw const ApiException('Source POI ID cannot be empty.');
    }
    if (cleanToPuid.isEmpty) {
      throw const ApiException('Destination POI ID cannot be empty.');
    }

    final uri = Uri.parse('$_baseUrl${ApiConfig.endpointNavigationRoute}');
    final requestBody = jsonEncode({
      'pois_from': cleanFromPuid,
      'pois_to': cleanToPuid,
    });

    debugPrint('[AnyplaceApi] --> POST navigation route: $uri');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': '*/*'},
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for route ($cleanFromPuid -> $cleanToPuid)',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch route (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final jsonMap = _decodeJsonResponse(response);

      if (jsonMap['status']?.toString().toLowerCase() == 'error') {
        throw ApiException(
          jsonMap['message']?.toString() ?? 'Failed to calculate route.',
          statusCode: response.statusCode,
        );
      }

      return NavigationRouteModel.fromJson(jsonMap);
    } on SocketException catch (e) {
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      throw ApiException('Invalid response format from server: ${e.message}');
    }
  }

  /// Fetches a route from coordinates on a floor to a destination POI.
  Future<NavigationRouteModel> fetchNavigationRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async {
    final cleanFloor = floorNumber.trim();
    final cleanDestinationPuid = destinationPuid.trim();

    if (cleanFloor.isEmpty) {
      throw const ApiException('Floor number cannot be empty.');
    }
    if (cleanDestinationPuid.isEmpty) {
      throw const ApiException('Destination POI ID cannot be empty.');
    }

    final uri = Uri.parse(
      '$_baseUrl${ApiConfig.endpointNavigationRouteCoordinates}',
    );
    final requestBody = jsonEncode({
      'coordinates_lat': latitude.toString(),
      'coordinates_lon': longitude.toString(),
      'floor_number': cleanFloor,
      'pois_to': cleanDestinationPuid,
    });

    debugPrint('[AnyplaceApi] --> POST coordinate navigation route: $uri');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': '*/*'},
            body: requestBody,
          )
          .timeout(ApiConfig.requestTimeout);

      debugPrint(
        '[AnyplaceApi] <-- HTTP ${response.statusCode} for coordinate route (floor=$cleanFloor, destination=$cleanDestinationPuid)',
      );

      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to fetch route (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
          details: response.body,
        );
      }

      final jsonMap = _decodeJsonResponse(response);

      if (jsonMap['status']?.toString().toLowerCase() == 'error') {
        throw ApiException(
          jsonMap['message']?.toString() ?? 'Failed to calculate route.',
          statusCode: response.statusCode,
        );
      }

      return NavigationRouteModel.fromJson(jsonMap);
    } on SocketException catch (e) {
      throw ApiException('Network connection error: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Connection to Anyplace backend timed out.');
    } on FormatException catch (e) {
      throw ApiException('Invalid response format from server: ${e.message}');
    }
  }

  /// Helper to safely decode JSON response, handling gzip decompression if needed.
  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final text = _decodePlainTextResponse(response);
    final dynamic decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Expected JSON object at root of response.');
  }

  /// Helper to safely decode plaintext response, handling gzip decompression if needed.
  String _decodePlainTextResponse(http.Response response) {
    final bytes = response.bodyBytes;

    // Check for GZIP magic bytes (0x1F, 0x8B)
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      debugPrint(
        '[AnyplaceApi] Decompressing GZIP response bytes (${bytes.length} bytes)...',
      );
      final decompressed = gzip.decode(bytes);
      return utf8.decode(decompressed, allowMalformed: true);
    }

    return response.body;
  }

  /// Closes the client when done.
  void dispose() {
    _client.close();
  }
}
