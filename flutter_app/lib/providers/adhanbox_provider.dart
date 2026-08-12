// lib/providers/adhanbox_provider.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/adhanbox_api.dart';
import '../services/esp32_discovery_service.dart';
import '../services/local_prayer_times.dart';
import '../models/prayer_time.dart';

/// Stocke le token API récupéré depuis le device après la première connexion.
final adhanboxApiKeyProvider = StateProvider<String?>((ref) => null);

/// Provider pour l'instance API — inclut la clé d'auth si disponible.
final adhanboxApiProvider = Provider<AdhanBoxAPI?>((ref) {
  final deviceIp = ref.watch(currentDeviceIpProvider);
  final apiKey = ref.watch(adhanboxApiKeyProvider);
  return deviceIp != null
      ? AdhanBoxAPI(baseUrl: 'http://$deviceIp', apiKey: apiKey)
      : null;
});

class SavedDevice {
  final String name;
  final String ip;

  /// Identifiant materiel stable (MAC eFuse), expose par le firmware >= 1.4.9 /
  /// 2.3.30 / 3.0.3 via /api/device/info. C'est LUI qui identifie un boitier,
  /// pas son IP : sans ca, une box qui change d'IP (bail DHCP renouvele apres un
  /// redemarrage) apparaissait une seconde fois dans la liste.
  /// Null pour les entrees enregistrees avant cette version — elles sont
  /// completees automatiquement au premier contact avec l'appareil.
  final String? id;

