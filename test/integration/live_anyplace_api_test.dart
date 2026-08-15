// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';

void main() {
  group('Live Anyplace Backend Integration Test', () {
    late AnyplaceApiClient apiClient;
    late AnyplaceSpaceRepository repository;

    setUp(() {
      // In live testing environments, create an HttpClient that allows self-signed/trusted SSL
      final httpClient = HttpClient()
        ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
      final ioClient = IOClient(httpClient);

      apiClient = AnyplaceApiClient(client: ioClient, baseUrl: ApiConfig.baseUrl);
      repository = AnyplaceSpaceRepository(apiClient: apiClient);
    });

    test('fetches live buildings from Anyplace backend successfully', () async {
      final spaces = await repository.getPublicSpaces(forceReload: true);

      expect(spaces, isNotEmpty);
      print('Live test: Successfully retrieved ${spaces.length} spaces from ${ApiConfig.baseUrl}');

      for (int i = 0; i < (spaces.length > 5 ? 5 : spaces.length); i++) {
        final space = spaces[i];
        print('  - Space #${i + 1}: ${space.name} [buid: ${space.buid}] at (${space.latitude}, ${space.longitude})');
        expect(space.buid, isNotEmpty);
        expect(space.name, isNotEmpty);
        expect(space.latitude, isNot(0.0));
        expect(space.longitude, isNot(0.0));
      }
    });

    test('fetches details for a live space by buid', () async {
      final spaces = await repository.getPublicSpaces();
      expect(spaces, isNotEmpty);

      final firstSpace = spaces.first;
      final fetchedSpace = await repository.getSpaceByBuid(firstSpace.buid);

      expect(fetchedSpace, isNotNull);
      expect(fetchedSpace!.buid, firstSpace.buid);
      expect(fetchedSpace.name, firstSpace.name);
      print('Live test: Successfully verified space details for buid: ${fetchedSpace.buid} (${fetchedSpace.name})');
    });

    test('fetches floors for a live space from Anyplace backend', () async {
      final spaces = await repository.getPublicSpaces();
      expect(spaces, isNotEmpty);

      // Find a building that has floors
      for (final space in spaces.take(20)) {
        final floors = await repository.getFloorsByBuid(space.buid);
        if (floors.isNotEmpty) {
          print('Live test: Found ${floors.length} floors for building ${space.name} (${space.buid})');
          for (final floor in floors) {
            print('  - Floor: ${floor.displayName} [floor_number: ${floor.floorNumber}, fuid: ${floor.fuid}]');
            expect(floor.buid, space.buid);
            expect(floor.floorNumber, isNotEmpty);
          }
          break;
        }
      }
    });
  });
}
