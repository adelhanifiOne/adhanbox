import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/adhanbox_provider.dart';
import '../services/adhanbox_api.dart';
import 'mawaqit_config_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _scanForAdhanBoxNetworks();
  }

  /// ========== ÉTAPE 1: Scanner les réseaux WiFi Adhanbox ==========
  
  Future<void> _scanForAdhanBoxNetworks() async {
    setState(() {
      _isScanningAdhanboxWifi = true;
      _error = null;
    });

    try {
      // TODO: Utiliser wifi_scan package pour scanner les réseaux réels
      // final results = await WiFiScan.instance.getScannedResults();
      // Filtrer uniquement ceux qui commencent par "Adhanbox"
      
      // Simulation temporaire
      await Future.delayed(const Duration(seconds: 2));
      
      setState(() {
        _adhanboxNetworks = [
          {'ssid': 'AdhanBox_A1B2C3', 'rssi': -45, 'security': 'open'},
          {'ssid': 'AdhanBox_Setup', 'rssi': -50, 'security': 'open'},
        ];
      });

      if (_adhanboxNetworks.isEmpty) {
        setState(() {
          _error = 'Aucun AdhanBox détecté. Assurez-vous que l\'ESP32 est allumé.';
        });
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
      // TODO: Utiliser wifi_iot_plugin ou network_info_plus pour connexion auto
      // await WiFiForIoTPlugin.connect(_selectedAdhanboxWifi, 
      //     password: '', security: NetworkSecurity.NONE);
      
      // Simulation: demander à l'utilisateur de se connecter manuellement
      await Future.delayed(const Duration(seconds: 2));
      
      // Vérifier la connexion à l'ESP32
      final api = AdhanBoxAPI(
        baseUrl: 'http://192.168.4.1',
        timeout: const Duration(seconds: 5),
      );
      
      final status = await api.getStatus();
      if (status['device']?.toString().toLowerCase().contains('adhanbox') ?? false) {
        setState(() {
          _step = 3;
          _isConnectingToAdhanbox = false;
        });
        
        // Demander à l'ESP32 de scanner les réseaux WiFi disponibles
        await _getHomeWifiNetworksFromESP32();
      } else {
        throw Exception('Appareil non reconnu');
      }
    } catch (e) {
      setState(() {
        _error = 'Impossible de se connecter à l\'AdhanBox.\n'
            'Vérifiez que vous êtes bien connecté au WiFi $_selectedAdhanboxWifi';
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
      // Si l'API n'existe pas encore, utiliser des données mock
      setState(() {
        _homeWifiNetworks = [
          {'ssid': 'MonWiFi_Maison', 'rssi': -55, 'security': 'WPA2'},
          {'ssid': 'Invites', 'rssi': -70, 'security': 'WPA2'},
        ];
        _isScanningHomeWifi = false;
      });
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
        _isSendingCredentials = false;
      });
      
      // Rechercher l'ESP32 sur le réseau maison
      await _findESP32OnHomeNetwork();
    } catch (e) {
      setState(() {
        _error = 'Erreur lors de l\'envoi des credentials: $e\n'
            'Vérifiez le mot de passe WiFi.';
        _isSendingCredentials = false;
      });
    }
  }

  /// ========== ÉTAPE 4: Retrouver l'ESP32 sur le réseau maison ==========
  
  Future<void> _findESP32OnHomeNetwork() async {
    setState(() {
      _isSearchingOnHomeNetwork = true;
      _error = null;
    });

    try {
      // TODO: Utiliser mDNS pour découvrir l'appareil
      // final info = await nsd.discover('_http._tcp.');
      
      // Pour maintenant, essayer l'IP que l'ESP32 a pu obtenir via DHCP
      // On peut aussi scanner la plage du réseau local
      
      // L'ESP32 devrait annoncer son IP via mDNS (adhanbox.local)
      // Ou on scanne les IPs classiques du réseau local
      
      await Future.delayed(const Duration(seconds: 3));
      
      // Simulation: IP trouvée
      const foundIp = '192.168.1.146'; // À remplacer par découverte réelle
      
      final api = AdhanBoxAPI(
        baseUrl: 'http://$foundIp',
        timeout: const Duration(seconds: 5),
      );
      
      final status = await api.getStatus();
      if (status['device']?.toString().toLowerCase().contains('adhanbox') ?? false) {
        // Sauvegarder l'IP trouvée
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('deviceIp', foundIp);
        ref.read(currentDeviceIpProvider.notifier).state = foundIp;
        ref.invalidate(deviceIpProvider);
        
        setState(() {
          _deviceIp = foundIp;
          _step = 5; // Configuration finale
          _isSearchingOnHomeNetwork = false;
        });
      } else {
        throw Exception('Appareil non trouvé sur le réseau');
      }
    } catch (e) {
      setState(() {
        _error = 'Impossible de trouver l\'AdhanBox sur le réseau maison.\n'
            'L\'appareil a peut-être échoué à se connecter au WiFi.';
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
                const Text(
                  'Vérifiez que l\'ESP32 est allumé',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
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
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
          'Connexion au réseau: $_selectedAdhanboxWifi',
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
                  'Connexion au WiFi de l\'AdhanBox',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          )
        else
          Center(
            child: Column(
              children: [
                const Icon(Icons.info_outline, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Action requise',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  color: Colors.blue.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📱 Connectez votre téléphone manuellement:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text('1. Ouvrez les paramètres WiFi de votre téléphone'),
                        Text('2. Connectez-vous au réseau AdhanBox'),
                        Text('3. Revenez dans l\'application'),
                        Text('4. Appuyez sur "Continuer"'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _connectToAdhanBoxWifi,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Je suis connecté, continuer'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
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
                  onPressed: (_selectedHomeWifi == null || _isSendingCredentials)
                      ? null
                      : () => _sendWifiCredentialsToESP32(passwordController.text),
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
              ? const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Recherche en cours...'),
                    SizedBox(height: 8),
                    Text(
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
                        builder: (_) => const MawaqitConfigScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.mosque),
                  label: const Text('Configurer Mawaqit'),
                  style: ElevatedButton.styleFrom(
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


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Étape 1: Sélectionner le WiFi',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cherchez le réseau WiFi émis par votre AdhanBox (ex: AdhanBox_XXXX)',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        
        if (_isScanningWifi)
          const Center(
            child: CircularProgressIndicator(),
          )
        else if (_wifiNetworks.isEmpty)
          Center(
            child: Column(
              children: [
                const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                const Text('Aucun réseau détecté'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _scanLocalWifiNetworks,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rescanner'),
                ),
              ],
            ),
          )
        else
          Column(
            children: _wifiNetworks.map<Widget>((network) {
              final ssid = network['ssid']?.toString() ?? 'Unknown';
              final rssi = network['rssi']?.toString() ?? '-';
              final isSelected = _selectedWifi == ssid;
              
              return Card(
                color: isSelected ? Colors.blue[50] : null,
                child: ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text(ssid),
                  subtitle: Text('Force: $rssi dBm'),
                  trailing: Radio<String>(
                    value: ssid,
                    groupValue: _selectedWifi,
                    onChanged: (value) {
                      setState(() => _selectedWifi = value);
                    },
                  ),
                  onTap: () {
                    setState(() => _selectedWifi = ssid);
                  },
                ),
              );
            }).toList(),
          ),
        
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedWifi == null || _isScanningWifi)
                ? null
                : () {
                    setState(() => _step = 2);
                  },
            child: const Text('Suivant'),
          ),
        ),
      ],
    );
  }

  /// Étape 2: Se connecter au WiFi (skip si ouvert)
  Widget _buildStep2() {
    final passwordController = TextEditingController();
    
    // Si le réseau est ouvert, passer directement à l'étape 3
    final selectedNetwork = _wifiNetworks.firstWhere(
      (n) => n['ssid'] == _selectedWifi,
      orElse: () => {},
    );
    final isOpen = selectedNetwork['security']?.toString().toLowerCase() == 'open';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Étape 2: Connexion au WiFi AdhanBox',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Réseau sélectionné: $_selectedWifi',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        
        if (!isOpen) ...[
          const Text(
            'Ce réseau est protégé. Entrez le mot de passe:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Mot de passe WiFi',
              border: const OutlineInputBorder(),
              suffixIcon: Icon(Icons.lock, color: Colors.grey[400]),
              helperText: 'Le mot de passe du WiFi AdhanBox (si configuré)',
            ),
          ),
        ] else ...[
          Card(
            color: Colors.green[50],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Réseau ouvert (pas de mot de passe requis)',
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        const SizedBox(height: 16),
        Card(
          color: Colors.blue[50],
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Important',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Assurez-vous que votre téléphone est bien connecté '
                  'au WiFi de l\'AdhanBox via les paramètres système.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _step = 1);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                ),
                child: const Text('Retour'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _isConnectingWifi
                    ? null
                    : () => _connectAppToWifi(
                          _selectedWifi!,
                          isOpen ? null : passwordController.text,
                        ),
                child: _isConnectingWifi
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continuer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Étape 3: Découvrir l'appareil
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Étape 3: Découverte de l\'AdhanBox',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _isDiscoveringDevice 
              ? 'Tentative de connexion à 192.168.4.1...'
              : _deviceIp != null
                  ? 'Appareil détecté avec succès !'
                  : 'Prêt à rechercher l\'appareil',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        
        Center(
          child: _isDiscoveringDevice
              ? const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Découverte en cours...'),
                    SizedBox(height: 8),
                    Text(
                      'Cela peut prendre jusqu\'à 30 secondes',
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
                        Text(
                          'Appareil trouvé: $_deviceIp',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _step = 4);
                          },
                          child: const Text('Continuer vers la configuration'),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        const Icon(Icons.wifi_find,
                            size: 64, color: Colors.orange),
                        const SizedBox(height: 16),
                        const Text(
                          'En attente de connexion',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Assurez-vous d\'être connecté au WiFi de l\'AdhanBox',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _discoveryAdhanBox,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() => _step = 2);
                          },
                          child: const Text('Retour'),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  /// Étape 4: Navigation vers Mawaqit config
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Étape 4: Configuration Mawaqit',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Votre AdhanBox est prête! Configurez maintenant Mawaqit pour afficher les horaires de votre mosquée.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        
        const Icon(Icons.mosque, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MawaqitConfigScreen(),
                ),
              );
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Aller à Mawaqit'),
          ),
        ),
      ],
    );
  }
}


