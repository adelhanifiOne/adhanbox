import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:app_settings/app_settings.dart';
import '../providers/adhanbox_provider.dart';
import '../services/adhanbox_api.dart';
import '../services/esp32_discovery_service.dart';
import 'calculation_setup_screen.dart';

class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen> {
  // États du processus de configuration
  int _step = 1;
  String? _error;

  // Étape 1: Scan des réseaux WiFi disponibles (ceux émis par les ESP32)
  List<Map<String, dynamic>> _adhanboxNetworks = [];
  bool _isScanningAdhanboxWifi = false;
  String? _selectedAdhanboxWifi;

  // Étape 2: Connexion automatique au WiFi AdhanBox
  bool _isConnectingToAdhanbox = false;

  // Étape 3: Récupération des réseaux WiFi visibles par l'ESP32
  List<Map<String, dynamic>> _homeWifiNetworks = [];
  bool _isScanningHomeWifi = false;
  String? _selectedHomeWifi;
  bool _isSendingCredentials = false;

  // Étape 4: Recherche de l'ESP32 sur le réseau maison
  bool _isSearchingOnHomeNetwork = false;
  String? _deviceIp;
  String _networkScanProgress = '';
  bool _step4ReadyToSearch = false;
  final TextEditingController _manualIpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanForAdhanBoxNetworks();
  }

  /// Ouvre les paramètres WiFi du système
  Future<void> _openWiFiSettings() async {
    try {
      // app_settings ouvre directement les paramètres WiFi
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Paramètres WiFi ouverts - Revenez après connexion'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Fallback: ouvre les paramètres généraux
      try {
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ouvrez WiFi dans les paramètres'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: Ouvrez WiFi manuellement dans Paramètres'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// ========== ÉTAPE 1: Scanner les réseaux WiFi Adhanbox ==========

  Future<void> _scanForAdhanBoxNetworks() async {
    setState(() {
      _isScanningAdhanboxWifi = true;
      _error = null;
    });

    try {
      // Sur Flutter Web, wifi_scan n'est pas disponible
      // On passe donc en mode manuel (pas de simulation)
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 400));
        setState(() {
          _adhanboxNetworks = [];
          _error = null;
        });
      } else {
        final locationServiceEnabled =
            await Geolocator.isLocationServiceEnabled();
        if (!locationServiceEnabled) {
          setState(() {
            _error =
                'La localisation du téléphone est désactivée. Activez le GPS puis relancez le scan.';
          });
          return;
        }

        final locationPermission = await Permission.locationWhenInUse.request();
        if (!locationPermission.isGranted) {
          setState(() {
            _error =
                'Permission localisation refusée. Autorisez-la pour détecter les réseaux WiFi.';
          });
          return;
        }

        // Sur Android/iOS, utiliser wifi_scan réel
        final canScan = await WiFiScan.instance.canStartScan();

        if (canScan != CanStartScan.yes) {
          setState(() {
            _error =
                'Scan WiFi indisponible ($canScan). Vérifiez WiFi, GPS et permissions.';
          });
          setState(() => _isScanningAdhanboxWifi = false);
          return;
        }

        // Démarrer le scan WiFi réel
        await WiFiScan.instance.startScan();

        await Future.delayed(const Duration(seconds: 2));

        final canGetResults = await WiFiScan.instance.canGetScannedResults();
        if (canGetResults != CanGetScannedResults.yes) {
          setState(() {
            _error =
                'Impossible de lire les résultats du scan ($canGetResults). Vérifiez permissions et GPS.';
          });
          return;
        }

        // Récupérer les résultats du scan
        final results = await WiFiScan.instance.getScannedResults();

        // Filtrer les réseaux AdhanBox (tolérant: adhanbox / adhan-box / adhan)
        final adhanboxNetworks = results
            .where((network) {
              final ssid = network.ssid.toLowerCase();
              return ssid.contains('adhanbox') ||
                  ssid.contains('adhan-box') ||
                  ssid.contains('adhan');
            })
            .map((network) => {
                  'ssid': network.ssid,
                  'rssi': network.level,
                  'security': network.capabilities.toLowerCase().contains('wpa')
                      ? 'WPA2'
                      : (network.capabilities.toLowerCase().contains('wep')
                          ? 'WEP'
                          : 'Open'),
                })
            .toList();

        setState(() {
          _adhanboxNetworks = adhanboxNetworks;
        });

        if (_adhanboxNetworks.isEmpty) {
          setState(() {
            _error =
                'Aucun AdhanBox détecté. Vérifiez que l\'ESP32 émet bien un SSID visible (ex: AdhanBox_xxxx), en 2.4 GHz, et reste proche du téléphone.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur lors du scan WiFi: $e';
      });
    } finally {
      setState(() {
        _isScanningAdhanboxWifi = false;
      });
    }
  }

  /// ========== ÉTAPE 2: Connexion automatique au WiFi AdhanBox ==========

  Future<void> _connectToAdhanBoxWifi() async {
    if (_selectedAdhanboxWifi == null) return;

    setState(() {
      _isConnectingToAdhanbox = true;
      _error = null;
    });

    try {
      // Vérifier la connexion à l'ESP32 avec plusieurs tentatives
      const maxAttempts = 5;
      bool connected = false;
      Exception? lastError;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          setState(() {
            _error = 'Vérification de la connexion... ($attempt/$maxAttempts)';
          });

          final api = AdhanBoxAPI(
            baseUrl: 'http://192.168.4.1',
            timeout: const Duration(seconds: 8),
          );

          final status = await api.getStatus();
          // Vérifier que le JSON contient des clés attendues (wifi, rtc_ok, etc.)
          if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
            // Connexion réussie! Passer à l'étape suivante
            setState(() {
              _step = 3;
              _isConnectingToAdhanbox = false;
              _error = null;
            });

            // Demander à l'ESP32 de scanner les réseaux WiFi disponibles
            await _getHomeWifiNetworksFromESP32();
            connected = true;
            break;
          } else {
            throw Exception('Réponse JSON invalide');
          }
        } catch (e) {
          lastError = e as Exception;
          if (attempt < maxAttempts) {
            await Future.delayed(const Duration(seconds: 3));
          }
        }
      }

      if (!connected) {
        setState(() {
          _error =
              '❌ Impossible de contacter l\'ESP32\n\n'
              'Vérifiez que:\n'
              '• Vous êtes connecté au WiFi "$_selectedAdhanboxWifi"\n'
              '• L\'ESP32 est allumé\n'
              '• Vous êtes près de l\'ESP32\n\n'
              'Puis réessayez.';
          _isConnectingToAdhanbox = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '❌ Erreur: $e';
        _isConnectingToAdhanbox = false;
      });
    }
  }

  /// ========== ÉTAPE 3: Récupérer les réseaux WiFi visibles par l'ESP32 ==========

  Future<void> _getHomeWifiNetworksFromESP32() async {
    setState(() {
      _isScanningHomeWifi = true;
      _error = null;
    });

    try {
      final api = AdhanBoxAPI(
        baseUrl: 'http://192.168.4.1',
        timeout: const Duration(seconds: 10),
      );

      // L'ESP32 doit avoir un endpoint pour scanner les réseaux WiFi
      // TODO: Implémenter GET /api/wifi/scan dans le firmware ESP32
      final response = await api.scanWifiNetworks();

      setState(() {
        _homeWifiNetworks = (response['networks'] as List<dynamic>? ?? [])
            .map((n) => {
                  'ssid': n['ssid'],
                  'rssi': n['rssi'],
                  'security': n['security'],
                })
            .toList();
        _isScanningHomeWifi = false;
      });

      if (_homeWifiNetworks.isEmpty) {
        setState(() {
          _error = 'Aucun réseau WiFi détecté par l\'AdhanBox.';
        });
      }
    } catch (e) {
      // Si l'ESP32 n'est pas encore configuré, scanner directement les réseaux disponibles avec le téléphone
      try {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));

        final results = await WiFiScan.instance.getScannedResults();

        // Récupérer tous les réseaux WiFi réels visibles par le téléphone
        final realNetworks = results
            .where((network) => network.ssid.isNotEmpty)
            .map((network) => {
                  'ssid': network.ssid,
                  'rssi': network.level,
                  'security': network.capabilities.toLowerCase().contains('wpa')
                      ? 'WPA2'
                      : (network.capabilities.toLowerCase().contains('wep')
                          ? 'WEP'
                          : 'Open'),
                })
            .toList();

        setState(() {
          _homeWifiNetworks = realNetworks;
          _isScanningHomeWifi = false;
        });

        if (_homeWifiNetworks.isEmpty) {
          setState(() {
            _error = 'Aucun réseau WiFi détecté.';
          });
        }
      } catch (scanError) {
        setState(() {
          _error = 'Erreur lors du scan WiFi local: $scanError';
          _isScanningHomeWifi = false;
        });
      }
    }
  }

  /// Envoyer les credentials WiFi maison à l'ESP32
  Future<void> _sendWifiCredentialsToESP32(String password) async {
    if (_selectedHomeWifi == null) return;

    setState(() {
      _isSendingCredentials = true;
      _error = null;
    });

    try {
      final api = AdhanBoxAPI(
        baseUrl: 'http://192.168.4.1',
        timeout: const Duration(seconds: 10),
      );

      // Envoyer les credentials à l'ESP32
      await api.connectWiFi(_selectedHomeWifi!, password);

      // Attendre que l'ESP32 se connecte (environ 10 secondes)
      await Future.delayed(const Duration(seconds: 10));

      setState(() {
        _step = 4;
        _step4ReadyToSearch = false;
        _isSendingCredentials = false;
      });

      // NE PAS lancer la recherche automatiquement - attendre que l'utilisateur
      // se reconnecte au WiFi maison et clique sur "Continuer"
    } catch (e) {
      setState(() {
        _error = 'Erreur lors de l\'envoi des credentials: $e\n'
            'Vérifiez le mot de passe WiFi.';
        _isSendingCredentials = false;
      });
    }
  }

  /// ========== ÉTAPE 4: Retrouver l'ESP32 sur le réseau maison ==========

  /// Récupérer l'IP locale du téléphone
  Future<String?> _getLocalIp() async {
    if (kIsWeb) return null;

    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          // Chercher une IPv4 du réseau local (192.168.x.x, 10.x.x.x, ou 172.16.x.x-172.31.x.x)
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
              return ip;
            }
            // Vérifier aussi les adresses 172.16.x.x à 172.31.x.x
            if (ip.startsWith('172.')) {
              final secondOctet = int.tryParse(ip.split('.')[1]) ?? 0;
              if (secondOctet >= 16 && secondOctet <= 31) {
                return ip;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération de l\'IP locale: $e');
    }
    return null;
  }

  /// Scanner le réseau local pour trouver l'AdhanBox
  Future<String?> _scanNetworkForAdhanBox() async {
    final localIp = await _getLocalIp();
    if (localIp == null) {
      setState(() {
        _networkScanProgress = 'Impossible de déterminer l\'IP locale';
      });
      return null;
    }

    // Extraire le préfixe du réseau (ex: "192.168.1" de "192.168.1.45")
    final parts = localIp.split('.');
    if (parts.length != 4) return null;

    final networkPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    debugPrint('Scan du réseau: $networkPrefix.0/24');

    setState(() {
      _networkScanProgress = 'Scan de $networkPrefix.0/24';
    });

    // Liste des IPs à tester (1-254, en excluant l'IP du téléphone)
    final hostNumber = int.tryParse(parts[3]) ?? 0;
    final ipsToTest = <String>[];

    for (int i = 1; i <= 254; i++) {
      if (i != hostNumber) {
        ipsToTest.add('$networkPrefix.$i');
      }
    }

    // Tester les IPs par lots de 15 en parallèle avec timeout de 5 secondes
    const batchSize = 15;
    int tested = 0;

    for (int i = 0; i < ipsToTest.length; i += batchSize) {
      final batch = ipsToTest.sublist(
        i,
        (i + batchSize < ipsToTest.length) ? i + batchSize : ipsToTest.length,
      );

      // Tester ce lot en parallèle
      final results = await Future.wait(
        batch.map((ip) => _testIpForAdhanBox(ip)),
      );

      // Vérifier si on a trouvé l'AdhanBox
      for (int j = 0; j < results.length; j++) {
        if (results[j]) {
          return batch[j];
        }
      }

      tested += batch.length;
      setState(() {
        _networkScanProgress = 'Testé $tested/${ipsToTest.length} adresses...';
      });
    }

    return null;
  }

  /// Tester si une IP correspond à l'AdhanBox
  Future<bool> _testIpForAdhanBox(String ip) async {
    try {
      final api = AdhanBoxAPI(
        baseUrl: 'http://$ip',
        timeout: const Duration(seconds: 5),
      );

      final status = await api.getStatus();

      // Vérifier si c'est bien un AdhanBox (vérifier les champs qui existent)
      if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
        debugPrint('AdhanBox trouvée à $ip');
        return true;
      }
    } catch (e) {
      // IP ne répond pas ou n'est pas un AdhanBox
    }
    return false;
  }

  Future<void> _findESP32OnHomeNetwork() async {
    setState(() {
      _isSearchingOnHomeNetwork = true;
      _error = null;
      _networkScanProgress = 'Recherche de l\'AdhanBox sur le réseau...';
    });

    try {
      // Essayer de scanner le réseau pour trouver une IP réelle (pas mDNS)
      const maxAttempts = 3;
      bool connected = false;
      Exception? lastError;
      String? foundIp;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          setState(() {
            _networkScanProgress = 'Tentative $attempt/$maxAttempts...';
          });

          // Utiliser le discovery service pour trouver l'ESP32
          final discovery = ESP32DiscoveryService();
          final device = await discovery.findAdhanBox(timeout: const Duration(seconds: 5)).timeout(
            const Duration(seconds: 6),
            onTimeout: () => null,
          );

          if (device != null) {
            // Tester la connexion avec l'IP trouvée
            final api = AdhanBoxAPI(
              baseUrl: 'http://${device.host}',
              timeout: const Duration(seconds: 5),
            );

            final status = await api.getStatus();

            if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
              foundIp = device.host;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('deviceIp', foundIp!);
              ref.read(currentDeviceIpProvider.notifier).state = foundIp;
              ref.invalidate(deviceIpProvider);

              // Envoyer automatiquement la position GPS à l'ESP
              try {
                print('DEBUG: Envoi automatique de la position GPS...');
                final position = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high,
                  timeLimit: const Duration(seconds: 10),
                );
                await api.setLocation(
                  position.latitude,
                  position.longitude,
                  position.accuracy,
                );
                print('DEBUG: ✓ Position GPS envoyée: ${position.latitude}, ${position.longitude}');
              } catch (e) {
                print('DEBUG: ✗ Échec envoi GPS automatique: $e (peut être configuré manuellement plus tard)');
              }

              // Synchroniser l'heure du RTC avec le smartphone
              try {
                print('DEBUG: Synchronisation de l\'heure RTC...');
                await api.setRtcTime(DateTime.now());
                print('DEBUG: ✓ Heure RTC synchronisée');
              } catch (e) {
                print('DEBUG: ✗ Échec sync RTC: $e');
              }

              setState(() {
                _deviceIp = foundIp;
                _step = 5; // Configuration finale
                _isSearchingOnHomeNetwork = false;
                _networkScanProgress = '';
              });
              connected = true;
              break;
            }
          }
        } catch (e) {
          lastError = e as Exception;
          print('DEBUG: Tentative $attempt échouée: $e');
          if (attempt < maxAttempts) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (!connected) {
        setState(() {
          _error = 'Impossible de trouver l\'AdhanBox sur le réseau après $maxAttempts tentatives.\n\n'
              'Assurez-vous que:\n'
              '1. L\'ESP32 est connecté au WiFi\n'
              '2. Le téléphone est sur le même réseau\n'
              '3. L\'adresse IP est dans la plage 172.20.x.x ou 192.168.x.x\n\n'
              'Vous pouvez aussi entrer l\'IP manuellement.';
          _isSearchingOnHomeNetwork = false;
          _networkScanProgress = '';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur: $e\n'
            'Vous pouvez entrer l\'IP manuellement.';
        _isSearchingOnHomeNetwork = false;
        _networkScanProgress = '';
      });
    }
  }

  /// Tester manuellement une IP fournie par l'utilisateur
  Future<void> _testManualIp(String ip) async {
    setState(() {
      _isSearchingOnHomeNetwork = true;
      _error = null;
    });

    try {
      final api = AdhanBoxAPI(
        baseUrl: 'http://$ip',
        timeout: const Duration(seconds: 5),
      );

      final status = await api.getStatus();

      if (status.containsKey('wifi') && status.containsKey('rtc_ok')) {
        // Sauvegarder l'IP
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('deviceIp', ip);
        ref.read(currentDeviceIpProvider.notifier).state = ip;
        ref.invalidate(deviceIpProvider);

        // Envoyer automatiquement la position GPS à l'ESP
        try {
          print('DEBUG: Envoi automatique de la position GPS (connexion manuelle)...');
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
          await api.setLocation(
            position.latitude,
            position.longitude,
            position.accuracy,
          );
          print('DEBUG: ✓ Position GPS envoyée: ${position.latitude}, ${position.longitude}');
        } catch (e) {
          print('DEBUG: ✗ Échec envoi GPS automatique: $e (peut être configuré manuellement plus tard)');
        }

        // Synchroniser l'heure du RTC avec le smartphone
        try {
          print('DEBUG: Synchronisation de l\'heure RTC (connexion manuelle)...');
          await api.setRtcTime(DateTime.now());
          print('DEBUG: ✓ Heure RTC synchronisée');
        } catch (e) {
          print('DEBUG: ✗ Échec sync RTC: $e');
        }

        setState(() {
          _deviceIp = ip;
          _step = 5;
          _isSearchingOnHomeNetwork = false;
        });
      } else {
        setState(() {
          _error = 'Cette adresse ne correspond pas à un AdhanBox';
          _isSearchingOnHomeNetwork = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Impossible de contacter l\'appareil à $ip: $e';
        _isSearchingOnHomeNetwork = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration AdhanBox'),
        leading: _step > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_step == 2) {
                    setState(() => _step = 1);
                  } else if (_step == 3) {
                    setState(() => _step = 2);
                  } else {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStepIndicator(),
          const SizedBox(height: 24),

          // Étape 1: Scanner les WiFi Adhanbox
          if (_step == 1) _buildStep1_ScanAdhanbox(),

          // Étape 2: Connexion auto au WiFi Adhanbox
          if (_step == 2) _buildStep2_ConnectToAdhanbox(),

          // Étape 3: Configurer le WiFi maison
          if (_step == 3) _buildStep3_ConfigureHomeWifi(),

          // Étape 4: Recherche sur réseau maison
          if (_step == 4) _buildStep4_FindOnHomeNetwork(),

          // Étape 5: Configuration finale
          if (_step == 5) _buildStep5_FinalConfig(),

          // Afficher les erreurs
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStepDot(1, 'Scan'),
        _buildStepLine(),
        _buildStepDot(2, 'Connect'),
        _buildStepLine(),
        _buildStepDot(3, 'WiFi'),
        _buildStepLine(),
        _buildStepDot(4, 'Réseau'),
        _buildStepLine(),
        _buildStepDot(5, 'Config'),
      ],
    );
  }

  Widget _buildStepDot(int step, String label) {
    final isActive = _step >= step;
    final isCurrent = _step == step;

    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.green : Colors.grey[300],
            border: Border.all(
              color: isCurrent ? Colors.green : Colors.transparent,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              step.toString(),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine() {
    return Expanded(
      child: Container(
        height: 2,
        color: _step > 1 ? Colors.green : Colors.grey[300],
      ),
    );
  }

  /// ========== WIDGETS DES ÉTAPES ==========

  /// Étape 1: Scanner les WiFi AdhanBox disponibles
  Widget _buildStep1_ScanAdhanbox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📡 Recherche d\'AdhanBox',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Scan des réseaux WiFi émis par vos appareils AdhanBox...',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (_isScanningAdhanboxWifi)
          const Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Scan en cours...'),
              ],
            ),
          )
        else if (_adhanboxNetworks.isEmpty)
          Center(
            child: Column(
              children: [
                const Icon(Icons.wifi_off, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Aucun AdhanBox trouvé',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? 'Le scan WiFi natif n\'est pas disponible sur navigateur. Connectez votre PC au WiFi AdhanBox puis continuez.'
                      : 'Vérifiez que l\'ESP32 est allumé',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                if (kIsWeb)
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedAdhanboxWifi = 'AdhanBox (manuel)';
                        _step = 2;
                      });
                      _connectToAdhanBoxWifi();
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Je suis connecté à AdhanBox'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _scanForAdhanBoxNetworks,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Rescanner'),
                  ),
              ],
            ),
          )
        else
          Column(
            children: [
              ..._adhanboxNetworks.map((network) {
                final ssid = network['ssid']?.toString() ?? 'Unknown';
                final rssi = network['rssi'] as int? ?? 0;
                final isSelected = _selectedAdhanboxWifi == ssid;

                return Card(
                  color: isSelected ? Colors.blue.shade50 : null,
                  elevation: isSelected ? 4 : 1,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.router,
                      color: isSelected ? Colors.green : Colors.grey,
                      size: 32,
                    ),
                    title: Text(
                      ssid,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('Signal: $rssi dBm'),
                    trailing: Radio<String>(
                      value: ssid,
                      groupValue: _selectedAdhanboxWifi,
                      onChanged: (value) {
                        setState(() => _selectedAdhanboxWifi = value);
                      },
                    ),
                    onTap: () {
                      setState(() => _selectedAdhanboxWifi = ssid);
                    },
                  ),
                );
              }).toList(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanForAdhanBoxNetworks,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Rescanner'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _selectedAdhanboxWifi == null
                          ? null
                          : () {
                              setState(() => _step = 2);
                              _connectToAdhanBoxWifi();
                            },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Connecter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  /// Étape 2: Connexion automatique au WiFi AdhanBox
  Widget _buildStep2_ConnectToAdhanbox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🔗 Connexion à l\'AdhanBox',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Réseau sélectionné: $_selectedAdhanboxWifi',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (_isConnectingToAdhanbox)
          const Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Connexion en cours...'),
                SizedBox(height: 8),
                Text(
                  'Tentative de connexion à l\'AdhanBox',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          )
        else
          Center(
            child: Column(
              children: [
                const Icon(Icons.wifi_tethering, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Action requise',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📱 Connectez-vous au réseau AdhanBox',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _openWiFiSettings,
                          icon: const Icon(Icons.settings, size: 20),
                          label: const Text('Ouvrir les paramètres WiFi'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            side: const BorderSide(color: Colors.blue, width: 2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '1. Cliquez sur le bouton ci-dessus',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '2. Sélectionnez "$_selectedAdhanboxWifi"',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '3. Revenez dans l\'app',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '💡 Aucun mot de passe nécessaire',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _connectToAdhanBoxWifi,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Je suis connecté'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _step = 1;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Retour au scan'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Étape 3: Configuration du WiFi maison
  Widget _buildStep3_ConfigureHomeWifi() {
    final passwordController = TextEditingController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🏠 Configuration WiFi maison',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choisissez le réseau WiFi auquel l\'AdhanBox doit se connecter',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (_isScanningHomeWifi)
          const Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Récupération des réseaux disponibles...'),
              ],
            ),
          )
        else if (_homeWifiNetworks.isEmpty)
          const Center(
            child: Text('Aucun réseau détecté'),
          )
        else
          Column(
            children: [
              const Text(
                'Réseaux WiFi disponibles:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._homeWifiNetworks.map((network) {
                final ssid = network['ssid']?.toString() ?? 'Unknown';
                final rssi = network['rssi'] as int? ?? 0;
                final isSelected = _selectedHomeWifi == ssid;

                return Card(
                  color: isSelected ? Colors.green.shade50 : null,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.wifi,
                      color: isSelected ? Colors.green : Colors.grey,
                    ),
                    title: Text(ssid),
                    subtitle: Text('Signal: $rssi dBm'),
                    trailing: Radio<String>(
                      value: ssid,
                      groupValue: _selectedHomeWifi,
                      onChanged: (value) {
                        setState(() => _selectedHomeWifi = value);
                      },
                    ),
                    onTap: () {
                      setState(() => _selectedHomeWifi = ssid);
                    },
                  ),
                );
              }).toList(),
              if (_selectedHomeWifi != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe WiFi',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                    helperText: 'Entrez le mot de passe de votre réseau WiFi',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_selectedHomeWifi == null ||
                          _isSendingCredentials)
                      ? null
                      : () =>
                          _sendWifiCredentialsToESP32(passwordController.text),
                  icon: _isSendingCredentials
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSendingCredentials
                      ? 'Envoi en cours...'
                      : 'Configurer l\'AdhanBox'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Étape 4: Recherche sur le réseau maison
  Widget _buildStep4_FindOnHomeNetwork() {
    // Écran d'attente: demander à l'utilisateur de se reconnecter au WiFi maison
    if (!_step4ReadyToSearch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚠️ Reconnexion WiFi',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Reconnectez-vous à votre WiFi maison',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _openWiFiSettings,
                    icon: const Icon(Icons.settings, size: 20),
                    label: const Text('Ouvrir les paramètres WiFi'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      side: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.orange),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. Cliquez sur "Ouvrir paramètres WiFi"',
                          style: TextStyle(fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '2. Sélectionnez votre WiFi maison',
                          style: TextStyle(fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '3. Revenez ici',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _step4ReadyToSearch = true);
                      _findESP32OnHomeNetwork();
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('Chercher l\'AdhanBox'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Écran de recherche principal
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🔍 Recherche sur réseau maison',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'L\'AdhanBox se connecte à votre WiFi...',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        Center(
          child: _isSearchingOnHomeNetwork
              ? Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Recherche en cours...'),
                    if (_networkScanProgress.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _networkScanProgress,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Cela peut prendre jusqu\'à 1 minute',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                )
              : _deviceIp != null
                  ? Column(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 64, color: Colors.green),
                        const SizedBox(height: 16),
                        const Text(
                          'AdhanBox trouvée !',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Adresse IP: $_deviceIp',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _step = 5);
                          },
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Continuer'),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Card(
                          color: Colors.blue.shade50,
                          child: const Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 48, color: Colors.blue),
                                SizedBox(height: 16),
                                Text(
                                  'L\'AdhanBox doit maintenant se connecter à votre WiFi.',
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Reconnectez votre téléphone à votre WiFi habituel,',
                                  style: TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  'puis appuyez sur "Rechercher"',
                                  style: TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _findESP32OnHomeNetwork,
                          icon: const Icon(Icons.search),
                          label: const Text('Rechercher l\'AdhanBox'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        const Text(
                          'L\'AdhanBox n\'est pas trouvée automatiquement ?',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Vous pouvez entrer son adresse IP manuellement:',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: _manualIpController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Adresse IP',
                                  hintText: '192.168.1.100',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.language),
                                  helperText:
                                      'Ex: 192.168.1.100 ou 192.168.0.50',
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  final ip = _manualIpController.text.trim();
                                  if (ip.isNotEmpty) {
                                    _testManualIp(ip);
                                  }
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Tester cette adresse'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  /// Étape 5: Configuration finale
  Widget _buildStep5_FinalConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '✅ Configuration terminée !',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Votre AdhanBox est maintenant connectée à Internet',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              const Icon(Icons.celebration, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Appareil configuré: $_deviceIp',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🕌 Prochaines étapes:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('• Configurer Mawaqit pour votre mosquée'),
                      Text('• Régler le fuseau horaire'),
                      Text('• Ajuster le volume et la luminosité'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const CalculationSetupScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Configurer les horaires'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Terminer et revenir à l\'accueil'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
