import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/constants.dart';

/// Temporary skeleton map used during Phase 1 to prove that
/// `flutter_map` renders with the configured tile URL template.
///
/// Self-hosted outdoor tiles (Phase 0.6) are the production source;
/// [AppConstants.outdoorTilesUrl] currently points at a Carto Positron
/// fallback. The tile source is swapped in Phase 3 when the real map
/// screen lands.
class MapPreviewScreen extends StatelessWidget {
  const MapPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CampusFind Map')),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(30.8564, 29.5945), // E-JUST campus area
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: AppConstants.outdoorTilesUrl,
            userAgentPackageName: 'eg.edu.ejust.anyplace_campusfind',
          ),
        ],
      ),
    );
  }
}
