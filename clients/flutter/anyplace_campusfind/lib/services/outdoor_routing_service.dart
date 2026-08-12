import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/outdoor_route.dart';

/// Thrown when OSRM returns a non-"Ok" status or the payload is malformed.
class OutdoorRoutingException implements Exception {
  OutdoorRoutingException(this.message);

  final String message;

  @override
  String toString() => 'OutdoorRoutingException: $message';
}

/// Client for the public OSRM demo server (`router.project-osrm.org`).
///
/// Used for the outdoor leg of navigation (GPS position → building entrance).
/// The public demo is rate-limited; production should self-host OSRM (see
/// project plan).
class OutdoorRoutingService {
  OutdoorRoutingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  void close() {
    _client.close();
  }

  /// OSRM demo base URL. No API key required.
  static const String baseUrl = 'https://router.project-osrm.org';

  /// Fetches a driving route between [from] and [to].
  ///
  /// Throws [OutdoorRoutingException] when the server reports a non-`Ok` code
  /// or the response cannot be parsed.
  Future<OutdoorRoute> route(
    LatLng from,
    LatLng to, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/${_coord(from)};${_coord(to)}'
      '?overview=full&geometries=geojson&steps=false',
    );

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } catch (e) {
      throw OutdoorRoutingException('Request failed: $e');
    }

    if (response.statusCode != 200) {
      throw OutdoorRoutingException(
        'OSRM returned HTTP ${response.statusCode}',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw OutdoorRoutingException('Malformed OSRM response');
    }

    if (json['code'] != 'Ok') {
      throw OutdoorRoutingException(
        'OSRM status: ${json['code']} (${json['message'] ?? ''})',
      );
    }

    final routes = json['routes'] as List<dynamic>? ?? const [];
    if (routes.isEmpty) {
      throw OutdoorRoutingException('OSRM returned no routes');
    }
    final first = routes.first as Map<String, dynamic>;
    final geometry = first['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List<dynamic>? ?? const [];

    final points = coords
        .map((c) => (c as List<dynamic>).cast<num>())
        .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
        .toList();

    return OutdoorRoute(
      points: points,
      distance: (first['distance'] as num?)?.toDouble(),
      duration: (first['duration'] as num?)?.toDouble(),
    );
  }

  String _coord(LatLng p) => '${p.longitude},${p.latitude}';
}