  SavedDevice({required this.name, required this.ip, this.id});

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        if (id != null) 'id': id,
      };
  factory SavedDevice.fromJson(Map<String, dynamic> json) => SavedDevice(
        name: json['name'] as String,
        ip: json['ip'] as String,
        id: json['id'] as String?,
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

  // Helper: charger le token API depuis le device ou prefs, et l'activer
  Future<void> loadApiToken(String ip) async {
    String? token;
    try {
      final devApi = AdhanBoxAPI(baseUrl: 'http://$ip', timeout: const Duration(seconds: 3));
      final info = await devApi.getDeviceInfo();
      token = info['token'] as String?;
    } catch (_) {
      // device injoignable -> on tentera le cache ci-dessous
    }
    // Le firmware n'expose le token que pendant la fenetre d'appairage. Hors de
    // cette fenetre (usage normal) device/info ne renvoie plus de token : on
    // retombe alors sur le jeton mis en cache lors du 1er appairage. Sinon on
    // cache le nouveau jeton.
    if (token != null && token.isNotEmpty) {
      await prefs.setString('api_token_$ip', token);
    } else {
      token = prefs.getString('api_token_$ip');
    }
    if (token != null && token.isNotEmpty) {
      ref.read(adhanboxApiKeyProvider.notifier).state = token;
    }
  }

  // Helper: synchroniser l'heure du RTC après connexion
  Future<void> syncRtcTime(String ip) async {
    try {
      final token = prefs.getString('api_token_$ip');
      final api = AdhanBoxAPI(
        baseUrl: 'http://$ip',
        timeout: const Duration(seconds: 5),
        apiKey: token,
      );
      await api.setRtcTime(DateTime.now());
    } catch (_) {}
  }

  // Helper: rattacher l'identifiant materiel a l'entree enregistree et purger
  // les doublons fantomes laisses par d'anciens changements d'IP. Repare tout
  // seul les installations existantes, sans reappairage manuel.
  Future<void> reconcileIdentity(String ip) async {
    final id = await _fetchDeviceId(ip);
    if (id == null) return; // firmware anterieur : rien a faire

    final raw = prefs.getString('savedDevices');
    if (raw == null) return;
    List<SavedDevice> devices;
    try {
      devices = (jsonDecode(raw) as List)
          .map((e) => SavedDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return;
    }

    final before = jsonEncode(devices.map((e) => e.toJson()).toList());
    final index = devices.indexWhere((d) => d.ip == ip);
    if (index >= 0 && devices[index].id == null) {
      devices[index] = SavedDevice(
          name: devices[index].name, ip: ip, id: id);
    }
    for (final ghost in devices.where((d) => d.id == id && d.ip != ip)) {
      await prefs.remove('api_token_${ghost.ip}');
    }
    devices.removeWhere((d) => d.id == id && d.ip != ip);

    final after = jsonEncode(devices.map((e) => e.toJson()).toList());
    if (after != before) {
      await prefs.setString('savedDevices', after);
      ref.invalidate(savedDevicesProvider);
    }
  }

  // 1. Essayer l'IP sauvegardée D'ABORD
  if (savedIp != null && savedIp.isNotEmpty) {
    try {
      final api = AdhanBoxAPI(baseUrl: 'http://$savedIp', timeout: const Duration(seconds: 3));
      await api.getStatus().timeout(const Duration(seconds: 3));
      ref.read(currentDeviceIpProvider.notifier).state = savedIp;
      await loadApiToken(savedIp);
      await reconcileIdentity(savedIp);
      await syncRtcTime(savedIp);
      return savedIp;
    } catch (e) {
      if (kDebugMode) debugPrint('autoReconnect: $savedIp indisponible — $e');
      ref.read(currentDeviceIpProvider.notifier).state = savedIp;
      throw Exception('Appareil hors ligne');
    }
  }

  // 2. Tenter adhanbox.local par mDNS
  try {
    final api = AdhanBoxAPI(baseUrl: 'http://adhanbox.local', timeout: const Duration(seconds: 3));
    await api.getStatus().timeout(const Duration(seconds: 3));
    await prefs.setString('deviceIp', 'adhanbox.local');
    if (prefs.getString('savedDevices') == null) {
      await prefs.setString('savedDevices',
          jsonEncode([SavedDevice(name: 'AdhanBox', ip: 'adhanbox.local').toJson()]));
    }
    ref.read(currentDeviceIpProvider.notifier).state = 'adhanbox.local';
    await loadApiToken('adhanbox.local');
    await reconcileIdentity('adhanbox.local');
    await syncRtcTime('adhanbox.local');
    return 'adhanbox.local';
  } catch (_) {}

  // 3. Scan réseau en dernier recours
  try {
    final discovery = ESP32DiscoveryService();
    final device = await discovery
        .findAdhanBox(timeout: const Duration(seconds: 10))
        .timeout(const Duration(seconds: 12), onTimeout: () => null);
    if (device != null) {
      await prefs.setString('deviceIp', device.host);
      if (prefs.getString('savedDevices') == null) {
        await prefs.setString('savedDevices',
            jsonEncode([SavedDevice(name: 'AdhanBox', ip: device.host).toJson()]));
      }
      ref.read(currentDeviceIpProvider.notifier).state = device.host;
      await loadApiToken(device.host);
      await reconcileIdentity(device.host);
      await syncRtcTime(device.host);
      return device.host;
    }
  } catch (e) {
    if (kDebugMode) debugPrint('autoReconnect: scan échoué — $e');
  }

  return null;
});

/// Interroge l'appareil pour recuperer son identifiant materiel.
/// Renvoie null si l'appareil est injoignable ou tourne un firmware anterieur
/// a l'ajout de `device_id` — dans ce cas on retombe sur l'ancien comportement.
Future<String?> _fetchDeviceId(String ip) async {
  try {
    final info = await AdhanBoxAPI(
      baseUrl: 'http://$ip',
      timeout: const Duration(seconds: 3),
    ).getDeviceInfo();
    final id = info['device_id'] as String?;
    return (id != null && id.isNotEmpty) ? id : null;
  } catch (_) {
    return null;
  }
}

