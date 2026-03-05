import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../providers/adhanbox_provider.dart';
import 'device_setup_screen.dart';
import 'mawaqit_offsets_screen.dart';

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
  late TextEditingController _mosqueSearchController;
  String _selectedCalcMethod = 'mwl';

  final Map<String, String> _calcMethodLabels = const {
    'mwl': 'Muslim World League (Fajr 18° / Isha 17°)',
    'isna': 'ISNA (Fajr 15° / Isha 15°)',
    'uoif': 'UOIF/France (Fajr 12° / Isha 12°)',
    'egypt': 'Egyptian (Fajr 19.5° / Isha 17.5°)',
    'karachi': 'Karachi (Fajr 18° / Isha 18°)',
  };

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController();
    _lonController = TextEditingController();
    _mosqueSearchController = TextEditingController();
    _autoDetectAndConfigure();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _mosqueSearchController.dispose();
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
        final decoded = jsonDecode(response.body);
        final data = _asMap(decoded);
        if (data == null) return null;

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

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
    }
    return null;
  }

  List<MosqueData> _parseOverpassMosques(dynamic decoded) {
    final root = _asMap(decoded);
    if (root == null) return [];
    final elements = root['elements'];
    if (elements is! List) return [];

    final mosques = <MosqueData>[];

    for (final item in elements) {
      final element = _asMap(item);
      if (element == null) continue;

      final tags = _asMap(element['tags']) ?? <String, dynamic>{};
      final name = (tags['name'] ?? tags['name:fr'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final center = _asMap(element['center']);
      final latRaw = element['lat'] ?? center?['lat'];
      final lonRaw = element['lon'] ?? center?['lon'];
      if (latRaw == null || lonRaw == null) continue;

      final lat = double.tryParse(latRaw.toString());
      final lon = double.tryParse(lonRaw.toString());
      if (lat == null || lon == null) continue;

      final city = (tags['addr:city'] ?? tags['is_in:city'] ?? '').toString();
      final street = (tags['addr:street'] ?? '').toString();
      final houseNumber = (tags['addr:housenumber'] ?? '').toString();
      final address = [houseNumber, street]
          .where((part) => part.trim().isNotEmpty)
          .join(' ')
          .trim();

      mosques.add(
        MosqueData(
          uuid: 'osm-${element['id']}',
          name: name,
          lat: lat,
          lon: lon,
          city: city.isEmpty ? null : city,
          address: address.isEmpty ? null : address,
        ),
      );
    }

    final dedup = <String, MosqueData>{};
    for (final mosque in mosques) {
      final key = '${mosque.name.toLowerCase()}_${mosque.lat.toStringAsFixed(5)}_${mosque.lon.toStringAsFixed(5)}';
      dedup[key] = mosque;
    }

    return dedup.values.toList();
  }

  List<MosqueData> _parsePhotonMosques(dynamic decoded) {
    final root = _asMap(decoded);
    if (root == null) return [];
    final features = root['features'];
    if (features is! List) return [];

    final mosques = <MosqueData>[];
    for (final item in features) {
      final feature = _asMap(item);
      if (feature == null) continue;

      final properties = _asMap(feature['properties']) ?? <String, dynamic>{};
      final geometry = _asMap(feature['geometry']) ?? <String, dynamic>{};
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;

      final lon = double.tryParse(coords[0].toString());
      final lat = double.tryParse(coords[1].toString());
      if (lat == null || lon == null) continue;

      final name = (properties['name'] ?? properties['osm_value'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final osmValue = (properties['osm_value'] ?? '').toString().toLowerCase();
      final osmKey = (properties['osm_key'] ?? '').toString().toLowerCase();
      final type = (properties['type'] ?? '').toString().toLowerCase();
      
      // Filtre plus large pour capturer toutes les mosquées
      final looksMosque = name.toLowerCase().contains('mosqu') ||
          name.toLowerCase().contains('mosque') ||
          name.toLowerCase().contains('مسجد') ||
          osmValue == 'mosque' ||
          osmValue.contains('mosque') ||
          (osmKey == 'amenity' && osmValue == 'place_of_worship') ||
          (osmKey == 'building' && osmValue == 'mosque') ||
          type.contains('mosque');
      if (!looksMosque) continue;

      final city = (properties['city'] ?? properties['district'] ?? '').toString();
      final street = (properties['street'] ?? '').toString();
      final houseNumber = (properties['housenumber'] ?? '').toString();
      final address = [houseNumber, street]
          .where((part) => part.trim().isNotEmpty)
          .join(' ')
          .trim();

      final id = (properties['osm_id'] ?? properties['id'] ?? '${lat}_$lon').toString();

      mosques.add(
        MosqueData(
          uuid: 'photon-$id',
          name: name,
          lat: lat,
          lon: lon,
          city: city.isEmpty ? null : city,
          address: address.isEmpty ? null : address,
        ),
      );
    }

    final dedup = <String, MosqueData>{};
    for (final mosque in mosques) {
      final key = '${mosque.name.toLowerCase()}_${mosque.lat.toStringAsFixed(5)}_${mosque.lon.toStringAsFixed(5)}';
      dedup[key] = mosque;
    }
    return dedup.values.toList();
  }

  Future<List<MosqueData>> _searchMosquesViaPhoton(double lat, double lon) async {
    try {
      debugPrint('=== RECHERCHE PHOTON ===');
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': 'mosque',
        'lat': lat.toString(),
        'lon': lon.toString(),
        'limit': '50',
        'distance_sort': 'true',
      });

      debugPrint('>>> Photon endpoint: $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      debugPrint('<<< Photon status: ${response.statusCode}, body length: ${response.body.length}');

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        debugPrint('✗ Photon: pas de résultats (status=${response.statusCode})');
        return [];
      }

      final decoded = jsonDecode(response.body);
      final mosques = _parsePhotonMosques(decoded);
      debugPrint('✓ Mosquées Photon parsées: ${mosques.length}');
      
      return mosques;
    } on TimeoutException {
      debugPrint('✗ Photon timeout après 15s');
      return [];
    } catch (e) {
      debugPrint('✗ Photon échec: $e');
      return [];
    }
  }

  /// Rechercher des mosquées réellement proches via OpenStreetMap/Overpass
  Future<List<MosqueData>> _searchMosquesDirectly(double lat, double lon) async {
    try {
      debugPrint('=== RECHERCHE MOSQUÉES OSM ===');
      debugPrint('GPS: lat=$lat, lon=$lon');
      final startedAt = DateTime.now();

      final overpassQuery = '''
[out:json][timeout:35];
(
  node["amenity"="place_of_worship"]["religion"="muslim"](around:35000,$lat,$lon);
  way["amenity"="place_of_worship"]["religion"="muslim"](around:35000,$lat,$lon);
  relation["amenity"="place_of_worship"]["religion"="muslim"](around:35000,$lat,$lon);
  node["building"="mosque"](around:35000,$lat,$lon);
  way["building"="mosque"](around:35000,$lat,$lon);
  relation["building"="mosque"](around:35000,$lat,$lon);
  node["amenity"="mosque"](around:35000,$lat,$lon);
  way["amenity"="mosque"](around:35000,$lat,$lon);
  relation["amenity"="mosque"](around:35000,$lat,$lon);
);
out center tags;
''';

      final endpoints = [
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://overpass.openstreetmap.ru/api/interpreter',
      ];

      for (final endpoint in endpoints) {
        if (DateTime.now().difference(startedAt) > const Duration(seconds: 35)) {
          debugPrint('⏱️ Timeout global Overpass atteint (35s)');
          break;
        }
        try {
          debugPrint('>>> Overpass endpoint: $endpoint');
          final response = await http
              .post(
                Uri.parse(endpoint),
                headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                body: {'data': overpassQuery},
              )
              .timeout(const Duration(seconds: 12));

          debugPrint('<<< Overpass status: ${response.statusCode}');
          if (response.statusCode != 200 || response.body.trim().isEmpty) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          final mosques = _parseOverpassMosques(decoded);
          if (mosques.isNotEmpty) {
            debugPrint('✓ Mosquées OSM trouvées: ${mosques.length}');
            return mosques;
          }
        } catch (e) {
          debugPrint('✗ Overpass échec: $e');
        }
      }

      // Fallback rapide: Photon (toujours données OSM, souvent plus stable)
      final photonMosques = await _searchMosquesViaPhoton(lat, lon);
      return photonMosques;
    } catch (e) {
      debugPrint('✗ Erreur recherche OSM: $e');
      return [];
    }
  }

  /// Rechercher les mosquées par nom de ville ou code postal
  Future<void> _searchMosquesByCity() async {
    final cityInput = _mosqueSearchController.text.trim();
    if (cityInput.isEmpty) {
      setState(() {
        _error = 'Veuillez entrer une ville ou un code postal';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final geocodeUrl = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': cityInput,
          'format': 'json',
          'limit': '1',
          'countrycodes': 'fr',
        },
      );

      final geocodeResponse = await http.get(
        geocodeUrl,
        headers: {'User-Agent': 'AdhanBox/1.0 (Flutter)'} ,
      ).timeout(const Duration(seconds: 15));

      if (geocodeResponse.statusCode != 200 || geocodeResponse.body.trim().isEmpty) {
        throw Exception('Impossible de géocoder "$cityInput"');
      }

      final geocodeData = jsonDecode(geocodeResponse.body);
      if (geocodeData is! List || geocodeData.isEmpty) {
        throw Exception('Ville/code postal introuvable');
      }

      final first = _asMap(geocodeData.first);
      final lat = double.tryParse((first?['lat'] ?? '').toString());
      final lon = double.tryParse((first?['lon'] ?? '').toString());
      if (lat == null || lon == null) {
        throw Exception('Coordonnées invalides pour "$cityInput"');
      }

      _userLat = lat;
      _userLon = lon;

      final mosques = await _searchMosquesDirectly(lat, lon);
      if (mosques.isEmpty) {
        throw Exception('Aucune mosquée trouvée autour de "$cityInput"');
      }

      mosques.sort((a, b) {
        final distA = a.distanceTo(lat, lon);
        final distB = b.distanceTo(lat, lon);
        return distA.compareTo(distB);
      });

      setState(() {
        _nearbyMosques = mosques.take(20).toList();
        _isSearching = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Recherche impossible: $e';
        _isSearching = false;
      });
    }
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

        // 2. Search mosques with hard timeout to avoid infinite spinner
        debugPrint('>>> Début recherche mosquées (timeout 50s)...');
        final mosques = await _searchMosquesDirectly(_userLat!, _userLon!)
          .timeout(const Duration(seconds: 50));
        debugPrint('<<< Recherche terminée: ${mosques.length} mosquées');

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

  Future<void> _configureCalculatedFallback() async {
    setState(() {
      _isConfiguring = true;
      _error = null;
    });

    try {
      final api = ref.read(adhanboxApiProvider);
      if (api == null) {
        throw Exception('Aucun appareil configuré');
      }

      await api.setCalculationConfig(method: _selectedCalcMethod);

      ref.invalidate(prayerTimesProvider);
      ref.invalidate(deviceStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Horaires calculés activés (${_calcMethodLabels[_selectedCalcMethod] ?? _selectedCalcMethod})',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      setState(() {
        _configuredMosque = 'Mode calcul activé';
      });

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _error = 'Impossible d\'activer le mode calcul: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur mode calcul: $e'),
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

  Future<void> _configureMosque(MosqueData mosque) async {
    final deviceIp = ref.read(currentDeviceIpProvider);
    
    // Vérifier si un appareil est configuré
    if (deviceIp == null || deviceIp.isEmpty) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('🕌 Pas d\'appareil AdhanBox détecté'),
              content: const Text(
                'Vous devez d\'abord ajouter un appareil AdhanBox avant de pouvoir configurer une mosquée.\n\n'
                'Souhaitez-vous configurer votre AdhanBox maintenant ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeviceSetupScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Configurer AdhanBox'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                ),
              ],
            );
          },
        );
      }
      return;
    }

    setState(() {
      _isConfiguring = true;
      _error = null;
    });

    try {
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏳ Synchronisation en cours...'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
          }
          
          final syncResponse = await http
              .post(
                Uri.parse('http://$deviceIp/api/mawaqit/sync'),
              )
              .timeout(const Duration(seconds: 90));

          if (syncResponse.statusCode == 200) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Horaires Mawaqit synchronisés avec succès!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            
            // Attendre que l'ESP32 enregistre les données
            await Future.delayed(const Duration(seconds: 3));
          } else {
            throw Exception('Sync HTTP ${syncResponse.statusCode}');
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ Erreur synchronisation: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }

        // Invalidate cache providers to refresh data
        // Important: invalider aussi mawaqitTimesProvider et deviceStatusProvider
        ref.invalidate(prayerTimesProvider);
        ref.invalidate(mawaqitComparisonProvider);
        ref.invalidate(mawaqitTimesProvider);
        ref.invalidate(deviceStatusProvider);

        // Attendre que les providers se rechargent
        await Future.delayed(const Duration(seconds: 2));
        
        // Force reload des prayer times
        try {
          await ref.refresh(prayerTimesProvider.future);
        } catch (_) {}

        if (mounted) {
          // Proposer l'ajustement des horaires
          final shouldAdjust = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.tune, color: Color(0xFF2E7D32)),
                    SizedBox(width: 12),
                    Text('Ajuster les horaires?'),
                  ],
                ),
                content: const Text(
                  'Voulez-vous ajuster finement les horaires pour qu\'ils correspondent exactement aux horaires de votre mosquée locale?\n\n'
                  'Vous pourrez modifier chaque prière de ±30 minutes.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Plus tard'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    icon: const Icon(Icons.tune),
                    label: const Text('Ajuster maintenant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              );
            },
          );

          if (shouldAdjust == true && mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const MawaqitOffsetsScreen(),
              ),
            );
          } else {
            Navigator.of(context).pop();
          }
        }
      } else {
        String message = 'Erreur de configuration (HTTP ${response.statusCode})';
        final raw = response.body.trim();
        if (raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map && decoded['error'] != null) {
              message = decoded['error'].toString();
            } else {
              message = raw;
            }
          } catch (_) {
            message = raw;
          }
        }
        throw Exception(message);
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

            // Recherche: Deux options - Manuelle ou Automatique
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🕌 Trouver une mosquée',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Option 1: Recherche manuelle
                    const Text(
                      'Option 1: Recherche par ville ou code postal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _mosqueSearchController,
                      decoration: InputDecoration(
                        hintText: 'Ex: Paris, 75005, Marseille...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabled: !_isSearching,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isSearching 
                        ? null 
                        : _searchMosquesByCity,
                      icon: const Icon(Icons.location_city),
                      label: const Text('Rechercher par ville'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),
                    
                    // Option 2: Géolocalisation automatique
                    const Text(
                      'Option 2: Géolocalisation automatique',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Permet de trouver les mosquées les plus proches de vous',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isSearching 
                        ? null 
                        : _autoDetectAndConfigure,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Détecter ma position'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🧮 Si aucune mosquée n\'est trouvée',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Utiliser les horaires calculés localement.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _selectedCalcMethod,
                      decoration: const InputDecoration(
                        labelText: 'Méthode de calcul',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      isExpanded: true,
                      items: _calcMethodLabels.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isConfiguring
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedCalcMethod = value;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _isConfiguring ? null : _configureCalculatedFallback,
                      icon: const Icon(Icons.calculate, size: 18),
                      label: const Text(
                        'Utiliser horaires calculés',
                        style: TextStyle(fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
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
