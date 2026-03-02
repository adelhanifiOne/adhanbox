import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../providers/adhanbox_provider.dart';

class MosqueData {
  final String uuid;
  final String name;
  final double lat;
  final double lon;
  final String? city;
  final String? address;

  MosqueData({
    required this.uuid,
    required this.name,
    required this.lat,
    required this.lon,
    this.city,
    this.address,
  });

  factory MosqueData.fromJson(Map<String, dynamic> json) {
    return MosqueData(
      uuid: json['uuid'] ?? json['slug'] ?? '',
      name: json['name'] ?? 'Mosquée',
      lat: (json['latitude'] ?? json['lat'] ?? 0.0).toDouble(),
      lon: (json['longitude'] ?? json['lon'] ?? 0.0).toDouble(),
      city: json['city'] ?? json['address'] ?? json['localisation'],
      address: json['address'] ?? json['adresse'] ?? json['localisation'],
    );
  }

  double distanceTo(double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat);
    final dLon = _toRadians(lon2 - lon);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}

class MawaqitConfigScreen extends ConsumerStatefulWidget {
  const MawaqitConfigScreen({super.key});

  @override
  ConsumerState<MawaqitConfigScreen> createState() =>
      _MawaqitConfigScreenState();
}

class _MawaqitConfigScreenState extends ConsumerState<MawaqitConfigScreen> {
  bool _isConfiguring = false;
  bool _isSearching = false;
  String? _error;
  String? _configuredMosque;
  List<MosqueData> _nearbyMosques = [];
  double? _userLat;
  double? _userLon;
  bool _showManualLocation = false;
  late TextEditingController _latController;
  late TextEditingController _lonController;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController();
    _lonController = TextEditingController();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<Position> _getReliablePosition() async {
    // Priorité absolue: obtenir une NOUVELLE position GPS du téléphone (pas du cache)
    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        throw Exception(
            'Permission de localisation refusée.\nVeuillez accepter les permissions.');
      }

      debugPrint('=== LOCALISATION GPS ===');
      
