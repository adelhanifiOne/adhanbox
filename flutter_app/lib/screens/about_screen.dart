import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({Key? key}) : super(key: key);

  String _readString(Map<String, dynamic> status, List<String> keys, {String fallback = 'N/A'}) {
    for (final key in keys) {
      final value = status[key];
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }
    }
    return fallback;
  }

  String _readLocation(Map<String, dynamic> status) {
    final lat = _readString(status, const ['latitude', 'lat'], fallback: '');
    final lon = _readString(status, const ['longitude', 'lon'], fallback: '');
    if (lat.isEmpty || lon.isEmpty) return 'N/A';
    return '$lat, $lon';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(deviceStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('À propos'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App Header
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.mosque,
                    size: 64,
                    color: Colors.green[700],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'AdhanBox',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Horaires de Prière Intelligents',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // App Info
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Version',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('1.0.0'),
                  SizedBox(height: 20),
                  Text(
                    'Description',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'AdhanBox est une application mobile pour contrôler votre '
                    'dispositif de prière connecté. '
                    'Consultez les horaires de prière, contrôlez les LED et les paramètres '
                    'depuis votre téléphone.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Device Info
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informations du dispositif',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  statusAsync.when(
                    data: (status) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('Firmware', _readString(status, const ['firmware', 'version'])),
                        _buildInfoRow('Adresse MAC', _readString(status, const ['mac_address', 'mac'])),
                        _buildInfoRow('IP', _readString(status, const ['ip'])),
                        _buildInfoRow('Heure RTC', _readString(status, const ['rtc_time', 'rtc'])),
                        _buildInfoRow('Temps depuis démarrage', _readString(status, const ['uptime'])),
                        _buildInfoRow('Emplacement', _readLocation(status)),
                      ],
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (error, stack) => Text('Erreur: $error'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Links
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: const Text('Site Web'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      // TODO: Ouvrir le site web
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.bug_report),
                    title: const Text('Signaler un bug'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      // TODO: Ouvrir l'email
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text('Conditions d\'utilisation'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      // TODO: Afficher les conditions
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Footer
          Center(
            child: Text(
              '© 2026 AdhanBox. Tous droits réservés.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
