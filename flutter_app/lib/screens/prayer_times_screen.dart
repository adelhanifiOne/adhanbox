import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/prayer_time.dart';
import '../providers/adhanbox_provider.dart';
import 'calculation_setup_screen.dart';

class PrayerTimesScreen extends ConsumerWidget {
  const PrayerTimesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerTimesAsync = ref.watch(adjustedPrayerTimesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horaires de Prière'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(prayerTimesProvider);
          ref.invalidate(prayerOffsetsProvider);
          ref.invalidate(adjustedPrayerTimesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            prayerTimesAsync.when(
              data: (times) => _buildPrayerTimesTable(context, times),
              loading: () => const _LoadingWidget(),
              error: (error, stack) => _buildErrorWidget(error),
            ),
            const SizedBox(height: 24),
            _buildConfigButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerTimesTable(BuildContext context, PrayerTimes times) {
    final prayerList = times.times;

    if (prayerList.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Pas de prières aujourd\'hui',
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Horaires Calculés',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1B5E20),
              ),
            ),
            const SizedBox(height: 20),
            ...prayerList.map<Widget>((prayer) {
              return _buildPrayerRow(
                prayer.name,
                prayer.calculatedTime,
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

  Widget _buildConfigButton(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CalculationSetupScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tune,
                  size: 32,
                  color: Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configurer les horaires',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Méthode de calcul et ajustements fins',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
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