      // STRATÉGIE 1: Forcer une NOUVELLE position GPS en haute précision (5 min max)
      try {
        debugPrint('Tentative 1: GPS BEST (300s = 5 min)...');
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 300), // 5 minutes max
          forceAndroidLocationManager: false,
        );
        debugPrint(
            '✓ Position GPS obtenue: ${position.latitude}, ${position.longitude}');
        return position;
      } on TimeoutException {
        debugPrint('✗ GPS timeout, essai 2...');
      }

      // STRATÉGIE 2: Précision moyenne (3 min)
      try {
        debugPrint('Tentative 2: GPS MEDIUM (180s = 3 min)...');
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 180),
          forceAndroidLocationManager: false,
        );
        debugPrint(
            '✓ Position GPS obtenue (medium): ${position.latitude}, ${position.longitude}');
        return position;
      } on TimeoutException {
        debugPrint('✗ GPS timeout, essai 3...');
      }

      // STRATÉGIE 3: Précision basse (2 min)
      try {
        debugPrint('Tentative 3: GPS LOW (120s = 2 min)...');
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 120),
          forceAndroidLocationManager: false,
        );
        debugPrint(
            '✓ Position GPS obtenue (low): ${position.latitude}, ${position.longitude}');
        return position;
      } on TimeoutException {
        debugPrint('✗ GPS timeout complet');
      }

      // STRATÉGIE 4: Dernière position connue (seulement après tous les essais GPS)
      debugPrint('Fallback: Dernière position connue...');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        // Vérifier que ce n'est pas le fallback par défaut (Paris)
        final isParis = lastKnown.latitude == 48.8566 &&
            lastKnown.longitude == 2.3522;
        if (!isParis) {
          debugPrint(
              '✓ Dernière position valide: ${lastKnown.latitude}, ${lastKnown.longitude}');
          return lastKnown;
        }
      }
    } catch (e) {
      debugPrint('✗ Erreur GPS: $e');
    }

    // STRATÉGIE 5: Géolocalisation par IP (dernier recours)
    debugPrint('Fallback final: Géolocalisation par IP...');
    return await _getPositionByIP();
  }

  /// Obtenir la position par IP avec plusieurs sources (fallback sans GPS)
  Future<Position> _getPositionByIP() async {
    try {
      debugPrint('Fallback: Géolocalisation par IP (sources multiples)...');

      // Tester plusieurs services de géolocalisation IP en parallèle
      final futures = [
        _getIPLocationFromService('https://ipapi.co/json/'),
        _getIPLocationFromService('https://ip-api.com/json/'),
        _getIPLocationFromService('http://ip-api.com/json/'),
      ];

      final results = await Future.wait(futures, eagerError: false);

      for (final position in results) {
        if (position != null) {
          debugPrint(
              'Position obtenue par IP: ${position.latitude}, ${position.longitude}');
          return position;
        }
      }
    } catch (e) {
      debugPrint('Erreur géolocalisation IP: $e');
    }

    // Si tout échoue, lancer le processus de geolocation à nouveau avec timeout augmenté
    throw Exception('Impossible de déterminer votre localisation.\n\n'
        'Veuillez:\n'
        '1. Vérifier que le service de localisation est activé\n'
        '2. Vous assurer que l\'application a les permissions GPS\n'
        '3. Vous rapprocher d\'une fenêtre (améliore le signal GPS)\n'
        '4. Appuyer sur "Réessayer"');
  }

  /// Helper: Récupérer la localisation d'un service IP spécifique
  Future<Position?> _getIPLocationFromService(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        double? lat, lon;

        // Support multiple formats
        if (data['latitude'] != null && data['longitude'] != null) {
          lat = (data['latitude'] as num).toDouble();
          lon = (data['longitude'] as num).toDouble();
        } else if (data['lat'] != null && data['lon'] != null) {
          lat = (data['lat'] as num).toDouble();
          lon = (data['lon'] as num).toDouble();
        }

        if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
          return Position(
            latitude: lat,
            longitude: lon,
            timestamp: DateTime.now(),
            accuracy: 5000.0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
        }
      }
    } catch (e) {
      debugPrint('Service IP échoué ($url): $e');
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _autoDetectAndConfigure();
  }

  /// Rechercher les mosquées directement via l'API Mawaqit (sans passer par ESP32)
  Future<List<MosqueData>> _searchMosquesDirectly(
      double lat, double lon) async {
    try {
      // Essayer différents endpoints en PARALLÈLE (plus rapide)
      final endpoints = [
        'https://api.mawaqit.net/v1/mosque?latitude=$lat&longitude=$lon',
        'https://api.mawaqit.net/v1/mosque/nearby?latitude=$lat&longitude=$lon',
        'https://api.mawaqit.net/v1/mosques/search?latitude=$lat&longitude=$lon',
      ];

      // Teste tous les endpoints en parallèle au lieu de séquentiellement
      final futures = endpoints.map((endpoint) async {
        try {
          debugPrint('Essai endpoint: $endpoint');
          final searchResponse = await http
              .get(Uri.parse(endpoint))
              .timeout(const Duration(seconds: 10));

          debugPrint('Réponse statut: ${searchResponse.statusCode}');

          if (searchResponse.statusCode == 200) {
            final searchData = jsonDecode(searchResponse.body);

            // Essayer différentes clés de réponse
            List<dynamic> mosquesList = searchData['data'] as List? ??
                searchData['mosques'] as List? ??
                searchData['results'] as List? ??
                (searchData is List ? searchData : []);

            if (mosquesList.isNotEmpty) {
              debugPrint('Mosquées trouvées: ${mosquesList.length}');
              final mosques = mosquesList
                  .map((m) {
                    try {
                      return MosqueData.fromJson(m as Map<String, dynamic>);
                    } catch (e) {
                      return null;
                    }
                  })
                  .whereType<MosqueData>()
                  .where((m) => m.uuid.isNotEmpty)
                  .toList();

              if (mosques.isNotEmpty) {
                return mosques;
              }
            }
          }
        } catch (e) {
          debugPrint('Endpoint échoué: $e');
        }
        return <MosqueData>[];
      });

      // Exécute tous les futures en parallèle, prend le premier résultat non-vide
      final results = await Future.wait(futures);
      for (final mosques in results) {
        if (mosques.isNotEmpty) {
          return mosques;
        }
      }

      // Fallback : Retourner une liste manuelle de grandes mosquées
      debugPrint(
          'API échouée, fallback sur liste manuelle de mosquées connues');
      return _getFallbackMosques();
    } catch (e) {
      debugPrint('Erreur recherche Mawaqit: $e');
      return _getFallbackMosques();
    }
  }

  /// Liste manuelle de mosquées courantes (fallback)
  List<MosqueData> _getFallbackMosques() {
    return [
      MosqueData(
        uuid: 'grande-mosque-paris',
        name: 'Grande Mosquée de Paris',
        lat: 48.8372,
        lon: 2.3588,
        city: 'Paris 5e',
        address: '1 Rue Dieudé, 75005 Paris',
      ),
      MosqueData(
        uuid: 'mosquee-strasbourg',
        name: 'Mosquée de Strasbourg',
        lat: 48.5734,
        lon: 7.7521,
        city: 'Strasbourg',
        address: 'Rue du Fossé des Treize',
      ),
      MosqueData(
        uuid: 'mosquee-marseille',
        name: 'Mosquée Al-Farouq',
        lat: 43.2947,
        lon: 5.3708,
        city: 'Marseille',
        address: 'Boulevard Saint-Yves',
      ),
      MosqueData(
        uuid: 'mosquee-pau',
        name: 'Mosquée de Pau',
        lat: 43.2929,
        lon: -0.3654,
        city: 'Pau',
        address: 'Rue Maréchal Joffre',
      ),
      MosqueData(
        uuid: 'mosquee-bordeaux',
        name: 'Mosquée Abou Ayyoub As-Saluki',
        lat: 44.8378,
        lon: -0.5792,
        city: 'Bordeaux',
        address: 'Rue du Château Trompette',
      ),
    ];
  }

  Future<void> _autoDetectAndConfigure() async {
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      // IMPORTANT: Vérifier la connexion Internet
      final isConnected = await _checkInternetConnection();
      if (!isConnected) {
        setState(() {
          _error = 'Pas d\'accès à Internet.\n\n'
              '⚠️ Veuillez:\n'
              '1. Aller dans les paramètres WiFi\n'
              '2. Déconnecter du WiFi AdhanBox\n'
              '3. Reconnecter à votre WiFi maison\n'
              '4. Revenir à cette fenêtre\n\n'
              'Puis appuyez sur "Réessayer".';
          _isSearching = false;
        });
        return;
      }

      // 1. Get phone's GPS location (avec fallback sur dernière position connue)
      final position = await _getReliablePosition();

      _userLat = position.latitude;
      _userLon = position.longitude;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Position détectée: ${_userLat!.toStringAsFixed(4)}, ${_userLon!.toStringAsFixed(4)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 2. Search mosques via API Mawaqit directe (plus fiable)
      final mosques = await _searchMosquesDirectly(_userLat!, _userLon!);

      if (mosques.isEmpty) {
        throw Exception(
            'Aucune mosquée trouvée à proximité.\nVérifiez votre position GPS.');
      }

      // Sort by distance
      mosques.sort((a, b) {
        final distA = a.distanceTo(_userLat!, _userLon!);
        final distB = b.distanceTo(_userLat!, _userLon!);
        return distA.compareTo(distB);
      });

      setState(() {
        _nearbyMosques = mosques.take(10).toList();
      });

      // Show results
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${mosques.length} mosquées trouvées à proximité'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on TimeoutException catch (e) {
      setState(() {
        _error = 'Délai dépassé.\n'
            'Vérifications:\n'
            '• GPS activé en haute précision\n'
            '• Position stabilisée (attendre 30s)\n'
            '• Connexion WiFi stable';
      });
      debugPrint('TimeoutException: $e');
    } catch (e) {
      setState(() {
        _error = 'Erreur: $e';
      });
      debugPrint('Erreur autoDetectAndConfigure: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  /// Vérifier l'accès à Internet (utilise HTTP pour éviter les problèmes de certificats sur Android ancien)
  Future<bool> _checkInternetConnection() async {
    // Utiliser HTTP au lieu de HTTPS pour éviter les erreurs de certificats sur Android 6
    final urls = [
      'http://www.google.com',
      'http://captive.apple.com', // URL utilisée par Apple pour détecter les portails captifs
      'http://connectivitycheck.gstatic.com/generate_204', // Test de connectivité Google
    ];

    final futures = urls.map((url) async {
      try {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        return response.statusCode >= 200 && response.statusCode < 500;
      } catch (e) {
        debugPrint('Test Internet échoué pour $url: $e');
        return false;
      }
    });

    final results = await Future.wait(futures);
    final hasInternet = results.any((result) => result);

    if (!hasInternet) {
      debugPrint('Aucune URL de test n\'a répondu - pas d\'Internet');
    } else {
      debugPrint('Connexion Internet détectée avec succès');
    }

    return hasInternet;
  }

  Future<bool> _checkLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Service de localisation désactivé');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permission de localisation refusée définitivement');
    }

    return true;
  }

  Future<void> _configureMosque(MosqueData mosque) async {
    setState(() {
      _isConfiguring = true;
      _error = null;
    });

    try {
      final deviceIp = ref.read(currentDeviceIpProvider);
      if (deviceIp == null || deviceIp.isEmpty) {
        throw Exception('Aucune adresse IP configurée');
      }

      // Vérification importante: s'assurer que ce n'est pas l'adresse AP initiale
      if (deviceIp == '192.168.4.1') {
        throw Exception('IP incorrect (adresse AP).\n\n'
            'Vous semblez toujours connecté au WiFi AdhanBox.\n\n'
            'Veuillez:\n'
            '1. Retourner à l\'écran précédent\n'
            '2. Reconnecter le WiFi maison\n'
            '3. Recommencer l\'étape 4 (Rechercher l\'AdhanBox)\n'
            '4. Revenir ici');
      }

      final response = await http
          .post(
            Uri.parse('http://$deviceIp/api/mawaqit/config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mosque_uuid': mosque.uuid}),
          )
          .timeout(
              const Duration(seconds: 30)); // ESP32 fait un fetch, plus long

      if (response.statusCode == 200) {
        setState(() {
          _configuredMosque = mosque.name;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Mosquée configurée: ${mosque.name}\nSynchronisation...'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Force sync on ESP32
        try {
          final syncResponse = await http
              .post(
                Uri.parse('http://$deviceIp/api/mawaqit/sync'),
              )
              .timeout(const Duration(seconds: 60));

          if (syncResponse.statusCode == 200) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Horaires synchronisés ! ✓'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        } catch (_) {
          // Sync silently failed, but data might still be cached
        }

        // Invalidate cache providers to refresh data
        // Important: invalider aussi mawaqitTimesProvider et deviceStatusProvider
        ref.invalidate(prayerTimesProvider);
        ref.invalidate(mawaqitComparisonProvider);
        ref.invalidate(mawaqitTimesProvider);
        ref.invalidate(deviceStatusProvider);

        // Attendre plus longtemps pour que l'ESP32 complète la synchronisation
        await Future.delayed(const Duration(seconds: 4));

        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Erreur de configuration');
      }
    } on TimeoutException {
      setState(() {
        _error = 'Le module AdhanBox met trop de temps à répondre.\n'
            'Vérifiez que le téléphone et l\'AdhanBox sont sur le même WiFi, puis réessayez.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timeout réseau: vérifiez la connexion WiFi locale.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur de configuration: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isConfiguring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSearching) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Configuration Mawaqit'),
          backgroundColor: Colors.teal,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text(
                'Recherche en cours...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Détection de votre position GPS'),
              SizedBox(height: 8),
              Text('Recherche des mosquées locales sur Mawaqit'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration Mawaqit'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _autoDetectAndConfigure,
            tooltip: 'Actualiser la recherche',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Location info
            if (_userLat != null && _userLon != null)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Position: ${_userLat!.toStringAsFixed(4)}, ${_userLon!.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Error card
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Erreur',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _autoDetectAndConfigure,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Success message
            if (_configuredMosque != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Configuration réussie !',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _configuredMosque!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Nearby mosques list
            if (_nearbyMosques.isNotEmpty && _userLat != null) ...[
              const SizedBox(height: 24),
              // Position détectée avec option de modification
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📍 Position détectée',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lat: ${_userLat!.toStringAsFixed(4)}, Lon: ${_userLon!.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (!_showManualLocation) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showManualLocation = true;
                              _latController.text =
                                  _userLat!.toStringAsFixed(6);
                              _lonController.text =
                                  _userLon!.toStringAsFixed(6);
                            });
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Corriger la localisation'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _latController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _lonController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setState(() => _showManualLocation = false);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                              ),
                              child: const Text('Annuler'),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                try {
                                  final lat = double.parse(_latController.text);
                                  final lon = double.parse(_lonController.text);

                                  setState(() {
                                    _userLat = lat;
                                    _userLon = lon;
                                    _showManualLocation = false;
                                    _nearbyMosques = [];
                                    _isSearching = true;
                                  });

                                  final mosques =
                                      await _searchMosquesDirectly(lat, lon);
                                  mosques.sort((a, b) {
                                    final distA = a.distanceTo(lat, lon);
                                    final distB = b.distanceTo(lat, lon);
                                    return distA.compareTo(distB);
                                  });

                                  setState(() {
                                    _nearbyMosques = mosques.take(10).toList();
                                    _isSearching = false;
                                  });

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Position mise à jour ✓'),
                                        backgroundColor: Colors.green,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Lat/Lon invalide: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                              child: const Text('Rechercher'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Mosquées à proximité (${_nearbyMosques.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sélectionnez votre mosquée locale',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              ..._nearbyMosques.map((mosque) {
                final distance = mosque.distanceTo(_userLat!, _userLon!);
                final isConfigured = _configuredMosque == mosque.name;
                final locationText =
                    mosque.city ?? mosque.address ?? 'Aucune adresse';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isConfigured ? Colors.green.shade50 : null,
                  elevation: isConfigured ? 3 : 1,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isConfigured ? Colors.green : Colors.teal,
                      child: Icon(
                        isConfigured ? Icons.check : Icons.mosque,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      mosque.name,
                      style: TextStyle(
                        fontWeight:
                            isConfigured ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '$locationText • ${distance.toStringAsFixed(1)} km',
                    ),
                    trailing: _isConfiguring
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ElevatedButton(
                            onPressed: () => _configureMosque(mosque),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isConfigured ? Colors.green : Colors.teal,
                            ),
                            child:
                                Text(isConfigured ? 'Configurée' : 'Choisir'),
                          ),
                  ),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }
}
