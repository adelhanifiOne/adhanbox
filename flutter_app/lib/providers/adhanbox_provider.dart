// lib/providers/adhanbox_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/adhanbox_api.dart';
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

// Provider pour sauvegarder l'IP du device
Future<void> saveDeviceIp(WidgetRef ref, String ip) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('deviceIp', ip);
  ref.read(currentDeviceIpProvider.notifier).state = ip;
  ref.invalidate(deviceIpProvider);
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
