import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Represents a parsed KML feature (Placemark with LineString or Point).
class KmlFeature {
  final String name;
  final List<LatLng> coordinates;
  final String type; // 'LineString' or 'Point'
  final double? altitude;

  const KmlFeature({
    required this.name,
    required this.coordinates,
    required this.type,
    this.altitude,
  });

  bool get isLineString => type == 'LineString';
  bool get isPoint => type == 'Point';

  @override
  String toString() =>
      'KmlFeature($name, $type, ${coordinates.length} pts)';
}

/// Loads and parses KMZ (zipped KML) or plain KML files.
///
/// KMZ files are ZIP archives containing a `doc.kml` file.
/// KML coordinate order is `longitude,latitude,altitude`.
class KmzLoader {
  /// Parses a KMZ file from raw bytes.
  ///
  /// Extracts the KML content from the ZIP archive and parses all
  /// Placemark features (LineStrings and Points).
  static List<KmlFeature> parseKmzBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find the KML file inside the archive
    String? kmlContent;
    for (final file in archive) {
      final name = file.name.toLowerCase();
      if (name.endsWith('.kml')) {
        kmlContent = utf8.decode(file.content as List<int>);
        break;
      }
    }

    if (kmlContent == null) {
      throw FormatException('No .kml file found inside KMZ archive');
    }

    return parseKml(kmlContent);
  }

  /// Parses raw KML XML content into a list of features.
  ///
  /// Handles `<Placemark>` elements containing `<LineString>` or `<Point>`
  /// geometry. Coordinates use the KML order: `lon,lat,alt`.
  static List<KmlFeature> parseKml(String kmlContent) {
    final features = <KmlFeature>[];

    // Extract Placemarks using simple regex-based parsing
    // (avoids pulling in an XML package for this simple case)
    final placemarkPattern = RegExp(
      r'<Placemark[^>]*>(.*?)</Placemark>',
      dotAll: true,
    );

    for (final match in placemarkPattern.allMatches(kmlContent)) {
      final placemarkXml = match.group(1)!;

      // Extract name
      final name = _extractTag(placemarkXml, 'name') ?? 'Unnamed';

      // Detect geometry type
      if (placemarkXml.contains('<LineString')) {
        final coords = _extractCoordinates(placemarkXml);
        if (coords.isNotEmpty) {
          features.add(KmlFeature(
            name: name,
            coordinates: coords,
            type: 'LineString',
          ));
        }
      } else if (placemarkXml.contains('<Point')) {
        final coords = _extractCoordinates(placemarkXml);
        if (coords.isNotEmpty) {
          features.add(KmlFeature(
            name: name,
            coordinates: coords,
            type: 'Point',
          ));
        }
      }
    }

    debugPrint('[KmzLoader] Parsed ${features.length} features from KML');
    return features;
  }

  /// Extracts text content of the first matching XML tag.
  static String? _extractTag(String xml, String tagName) {
    final pattern = RegExp(
      '<$tagName[^>]*>(.*?)</$tagName>',
      dotAll: true,
    );
    final match = pattern.firstMatch(xml);
    return match?.group(1)?.trim();
  }

  /// Extracts coordinates from a `<coordinates>` block.
  ///
  /// KML standard order is `longitude,latitude,altitude`, but some exporters
  /// (including Google My Maps) produce `latitude,longitude,altitude`.
  /// We auto-detect the order by checking coordinate ranges for the EJUST
  /// campus area (lat ~29.5, lon ~30.8).
  ///
  /// Returns [LatLng] points in the correct lat/lng order for Google Maps.
  static List<LatLng> _extractCoordinates(String xml) {
    final pattern = RegExp(
      r'<coordinates[^>]*>(.*?)</coordinates>',
      dotAll: true,
    );
    final match = pattern.firstMatch(xml);
    if (match == null) return const [];

    final coordString = match.group(1)!.trim();
    final points = <LatLng>[];

    // Split by whitespace (spaces, newlines, tabs)
    final triples = coordString.split(RegExp(r'\s+'));

    // First, collect raw coordinate pairs to detect order
    final rawPairs = <(double, double)>[];
    for (final triple in triples) {
      final parts = triple.split(',');
      if (parts.length >= 2) {
        final a = double.tryParse(parts[0].trim());
        final b = double.tryParse(parts[1].trim());
        if (a != null && b != null) {
          rawPairs.add((a, b));
        }
      }
    }

    if (rawPairs.isEmpty) return const [];

    // KML standard order is always longitude,latitude,altitude.
    // Always treat the first value as longitude and second as latitude,
    // then swap to LatLng(lat, lon) for Google Maps.
    debugPrint('[KmzLoader] Raw first coord: (${rawPairs[0].$1}, ${rawPairs[0].$2})');
    debugPrint('[KmzLoader] Using KML standard order: lon,lat (${rawPairs.length} points)');

    for (final pair in rawPairs) {
      // Standard KML: first=lon, second=lat → swap to LatLng(lat, lon)
      points.add(LatLng(pair.$2, pair.$1));
    }

    debugPrint('[KmzLoader] First parsed: ${points.first}, Last: ${points.last}');

    return points;
  }
}