// Provider pour sauvegarder l'IP du device
Future<void> saveDeviceIp(WidgetRef ref, String ip,
    {String name = 'AdhanBox', String? id}) async {
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

  // L'identifiant materiel prime sur l'IP : c'est ce qui evite le doublon
  // fantome quand le routeur attribue une nouvelle adresse au meme boitier.
  id ??= await _fetchDeviceId(ip);
  int existingIndex = -1;
  if (id != null) existingIndex = devices.indexWhere((d) => d.id == id);
  existingIndex = existingIndex >= 0 ? existingIndex : devices.indexWhere((d) => d.ip == ip);

  if (existingIndex >= 0) {
    final previous = devices[existingIndex];
    // L'appareil a change d'adresse : le jeton API est indexe par IP, il faut
    // le deplacer sinon l'app perd l'authentification et redemande un appairage.
    if (previous.ip != ip) {
      final token = prefs.getString('api_token_${previous.ip}');
      if (token != null && token.isNotEmpty) {
        await prefs.setString('api_token_$ip', token);
      }
      await prefs.remove('api_token_${previous.ip}');
    }
    devices[existingIndex] =
        SavedDevice(name: name, ip: ip, id: id ?? previous.id);
  } else {
    devices.add(SavedDevice(name: name, ip: ip, id: id));
  }

  // Purge des doublons laisses par les changements d'IP anterieurs : meme
  // identifiant materiel => une seule entree, celle qui porte l'IP courante.
  if (id != null) {
    final ghosts = devices.where((d) => d.id == id && d.ip != ip).toList();
    for (final ghost in ghosts) {
      await prefs.remove('api_token_${ghost.ip}');
    }
    devices.removeWhere((d) => d.id == id && d.ip != ip);
  }

  await prefs.setString('savedDevices', jsonEncode(devices.map((e) => e.toJson()).toList()));
  await prefs.setString('deviceIp', ip);

  ref.read(currentDeviceIpProvider.notifier).state = ip;
  ref.invalidate(deviceIpProvider);
  ref.invalidate(savedDevicesProvider);
  ref.invalidate(autoReconnectProvider);
}

/// Bascule l'appareil actif vers [d] et charge SON token (cache puis rafraîchi).
Future<void> switchToDevice(WidgetRef ref, SavedDevice d) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('deviceIp', d.ip);
  ref.read(currentDeviceIpProvider.notifier).state = d.ip;
  // Token propre à CET appareil : cache d'abord, puis rafraîchi si joignable.
  ref.read(adhanboxApiKeyProvider.notifier).state = prefs.getString('api_token_${d.ip}');
  try {
    final info = await AdhanBoxAPI(baseUrl: 'http://${d.ip}', timeout: const Duration(seconds: 3))
        .getDeviceInfo();
    final t = info['token'] as String?;
    if (t != null && t.isNotEmpty) {
      await prefs.setString('api_token_${d.ip}', t);
      ref.read(adhanboxApiKeyProvider.notifier).state = t;
    }
  } catch (_) {}
  ref.invalidate(deviceIpProvider);
  ref.invalidate(savedDevicesProvider);
  ref.invalidate(autoReconnectProvider);
}

/// Retire un appareil de la liste (+ son token). Bascule si c'était l'actif.
Future<void> removeSavedDevice(WidgetRef ref, String ip) async {
  final prefs = await SharedPreferences.getInstance();
  List<SavedDevice> devices = [];
  final s = prefs.getString('savedDevices');
  if (s != null) {
    try {
      final List decoded = jsonDecode(s);
      devices = decoded.map((e) => SavedDevice.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}
  }
  devices.removeWhere((e) => e.ip == ip);
  await prefs.setString('savedDevices', jsonEncode(devices.map((e) => e.toJson()).toList()));
  await prefs.remove('api_token_$ip');
  if (ref.read(currentDeviceIpProvider) == ip) {
    if (devices.isNotEmpty) {
      await switchToDevice(ref, devices.first);
    } else {
      await prefs.remove('deviceIp');
      ref.read(currentDeviceIpProvider.notifier).state = null;
      ref.read(adhanboxApiKeyProvider.notifier).state = null;
    }
  }
  ref.invalidate(deviceIpProvider);
  ref.invalidate(savedDevicesProvider);
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

  // La box est la source de vérité quand elle répond : c'est elle qui déclenche
  // l'adhan, les heures affichées doivent être exactement celles qu'elle jouera.
  if (api != null) {
    try {
      return await api.getPrayerTimes();
    } catch (e) {
      // Box appairée mais injoignable (hors ligne, coupure de courant) : on
      // bascule sur le calcul local plutôt que de laisser l'écran vide.
      if (kDebugMode) debugPrint('prayerTimes: box injoignable, calcul local — $e');
    }
  }

  // Aucun appareil, ou appareil hors ligne : l'app calcule elle-même. Sans ça
  // l'application est entièrement inutilisable tant qu'aucune box n'est
  // appairée — cas de tout client entre la précommande et la livraison.
  return calculerHorairesLocaux();
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

// Provider pour récupérer la version locale de l'AdhanBox
final deviceFirmwareVersionProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) throw Exception('Aucun appareil connecté');
  try {
    return await api.getFirmwareVersion().timeout(const Duration(seconds: 4));
  } catch (e) {
    // La route /api/firmware/version a échoué. DEUX cas très différents :
    //  (a) box INJOIGNABLE (débranchée / hors réseau) -> il ne faut RIEN proposer :
    //      inventer une version ferait afficher "Ancienne version" et pousserait
    //      un firmware du mauvais canal (ex: 1.4.6 V1 sur une V2) = brique.
    //  (b) box legacy V1 réellement EN LIGNE mais sans cette route.
    // On tranche via un endpoint léger présent sur TOUTES les générations.
    try {
      await api.getStatus().timeout(const Duration(seconds: 3)); // ping universel
    } catch (_) {
      throw Exception('Appareil hors ligne'); // -> UI "hors ligne", aucun update
    }
    // Joignable mais sans la route version -> vrai firmware V1 legacy.
    return {
      'version': '1.0.0',
      'isLegacy': true,
    };
  }
});

