import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/prayer_time.dart';
import '../providers/adhanbox_provider.dart';

class PrayerTimesScreen extends ConsumerWidget {
  const PrayerTimesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerTimesAsync = ref.watch(prayerTimesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horaires de Prière'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(prayerTimesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            prayerTimesAsync.when(
              data: (times) => _buildPrayerTimesTable(context, times),
              loading: () => const _LoadingWidget(),
              error: (error, stack) => _buildErrorWidget(error),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerTimesTable(BuildContext context, PrayerTimes times) {
    final prayerList = times.times;
    final isMawaqit = times.source.toLowerCase() == 'mawaqit' ||
        prayerList.any((p) => p.mawaqitTime != null);

    if (prayerList.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Pas de prières aujourd\'hui',
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMawaqit ? 'Horaires Mawaqit' : 'Horaires Calculés',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (isMawaqit)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Source: Mawaqit',
                  style: TextStyle(fontSize: 13, color: Colors.green),
                ),
              ),
            const SizedBox(height: 16),
            ...prayerList.map<Widget>((prayer) {
              final displayedTime = prayer.mawaqitTime ?? prayer.calculatedTime;
              return _buildPrayerRow(
                prayer.name,
                displayedTime,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerRow(String name, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontSize: 16)),
          Text(time,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chargement des horaires...'),
          ],
        ),
      ),
    );
  }
}

Widget _buildErrorWidget(dynamic error) {
  return Card(
    color: Colors.red[50],
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(height: 8),
          const Text('Erreur de chargement'),
          const SizedBox(height: 4),
          Text(error.toString(), style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
