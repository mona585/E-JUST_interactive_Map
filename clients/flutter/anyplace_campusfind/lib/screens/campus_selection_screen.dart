import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/campus.dart';
import '../providers/campus_provider.dart';
import '../providers/providers.dart';

/// First-launch campus picker. Persists the selection via CacheService and
/// exposes it on [onSelected].
class CampusSelectionScreen extends ConsumerStatefulWidget {
  const CampusSelectionScreen({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  ConsumerState<CampusSelectionScreen> createState() =>
      _CampusSelectionScreenState();
}

class _CampusSelectionScreenState extends ConsumerState<CampusSelectionScreen> {
  bool _saving = false;

  Future<void> _select(Campus campus) async {
    setState(() => _saving = true);
    await ref
        .read(cacheServiceProvider)
        .setSelectedCampusId(campus.cuid);
    ref.read(selectedCampusIdProvider.notifier).state = campus.cuid;
    widget.onSelected(campus.cuid);
  }

  @override
  Widget build(BuildContext context) {
    final campusesAsync = ref.watch(configuredCampusesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to CampusFind')),
      body: campusesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                const Text('Could not load campuses'),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(configuredCampusesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (campuses) {
          if (campuses.isEmpty) {
            return _emptyState(context);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Choose your campus',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final campus in campuses)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.school),
                    title: Text(campus.name),
                    subtitle: Text(
                      '${campus.spaces.length} buildings',
                    ),
                    trailing: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _saving ? null : () => _select(campus),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 48),
            const SizedBox(height: 16),
            const Text('No campuses configured'),
            const SizedBox(height: 8),
            Text(
              'Build with --dart-define=CAMPUS_IDS='
              '${AppConstants.configuredCampusIds.isEmpty ? '<cuid>,' : ''}'
              '... to add campuses.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
