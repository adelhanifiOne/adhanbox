import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/prayer_time.dart';
import '../services/connection_service.dart';
import '../providers/adhanbox_provider.dart';
import 'device_setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceIpAsync = ref.watch(deviceIpProvider);

    return deviceIpAsync.when(
      data: (deviceIp) {
        // Initialiser currentDeviceIpProvider
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(currentDeviceIpProvider.notifier).state = deviceIp;
        });
        
        if (deviceIp == null) {
          return _buildNoDeviceScreen(context);
        } else {
          return _buildNormalHomeScreen(context, ref);
        }
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('AdhanBox')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _buildNoDeviceScreen(context),
    );
  }

  Widget _buildNoDeviceScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AdhanBox'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.devices_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Aucun appareil configuré',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cliquez sur le bouton ci-dessous pour\najouter votre AdhanBox',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeviceSetupScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Ajouter un appareil'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalHomeScreen(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(deviceStatusProvider);
    final prayerTimesAsync = ref.watch(prayerTimesProvider);
    final connectionState = ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AdhanBox'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child:
                _buildConnectionIndicator(context, connectionState, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(deviceStatusProvider);
          ref.invalidate(prayerTimesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status Card
            statusAsync.when(
              data: (status) => _buildStatusCard(context, status),
              loading: () => const _LoadingCard(),
              error: (error, stack) =>
                  _buildErrorCard('Erreur de status', error),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeviceSetupScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Ajouter un appareil'),
            ),
            const SizedBox(height: 20),
            // Next Prayer Card
            prayerTimesAsync.when(
              data: (prayerTimes) =>
                  _buildNextPrayerCard(context, prayerTimes),
              loading: () => const _LoadingCard(),
              error: (error, stack) =>
                  _buildErrorCard('Erreur prières', error),
            ),
            const SizedBox(height: 20),
            // Today's Prayers Preview
            prayerTimesAsync.when(
              data: (prayerTimes) =>
                  _buildTodayPrayersPreview(context, prayerTimes),
              loading: () => const _LoadingCard(),
              error: (error, stack) =>
                  _buildErrorCard('Erreur horaires', error),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, Map<String, dynamic> status) {
    final wifi = status['wifi'] as Map<String, dynamic>? ?? {};
    final location = status['location'] as Map<String, dynamic>? ?? {};
    final connected = wifi['connected'] == true;
    final ssid = wifi['ssid']?.toString() ?? 'N/A';
    final ip = wifi['ip']?.toString() ?? 'N/A';
    final signal = wifi['signal']?.toString() ?? 'N/A';
    final lat = location['lat']?.toStringAsFixed(3) ?? 'N/A';
    final lon = location['lon']?.toStringAsFixed(3) ?? 'N/A';
    final rtcOk = status['rtc_ok'] == true;
    final timestamp = status['timestamp']?.toString() ?? '0';
    final wifiText = connected ? '$ssid ($ip, $signal dBm)' : 'Deconnecte';
    final rtcText = rtcOk ? 'OK (ts: $timestamp)' : 'Non disponible';

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'État du système',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatusRow('WiFi', wifiText),
            _buildStatusRow('RTC', rtcText),
            _buildStatusRow('Emplacement', '$lat, $lon'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildNextPrayerCard(BuildContext context, PrayerTimes prayerTimes) {
    final next = _findNextPrayer(prayerTimes);

    if (next == null) {
      return Card(
        elevation: 4,
        color: Colors.amber[50],
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Pas de prière aujourd\'hui'),
        ),
      );
    }

    return Card(
      elevation: 4,
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Prochaine prière',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              next['name'] as String,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Dans ${next['minutesLeft']} minutes',
              style: const TextStyle(fontSize: 16, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayPrayersPreview(
      BuildContext context, PrayerTimes prayerTimes) {
    final times = prayerTimes.times;
    final hasMawaqit = times.any((p) => p.mawaqitTime != null);

    if (times.isEmpty) {
      return const SizedBox();
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Horaires d\'aujourd\'hui',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (hasMawaqit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Mawaqit ✓',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...times.map<Widget>((prayer) {
              final displayTime = prayer.mawaqitTime ?? prayer.calculatedTime;
              final isMawaqit = prayer.mawaqitTime != null;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(prayer.name),
                    Row(
                      children: [
                        Text(
                          displayTime,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isMawaqit ? Colors.green : Colors.black,
                          ),
                        ),
                        if (isMawaqit)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              '✓',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _findNextPrayer(PrayerTimes prayerTimes) {
    if (prayerTimes.times.isEmpty) return null;

    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    int? firstTime;
    PrayerTime? firstPrayer;

    for (final prayer in prayerTimes.times) {
      final timeToUse = prayer.mawaqitTime ?? prayer.calculatedTime;
      final minutes = _timeToMinutes(timeToUse);
      if (minutes == null) continue;

      firstTime ??= minutes;
      firstPrayer ??= prayer;

      if (minutes > nowMinutes) {
        return {
          'name': prayer.name,
          'minutesLeft': minutes - nowMinutes,
        };
      }
    }

    if (firstTime == null || firstPrayer == null) return null;

    return {
      'name': firstPrayer.name,
      'minutesLeft': (24 * 60 - nowMinutes) + firstTime,
    };
  }

  int? _timeToMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  Widget _buildConnectionIndicator(
    BuildContext context,
    ESP32ConnectionState connectionState,
    WidgetRef ref,
  ) {
    late Color statusColor;
    late IconData statusIcon;
    late String statusText;

    switch (connectionState.status) {
      case ConnectionStatus.connected:
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        statusText = 'ESP32 Connecté';
        break;
      case ConnectionStatus.disconnected:
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_off;
        statusText = 'Déconnecté';
        break;
      case ConnectionStatus.checking:
        statusColor = Colors.blue;
        statusIcon = Icons.wifi_find;
        statusText = 'Vérification...';
        break;
      case ConnectionStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error_outline;
        statusText = 'Erreur';
        break;
    }

    return Tooltip(
      message: connectionState.message ?? statusText,
      child: InkWell(
        onTap: () {
          ref.read(connectionStateProvider.notifier).checkNow();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 6),
              if (!connectionState.isChecking)
                Text(
                  connectionState.isConnected ? '✓' : '✗',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chargement...'),
          ],
        ),
      ),
    );
  }
}

Widget _buildErrorCard(String title, dynamic error) {
  return Card(
    elevation: 4,
    color: Colors.red[50],
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(error.toString(), style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
