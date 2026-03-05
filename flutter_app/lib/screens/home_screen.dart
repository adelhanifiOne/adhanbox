import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/prayer_time.dart';
import '../services/connection_service.dart';
import '../services/adhanbox_api.dart';
import '../providers/adhanbox_provider.dart';
import '../widgets/wifi_config_dialog.dart';
import 'device_setup_screen.dart';
import 'calculation_setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoConnectAsync = ref.watch(autoReconnectProvider);

    return autoConnectAsync.when(
      data: (deviceIp) {
        if (deviceIp == null) {
          return _buildNoDeviceScreen(context, ref);
        } else {
          return _buildNormalHomeScreen(context, ref);
        }
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('AdhanBox')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, __) {
        print('Erreur de connexion: $error');
        return _buildConnectionErrorScreen(context, ref);
      },
    );
  }

  /// Écran en cas d'erreur de connexion
  Widget _buildConnectionErrorScreen(BuildContext context, WidgetRef ref) {
    final ipController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AdhanBox'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off,
                size: 80,
                color: Colors.red[300],
              ),
              const SizedBox(height: 24),
              Text(
                'Erreur de connexion',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Impossible de se connecter à l\'AdhanBox.\nSi l\'appareil est connecté au WiFi, essayez d\'entrer son IP manuellement.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: ipController,
                decoration: InputDecoration(
                  hintText: '172.20.10.4',
                  labelText: 'Adresse IP de l\'AdhanBox',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.router),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  final ip = ipController.text.trim();
                  if (ip.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Veuillez entrer une IP')),
                    );
                    return;
                  }

                  // Tenter la connexion
                  final api = AdhanBoxAPI(baseUrl: 'http://$ip');
                  try {
                    print('DEBUG: Test connexion à $ip...');
                    await api.getStatus().timeout(const Duration(seconds: 5));
                    // Connexion réussie, sauvegarder l'IP
                    print('DEBUG: Connexion réussie!');
                    await saveDeviceIp(ref, ip);
                    ref.invalidate(autoReconnectProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Connecté! Actualisation...'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('DEBUG: Erreur de connexion: $e');
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Erreur de connexion'),
                          content: SingleChildScrollView(
                            child: Text(
                              'Impossible de se connecter à http://$ip\n\nDétails:\n$e',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.connect_without_contact, size: 28),
                label: const Text(
                  'Connecter',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  ref.invalidate(autoReconnectProvider);
                },
                icon: const Icon(Icons.refresh, size: 28),
                label: const Text(
                  'Réessayer la détection',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeviceSetupScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('Configuration avancée'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoDeviceScreen(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AdhanBox'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.devices_outlined,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'Aucun appareil configuré',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Configurez votre AdhanBox pour commencer',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeviceSetupScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add_box_outlined, size: 28),
                label: const Text(
                  'Configurer un appareil',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  // Afficher les instructions
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Configuration AdhanBox'),
                      content: const SingleChildScrollView(
                        child: Text(
                          '1. Allumez votre ESP32 AdhanBox\n\n'
                          '2. L\'ESP32 créera un réseau WiFi "AdhanBox"\n\n'
                          '3. Cliquez sur "Configurer un appareil"\n\n'
                          '4. Suivez l\'assistant de configuration\n\n'
                          '5. Connectez l\'ESP32 à votre WiFi maison',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Compris'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.help_outline),
                label: const Text('Comment configurer ?'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalHomeScreen(BuildContext context, WidgetRef ref) {
    final prayerTimesAsync = ref.watch(adjustedPrayerTimesProvider);
    final connectionState = ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AdhanBox'),
        elevation: 0,
        actions: [
          // Bouton pour ajouter/reconfigurer un appareil
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Configurer un appareil',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeviceSetupScreen(),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child:
                _buildConnectionIndicator(context, connectionState, ref),
          ),
        ],
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
            // WiFi Disconnected Warning (if applicable)
            if (connectionState.status == ConnectionStatus.disconnected ||
                connectionState.status == ConnectionStatus.error)
              _buildWiFiDisconnectedCard(context, ref),
            if (connectionState.status == ConnectionStatus.disconnected ||
                connectionState.status == ConnectionStatus.error)
              const SizedBox(height: 16),
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
      floatingActionButton: connectionState.status == ConnectionStatus.disconnected ||
              connectionState.status == ConnectionStatus.error
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeviceSetupScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings_input_antenna),
              label: const Text('Configurer'),
              backgroundColor: Colors.orange[700],
            )
          : null,
    );
  }

  Widget _buildStatusCard(BuildContext context, Map<String, dynamic> status) {
    final wifiRaw = status['wifi'];
    final locationRaw = status['location'];
    final wifi = wifiRaw is Map ? Map<String, dynamic>.from(wifiRaw) : <String, dynamic>{};
    final location = locationRaw is Map ? Map<String, dynamic>.from(locationRaw) : <String, dynamic>{};

    final connected = wifi['connected'] == true || wifiRaw?.toString().toLowerCase() == 'connected';
    final ssid = wifi['ssid']?.toString() ?? 'N/A';
    final ip = wifi['ip']?.toString() ?? (status['ip']?.toString() ?? 'N/A');
    final signal = wifi['signal']?.toString() ?? 'N/A';
    final latVal = location['lat'];
    final lonVal = location['lon'];
    final lat = latVal is num ? latVal.toStringAsFixed(3) : (status['lat']?.toString() ?? 'N/A');
    final lon = lonVal is num ? lonVal.toStringAsFixed(3) : (status['lon']?.toString() ?? 'N/A');
    final rtcOk = status['rtc_ok'] == true || status['rtc_ok'] == 1;
    final timestamp = status['timestamp']?.toString() ?? status['rtc']?.toString() ?? '0';
    final wifiText = connected ? '$ssid ($ip, $signal dBm)' : (wifiRaw?.toString() ?? 'Deconnecte');
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

    if (times.isEmpty) {
      return const SizedBox();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Horaires d\'aujourd\'hui',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CalculationSetupScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.tune,
                          size: 18,
                          color: Color(0xFF1B5E20),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Ajuster',
                          style: TextStyle(
                            color: Color(0xFF1B5E20),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...times.map<Widget>((prayer) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      prayer.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      prayer.calculatedTime,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF1B5E20),
                      ),
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
      final minutes = _timeToMinutes(prayer.calculatedTime);
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
          // If disconnected, show options menu
          if (connectionState.status == ConnectionStatus.disconnected ||
              connectionState.status == ConnectionStatus.error) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('ESP32 Déconnecté'),
                content: const Text(
                  'L\'ESP32 n\'est pas accessible. Voulez-vous configurer sa connexion WiFi ?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ref.read(connectionStateProvider.notifier).checkNow();
                    },
                    child: const Text('Réessayer'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showWiFiConfigDialog(context, ref);
                    },
                    child: const Text('Configurer WiFi'),
                  ),
                ],
              ),
            );
          } else {
            // If connected, just refresh
            ref.read(connectionStateProvider.notifier).checkNow();
          }
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

  Widget _buildWiFiDisconnectedCard(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 6,
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.orange[700], size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ESP32 Déconnecté',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'L\'appareil n\'est pas accessible sur le réseau WiFi',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(connectionStateProvider.notifier).checkNow();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange[700],
                      side: BorderSide(color: Colors.orange[700]!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showWiFiConfigDialog(context, ref);
                    },
                    icon: const Icon(Icons.wifi),
                    label: const Text('Configurer WiFi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
