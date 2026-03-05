// lib/providers/adhanbox_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/adhanbox_api.dart';
import '../services/esp32_discovery_service.dart';
import '../models/prayer_time.dart';

// Provider pour l'instance API
final adhanboxApiProvider = Provider<AdhanBoxAPI?>((ref) {
  final deviceIp = ref.watch(currentDeviceIpProvider);
  return deviceIp != null ? AdhanBoxAPI(baseUrl: 'http://$deviceIp') : null;
});

// Provider pour l'IP du device (persisté dans SharedPreferences)
final deviceIpProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('deviceIp'); // Retourne null si pas encore configuré
});

// Provider modifiable pour l'IP du device (current session)
final currentDeviceIpProvider = StateProvider<String?>((ref) {
  // Initialisé à null, sera mis à jour après lecture de SharedPreferences
  return null;
});

// Provider pour la reconnexion automatique au démarrage
final autoReconnectProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  
  // 1. Essayer d'abord adhanbox.local (mDNS)
  print('DEBUG: Tentative de connexion via mDNS (adhanbox.local)...');
  try {
    final api = AdhanBoxAPI(baseUrl: 'http://adhanbox.local', timeout: const Duration(seconds: 3));
    await api.getStatus().timeout(const Duration(seconds: 3));
    print('DEBUG: ✓ ESP32 accessible via adhanbox.local');
    await prefs.setString('deviceIp', 'adhanbox.local');
    ref.read(currentDeviceIpProvider.notifier).state = 'adhanbox.local';
    return 'adhanbox.local';
  } catch (e) {
    print('DEBUG: ✗ mDNS échoué: $e');
  }

  // 2. Essayer l'IP sauvegardée
  var savedIp = prefs.getString('deviceIp');
  if (savedIp != null && savedIp != 'adhanbox.local') {
    print('DEBUG: Tentative de connexion à IP sauvegardée: $savedIp');
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://$savedIp', timeout: const Duration(seconds: 3));
      await api.getStatus().timeout(const Duration(seconds: 3));
      print('DEBUG: ✓ ESP32 accessible à $savedIp');
      ref.read(currentDeviceIpProvider.notifier).state = savedIp;
      return savedIp;
    } catch (e) {
      print('DEBUG: ✗ IP sauvegardée échouée: $e');
    }
  }

  // 3. Scanner le réseau local
  print('DEBUG: Lancement de la découverte réseau...');
  try {
    final discovery = ESP32DiscoveryService();
    final device = await discovery.findAdhanBox(timeout: const Duration(seconds: 3)).timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );

    if (device != null) {
      print('DEBUG: ✓ ESP32 trouvé à ${device.host}');
      await prefs.setString('deviceIp', device.host);
      ref.read(currentDeviceIpProvider.notifier).state = device.host;
      return device.host;
    }
  } catch (e) {
    print('DEBUG: ✗ Découverte réseau échouée: $e');
  }

  // 4. Échec - aucune connexion possible
  print('DEBUG: ✗ Impossible de trouver l\'ESP32 automatiquement');
  return null;
});

// Provider pour sauvegarder l'IP du device
Future<void> saveDeviceIp(WidgetRef ref, String ip) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('deviceIp', ip);
  ref.read(currentDeviceIpProvider.notifier).state = ip;
  ref.invalidate(deviceIpProvider);
  ref.invalidate(autoReconnectProvider);
}

// Provider pour le statut du device
final deviceStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getStatus();
});

// Provider pour l'heure actuelle
final deviceTimeProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getTime();
});

// Provider pour les horaires de prière
final prayerTimesProvider = FutureProvider<PrayerTimes>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getPrayerTimes();
});

// Provider pour les offsets de fine-tuning
final prayerOffsetsProvider = FutureProvider<Map<String, int>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) return {};
  try {
    final response = await api.getOffsets();
    return {
      'fajr': response['fajr'] as int? ?? 0,
      'sunrise': response['sunrise'] as int? ?? 0,
      'dhuhr': response['dhuhr'] as int? ?? 0,
      'asr': response['asr'] as int? ?? 0,
      'maghrib': response['maghrib'] as int? ?? 0,
      'isha': response['isha'] as int? ?? 0,
    };
  } catch (e) {
    debugPrint('Error loading prayer offsets: $e');
    return {};
  }
});

// Provider pour les horaires avec offsets appliqués
final adjustedPrayerTimesProvider = FutureProvider<PrayerTimes>((ref) async {
  final prayerTimes = await ref.watch(prayerTimesProvider.future);
  final offsets = await ref.watch(prayerOffsetsProvider.future);
  
  // Appliquer les offsets
  return prayerTimes.applyOffsets(offsets);
});

// Provider pour les horaires Mawaqit
final mawaqitTimesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getMawaqitTimes();
});

// Provider pour la comparaison
final mawaqitComparisonProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getMawaqitComparison();
});

// Provider pour la localisation
final locationProvider = StateProvider<Map<String, dynamic>>((ref) {
  return {'lat': 0.0, 'lon': 0.0};
});

// Provider pour le fuseau horaire
final timezoneProvider = StateProvider<int>((ref) {
  return 0; // UTC
});

// Provider pour l'état LED
final ledStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getLedStatus();
});

// Provider pour le scénario LED
final ledScenarioProvider = StateProvider<int>((ref) {
  return 8; // Dynamic hue
});

// Provider pour le volume audio
final volumeProvider = StateProvider<int>((ref) {
  return 20; // 0-30
});

// Provider pour l'état WiFi
final wifiStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.getWiFiStatus();
});

// Provider pour scanner WiFi
final wifiScanProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil configuré');
  return api.scanWiFiNetworks();
});

// Provider pour la localisation stockée
final storedLocationProvider = StateProvider<Map<String, dynamic>?>(
  (ref) => null,
);

// Provider pour forcer le refresh
final refreshControllerProvider = StateProvider<int>((ref) => 0);

// Helpers pour rafraîchir les données
class RefreshController {
  static Future<void> refreshAll(WidgetRef ref) async {
    ref.invalidate(deviceStatusProvider);
    ref.invalidate(deviceTimeProvider);
    ref.invalidate(prayerTimesProvider);
    ref.invalidate(mawaqitTimesProvider);
    ref.invalidate(mawaqitComparisonProvider);
    ref.invalidate(ledStatusProvider);
    ref.invalidate(wifiStatusProvider);
  }

  static Future<void> refreshPrayerTimes(WidgetRef ref) async {
    ref.invalidate(prayerTimesProvider);
    ref.invalidate(mawaqitTimesProvider);
    ref.invalidate(mawaqitComparisonProvider);
  }
}

// Provider pour la localisation du téléphone (via geolocator)
final phoneLocationProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // À implémenter avec geolocator package
  return {'lat': 0.0, 'lon': 0.0};
});

// Provider pour les paramètres persistés
final prefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});
