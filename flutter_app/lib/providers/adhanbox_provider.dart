// lib/providers/adhanbox_provider.dart

import 'dart:convert';
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

class SavedDevice {
  final String name;
  final String ip;
  SavedDevice({required this.name, required this.ip});
  
  Map<String, dynamic> toJson() => {'name': name, 'ip': ip};
  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
        name: json['name'] as String, 
        ip: json['ip'] as String
      );
}

final savedDevicesProvider = FutureProvider<List<SavedDevice>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final listString = prefs.getString('savedDevices');
  if (listString != null) {
    try {
      final List decoded = jsonDecode(listString);
      return decoded.map((e) => SavedDevice.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}
  }
  
  // Migration backcompatibility
  final oldIp = prefs.getString('deviceIp');
  if (oldIp != null && oldIp.isNotEmpty) {
      final device = SavedDevice(name: 'AdhanBox', ip: oldIp);
      await prefs.setString('savedDevices', jsonEncode([device.toJson()]));
      return [device];
  }
  return [];
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
  final savedIp = prefs.getString('deviceIp');
  
  // Helper: synchroniser l'heure du RTC après connexion
  Future<void> syncRtcTime(String deviceIp) async {
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://$deviceIp', timeout: const Duration(seconds: 5));
      final now = DateTime.now();
      await api.setRtcTime(now);
      print('DEBUG: ✓ Heure RTC synchronisée automatiquement');
    } catch (e) {
      print('DEBUG: ✗ Échec sync RTC automatique: $e (peut être fait manuellement)');
    }
  }
  
  // 1. Essayer l'IP sauvegardée D'ABORD (Sinon on casse le mode multi-appareil)
  if (savedIp != null && savedIp.isNotEmpty) {
    print('DEBUG: Tentative de connexion à IP sélectionnée: $savedIp');
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://$savedIp', timeout: const Duration(seconds: 3));
      await api.getStatus().timeout(const Duration(seconds: 3));
      print('DEBUG: ✓ ESP32 accessible à $savedIp');
      ref.read(currentDeviceIpProvider.notifier).state = savedIp;
      await syncRtcTime(savedIp);
      return savedIp;
    } catch (e) {
      print('DEBUG: ✗ IP $savedIp indisponible: $e');
      // On conserve l'état sur l'IP pour éviter de rediriger vers l'écran d'accueil
      ref.read(currentDeviceIpProvider.notifier).state = savedIp;
      throw Exception('Appareil hors ligne');
    }
  }

  // 2. Si aucune IP n'est sélectionnée, tenter adhanbox.local par défaut
  print('DEBUG: Tentative de connexion via mDNS (adhanbox.local)...');
  try {
    final api = AdhanBoxAPI(baseUrl: 'http://adhanbox.local', timeout: const Duration(seconds: 3));
    await api.getStatus().timeout(const Duration(seconds: 3));
    print('DEBUG: ✓ ESP32 accessible via adhanbox.local');
    await prefs.setString('deviceIp', 'adhanbox.local');
    
    final currList = prefs.getString('savedDevices');
    if (currList == null) {
       final newDev = SavedDevice(name: 'AdhanBox', ip: 'adhanbox.local');
       await prefs.setString('savedDevices', jsonEncode([newDev.toJson()]));
    }
    
    ref.read(currentDeviceIpProvider.notifier).state = 'adhanbox.local';
    await syncRtcTime('adhanbox.local');
    return 'adhanbox.local';
  } catch (e) {
    print('DEBUG: ✗ mDNS échoué: $e');
  }

  // 3. Essayer scan réseau en dernier recours
  print('DEBUG: Recherche sur le réseau local...');
  try {
    final discovery = ESP32DiscoveryService();
    final device = await discovery.findAdhanBox(timeout: const Duration(seconds: 10)).timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );

    if (device != null) {
      print('DEBUG: ✓ ESP32 trouvé à ${device.host}');
      await prefs.setString('deviceIp', device.host);
      
      final listStr = prefs.getString('savedDevices');
      if (listStr == null) {
          final d = SavedDevice(name: 'AdhanBox', ip: device.host);
          await prefs.setString('savedDevices', jsonEncode([d.toJson()]));
      }
      
      ref.read(currentDeviceIpProvider.notifier).state = device.host;
      await syncRtcTime(device.host);
      return device.host;
    }
  } catch (e) {
    print('DEBUG: ✗ Découverte réseau échouée: $e');
  }

  return null;
});

// Provider pour sauvegarder l'IP du device
Future<void> saveDeviceIp(WidgetRef ref, String ip, {String name = 'AdhanBox'}) async {
  final prefs = await SharedPreferences.getInstance();
  
  List<SavedDevice> devices = [];
  final listString = prefs.getString('savedDevices');
  if (listString != null) {
    try {
      final List decoded = jsonDecode(listString);
      devices = decoded.map((e) => SavedDevice.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}
  } else {
    // Migration: si c'est la toute première sauvegarde et qu'on avait une IP, on la garde.
    final oldIp = prefs.getString('deviceIp');
    if (oldIp != null && oldIp.isNotEmpty) {
      devices.add(SavedDevice(name: 'AdhanBox (Ancien)', ip: oldIp));
    }
  }
  
  final existingIndex = devices.indexWhere((d) => d.ip == ip);
  if (existingIndex >= 0) {
    devices[existingIndex] = SavedDevice(name: name, ip: ip);
  } else {
    devices.add(SavedDevice(name: name, ip: ip));
  }
  await prefs.setString('savedDevices', jsonEncode(devices.map((e) => e.toJson()).toList()));
  await prefs.setString('deviceIp', ip);
  
  ref.read(currentDeviceIpProvider.notifier).state = ip;
  ref.invalidate(deviceIpProvider);
  ref.invalidate(savedDevicesProvider);
  ref.invalidate(autoReconnectProvider);
}

Future<void> removeSavedDevice(WidgetRef ref, String ip) async {
  final prefs = await SharedPreferences.getInstance();
  final listString = prefs.getString('savedDevices');
  if (listString != null) {
    try {
      final List decoded = jsonDecode(listString);
      List<SavedDevice> devices = decoded.map((e) => SavedDevice.fromJson(e as Map<String, dynamic>)).toList();
      devices.removeWhere((d) => d.ip == ip);
      await prefs.setString('savedDevices', jsonEncode(devices.map((e) => e.toJson()).toList()));
      
      final currentIp = prefs.getString('deviceIp');
      if (currentIp == ip) {
          if (devices.isNotEmpty) {
             final newIp = devices.first.ip;
             await prefs.setString('deviceIp', newIp);
             ref.read(currentDeviceIpProvider.notifier).state = newIp;
          } else {
             await prefs.remove('deviceIp');
             ref.read(currentDeviceIpProvider.notifier).state = null;
          }
      }
      ref.invalidate(savedDevicesProvider);
      ref.invalidate(autoReconnectProvider);
    } catch (_) {}
  }
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

// Provider pour les horaires (les offsets sont déjà appliqués par le firmware)
final adjustedPrayerTimesProvider = FutureProvider<PrayerTimes>((ref) async {
  return await ref.watch(prayerTimesProvider.future);
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