// true si le device tourne un firmware V2 (>= 2.x) -> débloque les fonctions V2
// (upload de fichiers audio, etc.). false pour un device V1 (1.x) ou legacy.
final isV2DeviceProvider = FutureProvider<bool>((ref) async {
  try {
    final device = await ref.watch(deviceFirmwareVersionProvider.future);
    final hw = (device['hardware'] ?? '').toString();
    final major =
        int.tryParse((device['version'] ?? '1').toString().split('.').first) ?? 1;
    return hw == 'v2' || major >= 2;
  } catch (_) {
    return false; // device indisponible -> on considère V1 par sécurité
  }
});

// Provider pour récupérer la dernière version disponible en ligne, SUR LE BON
// CANAL selon le firmware du device :
//   - firmware 1.x -> canal V1 (firmware_version.json)
//   - firmware 2.x -> canal V2 (firmware_version_v2.json)
//   - firmware 3.x -> canal V3 (firmware_version_v3.json) — PCB V3 (RTC RX8025T)
// Comme chaque manifeste ne contient que sa propre lignée, un device 1.x ou 2.x
// ne se voit JAMAIS proposer un firmware 3.x (et inversement) : les cartes V2
// (DS3231) et V3 (RX8025T) ont des drivers RTC differents -> croiser les canaux
// casserait les alarmes de priere. Une seule app pour tous.
final latestFirmwareVersionProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  // 1) Choisir le canal d'après le firmware actuel du device.
  // IMPORTANT : si le device est injoignable, deviceFirmwareVersionProvider
  // lève désormais une erreur -> on la laisse remonter et on ne propose AUCUNE
  // mise à jour. On ne défausse PLUS sur le canal V1 : proposer un firmware d'un
  // autre canal (ex: 1.4.6) sur une box V2/V3 la briquerait.
  final device = await ref.watch(deviceFirmwareVersionProvider.future);
  final hw = (device['hardware'] ?? '').toString();
  final major =
      int.tryParse((device['version'] ?? '1.0.0').toString().split('.').first) ?? 1;
  String channel;
  if (hw == 'v3' || major >= 3) {
    channel = 'firmware_version_v3.json';
  } else if (hw == 'v2' || major == 2) {
    channel = 'firmware_version_v2.json';
  } else {
    channel = 'firmware_version.json'; // V1 (vrai legacy en ligne uniquement)
  }

  // 2) Lire le manifeste du canal correspondant
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final response = await http.get(Uri.parse(
      'https://raw.githubusercontent.com/adelhanifiOne/adhanbox/main/$channel?t=$timestamp'))
      .timeout(const Duration(seconds: 8));
  if (response.statusCode == 200) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
  throw Exception('Impossible de vérifier les mises à jour');
});

/// Nom de la mosquée Mawaqit configurée (persisté localement).
/// Affiché sur la page Prière. Invalidé après reconfiguration.
const kMawaqitMosqueNameKey = 'mawaqit_mosque_name';

final configuredMosqueProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(kMawaqitMosqueNameKey);
  return (name != null && name.isNotEmpty) ? name : null;
});
