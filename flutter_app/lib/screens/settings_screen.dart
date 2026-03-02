import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';
import '../services/location_service.dart';
import '../services/wifi_service.dart';
import '../services/esp32_discovery_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _ipController;
  int _volume = 20;
  int _timezone = 0;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceIp = ref.watch(currentDeviceIpProvider) ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Device IP Setting
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Adresse IP du dispositif',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'IP actuelle: $deviceIp',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ipController..text = deviceIp,
                    decoration: InputDecoration(
                      hintText: 'Ex: 192.168.1.100',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () async {
                          ref.read(currentDeviceIpProvider.notifier).state =
                              _ipController.text;
                          await saveDeviceIp(ref, _ipController.text);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('IP sauvegardée'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _discoverESP32(),
                    icon: const Icon(Icons.search),
                    label: const Text('Découvrir automatiquement'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Audio Settings
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Volume Audio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.volume_off),
                      Expanded(
                        child: Slider(
                          value: _volume.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 30,
                          onChanged: (value) async {
                            setState(() => _volume = value.toInt());
                            final api = ref.read(adhanboxApiProvider);
                            if (api != null) {
                              await api.setAudioVolume(_volume);
                            }
                          },
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ],
                  ),
                  Center(
                    child: Text(
                      'Volume: $_volume',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Timezone Settings
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fuseau Horaire (UTC)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _timezone.toDouble(),
                    min: -12,
                    max: 12,
                    divisions: 24,
                    onChanged: (value) async {
                      setState(() => _timezone = value.toInt());
                      final api = ref.read(adhanboxApiProvider);
                      if (api != null) {
                        await api
                            .setTimezone(_timezone * 60); // Convertir en minutes
                      }
                    },
                  ),
                  Center(
                    child: Text(
                      'UTC ${_timezone >= 0 ? '+' : ''}$_timezone',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // WiFi Settings
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WiFi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showWiFiDialog(),
                    icon: const Icon(Icons.wifi),
                    label: const Text('Sélectionner réseau WiFi'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Location Settings
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Emplacement',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _getGPSLocation(),
                    icon: const Icon(Icons.location_on),
                    label: const Text('Utiliser ma position GPS'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Découvre automatiquement l'ESP32 sur le réseau
  Future<void> _discoverESP32() async {
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
                Text('Recherche de l\'AdhanBox...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final service = ref.read(esp32DiscoveryServiceProvider);
      
      // Essaye d'abord mDNS
      final device = await service.findAdhanBox(
        timeout: const Duration(seconds: 5),
      );

      if (device != null) {
        Navigator.pop(context); // Ferme le dialog
        
        // Met à jour l'IP
        ref.read(currentDeviceIpProvider.notifier).state = device.host;
        await saveDeviceIp(ref, device.host);
        _ipController.text = device.host;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AdhanBox trouvé: ${device.name} (${device.host})'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // Si mDNS échoue, scan le réseau
      final subnet = await service.getLocalSubnet();
      if (subnet == null) {
        Navigator.pop(context);
        _showError('Impossible de déterminer le sous-réseau local');
        return;
      }

      final hosts = await service.scanLocalNetwork(subnet: subnet);
      
      Navigator.pop(context); // Ferme le dialog

      if (hosts.isEmpty) {
        _showError('Aucun appareil trouvé sur le réseau');
        return;
      }

      // Affiche la liste des appareils trouvés
      _showDeviceListDialog(hosts);
    } catch (e) {
      Navigator.pop(context);
      _showError('Erreur lors de la découverte: $e');
    }
  }

  /// Affiche une liste de choix d'appareils
  void _showDeviceListDialog(List<String> hosts) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Appareils trouvés'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: hosts.length,
            itemBuilder: (context, index) {
              final host = hosts[index];
              return ListTile(
                leading: const Icon(Icons.devices),
                title: Text(host),
                onTap: () async {
                  ref.read(currentDeviceIpProvider.notifier).state = host;
                  await saveDeviceIp(ref, host);
                  _ipController.text = host;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('IP configurée: $host')),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  /// Affiche la liste des réseaux WiFi
  Future<void> _showWiFiDialog() async {
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

      Navigator.pop(context); // Ferme le dialog de chargement

      if (networks.isEmpty) {
        _showError('Aucun réseau WiFi trouvé');
        return;
      }

      // Affiche la liste des réseaux
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
                    _showWiFiPasswordDialog(network.ssid);
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
      Navigator.pop(context);
      _showError('Erreur lors du scan WiFi: $e');
    }
  }

  /// Affiche un dialog pour entrer le mot de passe WiFi
  void _showWiFiPasswordDialog(String ssid) {
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
                
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Configuration WiFi envoyée à l\'ESP32'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  _showError('Appareil non connecté');
                }
              } catch (e) {
                _showError('Erreur lors de la configuration WiFi: $e');
              }
            },
            child: const Text('Connecter'),
          ),
        ],
      ),
    );
  }

  /// Obtient la localisation GPS
  Future<void> _getGPSLocation() async {
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
                Text('Récupération de la position GPS...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final service = ref.read(locationServiceProvider);
      final position = await service.getCurrentLocation();

      Navigator.pop(context); // Ferme le dialog

      if (position == null) {
        _showError('Impossible de récupérer la position GPS');
        return;
      }

      // Envoie la position à l'ESP32
      try {
        final api = ref.read(adhanboxApiProvider);
        if (api != null) {
          await api.setLocation(
            position.latitude,
            position.longitude,
            position.accuracy,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Position GPS envoyée:\n${service.formatPosition(position)}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        _showError('Erreur lors de l\'envoi de la position: $e');
      }
    } catch (e) {
      Navigator.pop(context);
      _showError('Erreur GPS: $e');
    }
  }

  /// Affiche un message d'erreur
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
