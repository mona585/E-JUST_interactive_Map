import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// CP-9 §7.4 "Indoor runtime-absence" — structural regression guard.
//
// This is a CP-9 structural check only. It is NOT the full §6.4 reachability
// proof (dependency map, call-site inspection, hit classification, reachability
// proof, regression confirmation), which is deferred to CP-10.
//
// It asserts that the Indoor routing identifiers removed during CP-7F/CP-8
// do not reappear in non-comment production code under lib/. Inert seams
// (latestIndoorEstimate, isIndoorWifiActive, resetAllRadiomaps) are deferred
// per D4 and are intentionally NOT asserted here.
// ---------------------------------------------------------------------------

String _stripComments(String src) {
  final noBlocks = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final kept = <String>[];
  for (final line in noBlocks.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    kept.add(line);
  }
  return kept.join('\n');
}

List<File> _dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return <File>[];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  group('Indoor runtime absence (CP-9 structural guard)', () {
    test('removed Indoor routing identifiers absent from production code', () {
      // Identifiers fully removed during CP-7F/CP-8 (no inert seam remains).
      const removed = <String>[
        'getRouteBetweenPois',
        '_routeViaConnectors',
        'routeViaConnectorsForTest',
        'NativePositioningService',
        'loadRadioMap',
      ];
      final files = _dartFiles('lib');
      final violations = <String>[];
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        for (final id in removed) {
          if (src.contains(id)) {
            violations.add('${f.path}: $id');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Indoor routing identifiers reintroduced: $violations');
    });

    test('inert Indoor seams remain deferred (D4) — documented, not asserted', () {
      // These identifiers intentionally remain as inert seams (D4 deferred).
      // This test documents their continued presence so a future change is
      // visible; it does NOT assert absence.
      const deferred = <String>[
        'latestIndoorEstimate',
        'isIndoorWifiActive',
        'resetAllRadiomaps',
      ];
      final files = _dartFiles('lib');
      final present = <String>[];
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        for (final id in deferred) {
          if (src.contains(id)) present.add(id);
        }
      }
      // Documented expectation: all three remain (D4 deferred).
      expect(present.toSet(), containsAll(deferred));
    });
  });
}