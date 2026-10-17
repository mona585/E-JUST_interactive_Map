import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/viewmodels/map_view_model.dart';

/// Responsibility-based MVVM boundary tests (Phase 1 plan §6.3).
///
/// These are structural/headless assertions: they read the production sources
/// and encode the layer rules directly, so they run without a widget tree or
/// native renderer. Compilation alone is not evidence of MVVM compliance.
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
      .listSync(recursive: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  group('MVVM boundaries (§6.3)', () {
    test('ViewModels: no widgets, GoogleMapController, or camera calls', () {
      final forbidden = RegExp(
        r'\bGoogleMapController\b'
        r'|\banimateCamera\b'
        r'|\bmoveCamera\b'
        r'|\bStatefulWidget\b'
        r'|\bStatelessWidget\b'
        r'|\bConsumerStatefulWidget\b'
        r'|\bConsumerWidget\b'
        r'|\bWidget build\s*\(',
      );
      final files = _dartFiles('lib/viewmodels');
      expect(files, isNotEmpty, reason: 'no viewmodel sources found');
      for (final f in files) {
        final code = _stripComments(f.readAsStringSync());
        final m = forbidden.firstMatch(code);
        expect(m, isNull, reason: '${f.path} references ${m?.group(0)}');
      }
    });

    test('Models/domain: no Flutter presentation imports', () {
      final files = _dartFiles('lib/models');
      expect(files, isNotEmpty, reason: 'no model sources found');
      for (final f in files) {
        final code = _stripComments(f.readAsStringSync());
        expect(code.contains('package:flutter/material.dart'), isFalse,
            reason: '${f.path} imports material');
        expect(code.contains('package:flutter/widgets.dart'), isFalse,
            reason: '${f.path} imports widgets');
      }
    });

    test('Services: no Flutter material dependency', () {
      final files = _dartFiles('lib/services');
      expect(files, isNotEmpty, reason: 'no service sources found');
      for (final f in files) {
        final code = _stripComments(f.readAsStringSync());
        expect(code.contains('package:flutter/material.dart'), isFalse,
            reason: '${f.path} imports material');
      }
    });

    test('View: only writes allow-listed controller-boundary providers', () {
      const allowed = <String>{
        'routeBoundsFitterProvider',
        'mapFocusRequesterProvider',
      };
      final code =
          _stripComments(File('lib/views/map_screen.dart').readAsStringSync());
      final writes =
          RegExp(r'ref\.read\((\w+)\.notifier\)\.state\s*=').allMatches(code);
      for (final w in writes) {
        final provider = w.group(1)!;
        expect(allowed.contains(provider), isTrue,
            reason: 'View writes business provider "$provider"; '
                'business-state mutation must live in a ViewModel/service');
      }
    });

    test('MapViewModel connector predicate is a pure, headless decision', () {
      expect(MapViewModel.isConnectorPoi('None', 'anything'), isTrue);
      expect(MapViewModel.isConnectorPoi('elevator', 'Lift A'), isTrue);
      expect(MapViewModel.isConnectorPoi('STAIRS', 'Stair 1'), isTrue);
      expect(MapViewModel.isConnectorPoi('StairCase', 'x'), isTrue);
      expect(MapViewModel.isConnectorPoi('Room', 'Lecture Hall'), isFalse);
      expect(MapViewModel.isConnectorPoi('POI', 'Cafeteria'), isFalse);
    });
  });
}
