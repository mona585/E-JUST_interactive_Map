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

  /// Line color declared by the feature's own KML style, as an
  /// 0xAARRGGBB integer converted from the KML `aabbggrr` notation.
  /// Null when the feature carries no explicit `<LineStyle><color>`.
  final int? lineColorArgb;

  /// Line width declared by the feature's `<LineStyle><width>` (KML units).
  /// Null when the feature carries no explicit line width.
  final double? lineWidth;

  const KmlFeature({
    required this.name,
    required this.coordinates,
    required this.type,
    this.altitude,
    this.lineColorArgb,
    this.lineWidth,
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
  ///
  /// Per-feature line styling is resolved from the KML style system: an
  /// inline `<Style><LineStyle>` on the Placemark wins; otherwise the
  /// Placemark's `<styleUrl>` is resolved through `<StyleMap>` (using the
  /// `normal` state) to a document-level `<Style>` with its `<LineStyle>`
  /// color/width.
  static List<KmlFeature> parseKml(String kmlContent) {
    final features = <KmlFeature>[];

    final stylesById = _styleBlocksById(kmlContent);
    final styleMapNormals = _styleMapNormalTargets(kmlContent);

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

      // Resolve this feature's own line style, if any
      final lineStyle = _resolveLineStyle(
        placemarkXml,
        stylesById: stylesById,
        styleMapNormals: styleMapNormals,
      );

      // Detect geometry type
      if (placemarkXml.contains('<LineString')) {
        final coords = _extractCoordinates(placemarkXml);
        if (coords.isNotEmpty) {
          features.add(KmlFeature(
            name: name,
            coordinates: coords,
            type: 'LineString',
            lineColorArgb: lineStyle?.colorArgb,
            lineWidth: lineStyle?.width,
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

  /// Document-level `<Style id="...">` blocks keyed by their id.
  static Map<String, String> _styleBlocksById(String kmlContent) {
    final result = <String, String>{};
    final pattern = RegExp(r'<Style\b([^>]*)>(.*?)</Style>', dotAll: true);
    for (final match in pattern.allMatches(kmlContent)) {
      final id = _attrValue(match.group(1)!, 'id');
      if (id != null) result[id] = match.group(2)!;
    }
    return result;
  }

  /// `<StyleMap id="...">` entries mapped to the style id referenced by
  /// their `normal` state (`highlight` is an interactive-only variant).
  static Map<String, String> _styleMapNormalTargets(String kmlContent) {
    final result = <String, String>{};
    final mapPattern = RegExp(
      r'<StyleMap\b([^>]*)>(.*?)</StyleMap>',
      dotAll: true,
    );
    final pairPattern = RegExp(r'<Pair\b[^>]*>(.*?)</Pair>', dotAll: true);
    for (final match in mapPattern.allMatches(kmlContent)) {
      final id = _attrValue(match.group(1)!, 'id');
      if (id == null) continue;
      for (final pair in pairPattern.allMatches(match.group(2)!)) {
        final key = _extractTag(pair.group(1)!, 'key');
        final url = _extractTag(pair.group(1)!, 'styleUrl');
        if (key == 'normal' && url != null && url.startsWith('#')) {
          result[id] = url.substring(1).trim();
          break;
        }
      }
    }
    return result;
  }

  /// Resolves the effective line style of a Placemark.
  ///
  /// Precedence: inline `<Style><LineStyle>` first, then `<styleUrl>`
  /// resolved through [styleMapNormals] into [stylesById].
  /// Returns the declared color/width, or null when no LineStyle applies.
  static _KmlLineStyle? _resolveLineStyle(
    String placemarkXml, {
    required Map<String, String> stylesById,
    required Map<String, String> styleMapNormals,
  }) {
    String? lineStyleBody;

    final inlineStylePattern =
        RegExp(r'<Style\b[^>]*>(.*?)</Style>', dotAll: true);
    final lineStylePattern =
        RegExp(r'<LineStyle\b[^>]*>(.*?)</LineStyle>', dotAll: true);

    for (final style in inlineStylePattern.allMatches(placemarkXml)) {
      final ls = lineStylePattern.firstMatch(style.group(1)!);
      if (ls != null) {
        lineStyleBody = ls.group(1);
        break;
      }
    }

    if (lineStyleBody == null) {
      final styleUrl = _extractTag(placemarkXml, 'styleUrl');
      if (styleUrl != null && styleUrl.startsWith('#')) {
        var styleId = styleUrl.substring(1).trim();
        styleId = styleMapNormals[styleId] ?? styleId;
        final styleBody = stylesById[styleId];
        if (styleBody != null) {
          lineStyleBody = lineStylePattern.firstMatch(styleBody)?.group(1);
        }
      }
    }

    if (lineStyleBody == null) return null;

    final colorText = _extractTag(lineStyleBody, 'color');
    final widthText = _extractTag(lineStyleBody, 'width');

    return _KmlLineStyle(
      colorArgb: colorText == null ? null : kmlColorToArgb(colorText),
      width: widthText == null ? null : double.tryParse(widthText.trim()),
    );
  }

  /// Converts a KML `<color>` value (`aabbggrr`) into 0xAARRGGBB form.
  /// Returns null for malformed input.
  static int? kmlColorToArgb(String hex) {
    final v = hex.trim();
    if (v.length != 8) return null;
    final parsed = int.tryParse(v, radix: 16);
    if (parsed == null) return null;
    final a = (parsed >> 24) & 0xFF;
    final b = (parsed >> 16) & 0xFF;
    final g = (parsed >> 8) & 0xFF;
    final r = parsed & 0xFF;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  /// Extracts an attribute value from a raw attribute string.
  static String? _attrValue(String attrs, String name) {
    final match =
        RegExp('\\b$name\\s*=\\s*"([^"]*)"').firstMatch(attrs);
    return match?.group(1);
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

/// Line style declared by a KML `<LineStyle>` block.
class _KmlLineStyle {
  final int? colorArgb;
  final double? width;

  const _KmlLineStyle({this.colorArgb, this.width});
}
