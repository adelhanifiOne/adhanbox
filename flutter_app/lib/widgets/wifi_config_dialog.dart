import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/wifi_service.dart';
import '../services/connection_service.dart';
import '../providers/adhanbox_provider.dart';

/// Shows a WiFi configuration dialog that scans networks and allows connection
Future<void> showWiFiConfigDialog(BuildContext context, WidgetRef ref) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scan des réseaux WiFi...'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final service = ref.read(wifiServiceProvider);
    final networks = await service.scanNetworks();

    if (!context.mounted) return;
    Navigator.pop(context); // Ferme le dialog de chargement

    if (networks.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun réseau WiFi trouvé'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Affiche la liste des réseaux
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réseaux WiFi disponibles'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: networks.length,
            itemBuilder: (context, index) {
              final network = networks[index];
              final strength = service.signalStrengthPercent(network.level);

              return ListTile(
                leading: Icon(
                  Icons.wifi,
                  color: strength >= 75
                      ? Colors.green
                      : strength >= 50
                          ? Colors.orange
                          : Colors.red,
                ),
                title: Text(network.ssid),
                subtitle: Text('Signal: $strength%'),
                trailing: network.capabilities.contains('WPA')
                    ? const Icon(Icons.lock, size: 16)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _showWiFiPasswordDialog(context, ref, network.ssid);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur lors du scan WiFi: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

/// Shows a password dialog for connecting to a WiFi network
void _showWiFiPasswordDialog(
  BuildContext context,
  WidgetRef ref,
  String ssid,
) {
  final passwordController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Connexion à $ssid'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Mot de passe',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () async {
            final password = passwordController.text;
            Navigator.pop(context);

            // Envoie les informations WiFi à l'ESP32
            try {
              final api = ref.read(adhanboxApiProvider);
              if (api != null) {
                await api.connectWiFi(ssid, password);

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configuration WiFi envoyée à l\'ESP32'),
                    backgroundColor: Colors.green,
                  ),
                );

                // Refresh connection state after a delay
                Future.delayed(const Duration(seconds: 3), () {
                  ref.read(connectionStateProvider.notifier).checkNow();
                });
              } else {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Appareil non connecté'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erreur lors de la configuration WiFi: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: const Text('Connecter'),
        ),
      ],
    ),
  );
}
