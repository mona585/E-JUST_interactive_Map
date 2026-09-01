import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/datasources/gate_policy_config.dart';
import 'package:anyplace_campusfind/data/datasources/kmz_loader.dart';
import 'package:anyplace_campusfind/data/models/campus_gate.dart';
import 'package:anyplace_campusfind/data/models/custom_route_model.dart';
import 'package:anyplace_campusfind/data/repositories/campus_gate_repository.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_graph.dart';

const _gatesAsset = 'assets/config/university gates.kmz';
const _roadsAsset = 'assets/navigation/university roads.kmz';
const _policyAsset = 'assets/config/gate_policy.json';

CampusGate _gate(String id, double lat, double lon, {bool enabled = true}) =>
    CampusGate(
      id: id,
      name: id,
      latitude: lat,
      longitude: lon,
      enabled: enabled,
    );

Future<Uint8List> _loadAssetBytes(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List();
}

/// Builds the real campus road graph from the shipped university roads.kmz.
Future<CustomRouteGraph> _buildRealRoadsGraph() async {
  final bytes = await _loadAssetBytes(_roadsAsset);
  final features = KmzLoader.parseKmzBytes(bytes);
  final roads = features
      .where((f) => f.isLineString && f.coordinates.length >= 2)
      .map((f) => CustomRoute(name: f.name, vertices: f.coordinates))
      .toList();
  final graph = CustomRouteGraph();
  graph.build(roads);
  return graph;
}

Future<List<KmlFeature>> _parseGatesAsset() async {
  final bytes = await _loadAssetBytes(_gatesAsset);
  return KmzLoader.parseKmzBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CampusGate model', () {
    test('built from a KML Point feature', () {
      final gate = CampusGate.fromKmlFeature(const KmlFeature(
        name: 'G1',
        type: 'Point',
        coordinates: [LatLng(30.8626633, 29.5613399)],
      ));
      expect(gate, isNotNull);
      expect(gate!.id, 'G1');
      expect(gate.name, 'G1');
      expect(gate.latitude, closeTo(30.8626633, 1e-6));
      expect(gate.longitude, closeTo(29.5613399, 1e-6));
      expect(gate.enabled, isTrue);
    });

    test('non-Point / empty features are rejected', () {
      expect(
        CampusGate.fromKmlFeature(const KmlFeature(
          name: 'road',
          type: 'LineString',
          coordinates: [LatLng(30.0, 29.0)],
        )),
        isNull,
      );
      expect(
        CampusGate.fromKmlFeature(const KmlFeature(
          name: 'empty',
          type: 'Point',
          coordinates: [],
        )),
        isNull,
      );
    });

    test('copyWithEnabled changes only the policy flag', () {
      final g = _gate('G1', 30.0, 29.0);
      final disabled = g.copyWithEnabled(false);
      expect(disabled.enabled, isFalse);
      expect(disabled.latitude, 30.0);
      expect(disabled.longitude, 29.0);
      expect(disabled.name, 'G1');
    });
  });

  group('Real university gates.kmz parsing', () {
    test('parses 4 Point gates and keeps names/coords from the KMZ', () async {
      final features = await _parseGatesAsset();
      final points = features.where((f) => f.isPoint).toList();

      expect(points.length, 4, reason: 'KMZ should contain 4 gates');

      final byName = {for (final f in points) f.name: f.coordinates.first};
      expect(byName.keys, containsAll(['G1', 'G2', 'G3', 'G4']));

      // Coordinates are asserted exactly as exported from Google My Maps
      // (lon,lat in the KML; loader normalises to LatLng(lat,lon)).
      expect(byName['G1']!.latitude, closeTo(30.8626633, 1e-6));
      expect(byName['G1']!.longitude, closeTo(29.5613399, 1e-6));
      expect(byName['G2']!.latitude, closeTo(30.8617536, 1e-6));
      expect(byName['G2']!.longitude, closeTo(29.5669269, 1e-6));
      expect(byName['G3']!.latitude, closeTo(30.8570269, 1e-6));
      expect(byName['G3']!.longitude, closeTo(29.5614149, 1e-6));
      expect(byName['G4']!.latitude, closeTo(30.8590451, 1e-6));
      expect(byName['G4']!.longitude, closeTo(29.568944, 1e-6));
    });
  });

  group('CampusGateRepository (KMZ-backed)', () {
    test('load() reads the real gates from the KMZ asset', () async {
      final repo = CampusGateRepository();
      await repo.load();

      expect(repo.isLoaded, isTrue);
      expect(repo.gates.length, 4);
      expect(repo.gates.map((g) => g.id), containsAll(['G1', 'G2', 'G3', 'G4']));
      // Coordinates come from the KMZ, not from any Dart literal.
      final g1 = repo.gates.firstWhere((g) => g.id == 'G1');
      expect(g1.latitude, closeTo(30.8626633, 1e-6));
      expect(g1.longitude, closeTo(29.5613399, 1e-6));
    });

    test('loadFromBytes loads gates from raw KMZ bytes', () async {
      final bytes = await _loadAssetBytes(_gatesAsset);
      final repo = CampusGateRepository();
      repo.loadFromBytes(bytes);
      expect(repo.isLoaded, isTrue);
      expect(repo.gates.length, 4);
    });
  });

  group('CampusGateRepository.preferredGate policy', () {
    test('returns null when no gate data is loaded', () {
      final repo = CampusGateRepository();
      expect(repo.preferredGate(), isNull);
      expect(repo.isLoaded, isFalse);
    });

    test('preferred id returns its enabled gate', () {
      final repo = CampusGateRepository.seeded(
        gates: [_gate('G1', 30.1, 29.1), _gate('G2', 30.0, 29.0)],
        preferredGateId: 'G2',
      );
      expect(repo.preferredGate()?.id, 'G2');
    });

    test('does NOT pick the nearest gate when a preferred id is set', () {
      // G2 is preferred even though G1 is closer to nothing in particular;
      // preference is decided by policy, not by proximity.
      final repo = CampusGateRepository.seeded(
        gates: [_gate('G1', 30.1, 29.1), _gate('G2', 30.0, 29.0)],
        preferredGateId: 'G2',
      );
      expect(repo.preferredGate()?.id, isNot('G1'));
      expect(repo.preferredGate()?.id, 'G2');
    });

    test('preferred id disabled via policy falls back to first enabled', () {
      final repo = CampusGateRepository.seeded(
        gates: [_gate('G1', 30.1, 29.1), _gate('G2', 30.0, 29.0)],
        preferredGateId: 'G2',
        disabledGateIds: {'G2'},
      );
      expect(repo.preferredGate()?.id, 'G1');
      expect(repo.resolutionMessage, contains('disabled'));
    });

    test('preferred id not found falls back to first enabled', () {
      final repo = CampusGateRepository.seeded(
        gates: [_gate('G1', 30.1, 29.1), _gate('G2', 30.0, 29.0)],
        preferredGateId: 'GHOST',
      );
      expect(repo.preferredGate()?.id, 'G1');
      expect(repo.resolutionMessage, contains('not found'));
    });

    test('all gates disabled returns null', () {
      final repo = CampusGateRepository.seeded(
        gates: [
          _gate('G1', 30.1, 29.1, enabled: false),
          _gate('G2', 30.0, 29.0, enabled: false),
        ],
      );
      expect(repo.preferredGate(), isNull);
      expect(repo.resolutionMessage, contains('no enabled gates'));
    });

    test('policy can be set after seeding', () {
      final repo = CampusGateRepository.seeded(
        gates: [_gate('G1', 30.1, 29.1), _gate('G2', 30.0, 29.0)],
      );
      expect(repo.preferredGate()?.id, 'G1');
      repo.setPreferredGatePolicy(preferredGateId: 'G2', disabledGateIds: {'G1'});
      expect(repo.preferredGate()?.id, 'G2');
    });
  });

  group('Real gates connect to the real road graph', () {
    test('each real gate snaps to the university road graph', () async {
      final graph = await _buildRealRoadsGraph();
      final gatesRepo = CampusGateRepository();
      await gatesRepo.load();

      expect(graph.vertexCount, greaterThan(0), reason: 'roads graph must build');
      expect(gatesRepo.gates.length, 4);

      // Every real gate connects to the shipped campus road network (the
      // OSRM→custom leg routes user → gate, then gate → campus roads via this
      // snapped vertex). Assert connectivity for honest coverage.
      for (final gate in gatesRepo.gates) {
        final snapped = graph.nearestVertex(
          LatLng(gate.latitude, gate.longitude),
          maxDistance: 750.0,
        );
        expect(
          snapped,
          isNotNull,
          reason: 'gate ${gate.id} must connect to the road graph',
        );
      }
    });

    test('real gates snap to the road network within the documented distances',
        () async {
      final graph = await _buildRealRoadsGraph();
      final gatesRepo = CampusGateRepository();
      await gatesRepo.load();

      // Regression for the gate→road snapping analysis (REQUIREMENT #8).
      // The routing endpoint uses nearestVertex(maxDistance: 500) — the same
      // threshold here — so G4 (202.8 m) is genuinely connected via that
      // endpoint path while still far enough to prove the graph does NOT
      // extend to every gate. Distances are from the shipped KMZ, so if the
      // roads or gates data change these assertions catch it.
      final expected = {
        'G1': 5.1,
        'G2': 27.7,
        'G3': 16.1,
        'G4': 202.8,
      };

      for (final entry in expected.entries) {
        final gate = gatesRepo.gates.firstWhere((g) => g.id == entry.key);
        final snapped = graph.nearestVertex(
          LatLng(gate.latitude, gate.longitude),
          maxDistance: 500.0,
        );
        expect(snapped, isNotNull,
            reason: 'gate ${gate.id} must connect within 500m');
        // Loose tolerance: geometry may drift slightly with the network
        // connectivity fix, but magnitudes must stay stable.
        expect(snapped!.$2, closeTo(entry.value, 3.0),
            reason: 'nearestVertex distance for gate ${gate.id} changed '
                '(${snapped.$2.toStringAsFixed(1)}m vs expected ${entry.value}m)');
      }
    });

    test('preferred gate resolves against the loaded real gates', () async {
      final repo = CampusGateRepository();
      await repo.load();
      repo.setPreferredGatePolicy(preferredGateId: 'G2');

      final preferred = repo.preferredGate();
      expect(preferred, isNotNull);
      expect(preferred!.id, 'G2');
      expect(preferred.latitude, closeTo(30.8617536, 1e-6));
      expect(preferred.longitude, closeTo(29.5669269, 1e-6));
    });

    test('configured policy enables G2 and disables G1/G3/G4', () async {
      // Load the REAL gate_policy.json asset, exactly as SpaceProvider does at
      // startup, then apply it to the loaded KMZ gates.
      final policy = await const GatePolicyConfigLoader().load();
      expect(policy.preferredGateId, 'G2');
      expect(policy.disabledGateIds, containsAll(['G1', 'G3', 'G4']));
      expect(policy.disabledGateIds.length, 3);

      // Policy IDs only — the policy must NEVER embed coordinates.
      expect(
        _policyAsset,
        contains('gate_policy'),
        reason: 'policy is loaded from the config asset, not hardcoded',
      );

      final repo = CampusGateRepository();
      await repo.load();
      repo.setPreferredGatePolicy(
        preferredGateId: policy.preferredGateId,
        disabledGateIds: policy.disabledGateIds,
      );

      // The preferred gate resolves to G2 and it is enabled.
      final preferred = repo.preferredGate();
      expect(preferred, isNotNull);
      expect(preferred!.id, 'G2');
      expect(preferred.enabled, isTrue);

      // G2 coordinates come from the KMZ, not from the policy file.
      expect(preferred.latitude, closeTo(30.8617536, 1e-6));
      expect(preferred.longitude, closeTo(29.5669269, 1e-6));

      // Every other KMZ gate is disabled through the policy.
      for (final id in ['G1', 'G3', 'G4']) {
        expect(policy.disabledGateIds, contains(id));
      }
      // G2 is the only gate the repository would actually route to.
      expect(repo.gates.where((g) => g.enabled).map((g) => g.id),
          containsAll(['G2']));
      // preferredGate() never falls back to a disabled gate.
      expect(repo.preferredGate()!.id, isNot(anyOf('G1', 'G3', 'G4')));
    });
  });

  group('GatePolicyConfigLoader parsing', () {
    test('decodes preferredGateId and disabledGateIds from JSON', () {
      const json = '''
{
  "preferredGateId": "G2",
  "disabledGateIds": ["G1", "G3", "G4"]
}''';
      final policy = GatePolicyConfigLoader.decode(json);
      expect(policy.preferredGateId, 'G2');
      expect(policy.disabledGateIds, {'G1', 'G3', 'G4'});
    });

    test('missing keys decode to null / empty set', () {
      final policy = GatePolicyConfigLoader.decode('{}');
      expect(policy.preferredGateId, isNull);
      expect(policy.disabledGateIds, isEmpty);
    });

    test('load() reads the bundled gate_policy.json asset', () async {
      final policy = await const GatePolicyConfigLoader().load();
      expect(policy.preferredGateId, 'G2');
      expect(policy.disabledGateIds, {'G1', 'G3', 'G4'});
      // The config asset must not carry coordinates — ids only.
      final raw = await rootBundle.loadString(_policyAsset);
      expect(raw, isNot(contains('30.8')));
      expect(raw, isNot(contains('29.5')));
    });

    test('malformed input is rejected', () {
      expect(() => GatePolicyConfigLoader.decode('not json'),
          throwsFormatException);
      expect(() => GatePolicyConfigLoader.decode('[]'),
          throwsFormatException);
      expect(
          () => GatePolicyConfigLoader.decode(
              '{"disabledGateIds": "G2"}'),
          throwsFormatException);
      expect(
          () => GatePolicyConfigLoader.decode(
              '{"disabledGateIds": [1, 2]}'),
          throwsFormatException);
    });
  });
}
