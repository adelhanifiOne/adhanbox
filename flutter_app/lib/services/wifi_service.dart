import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// Service pour gérer le WiFi
class WiFiService {
  /// Vérifie et demande les permissions WiFi
  Future<bool> checkAndRequestPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false; // WiFi scan not supported on this platform
    }

    // Sur Android 10+ (API 29+), la permission de localisation est requise pour scanner les WiFi
    var permission = await Permission.location.status;
    
    if (permission.isDenied) {
      permission = await Permission.location.request();
    }

    // Permission WiFi sur Android 13+ (API 33+)
    if (Platform.isAndroid) {
      var nearbyWifiPermission = await Permission.nearbyWifiDevices.status;
      if (nearbyWifiPermission.isDenied) {
        nearbyWifiPermission = await Permission.nearbyWifiDevices.request();
      }
    }

    if (permission.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return permission.isGranted;
  }

  /// Vérifie si le scan WiFi est disponible
  Future<bool> canScan() async {
    try {
      final can = await WiFiScan.instance.canStartScan();
      return can == CanStartScan.yes;
    } catch (e) {
      print('Erreur lors de la vérification du scan WiFi: $e');
      return false;
    }
  }

  /// Lance un scan des réseaux WiFi disponibles
  Future<List<WiFiAccessPoint>> scanNetworks() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return [];
      }

      final canScan = await this.canScan();
      if (!canScan) {
        print('Le scan WiFi n\'est pas disponible');
        return [];
      }

      // Lance le scan
      await WiFiScan.instance.startScan();

      // Attends un peu pour que le scan se termine
      await Future.delayed(const Duration(seconds: 2));

      // Récupère les résultats
      final results = await WiFiScan.instance.getScannedResults();
      return results;
    } catch (e) {
      print('Erreur lors du scan WiFi: $e');
      return [];
    }
  }

  /// Obtient les réseaux WiFi disponibles (avec cache)
  Future<List<WiFiAccessPoint>> getAvailableNetworks() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return [];
      }

      final results = await WiFiScan.instance.getScannedResults();
      return results;
    } catch (e) {
      print('Erreur lors de la récupération des réseaux WiFi: $e');
      return [];
    }
  }

  /// Formate l'intensité du signal (RSSI) en pourcentage
  int signalStrengthPercent(int rssi) {
    // RSSI typique: -100 dBm (faible) à -50 dBm (fort)
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100);
  }

  /// Obtient une icône selon l'intensité du signal
  String getSignalIcon(int rssi) {
    final strength = signalStrengthPercent(rssi);
    if (strength >= 75) return '📶'; // Excellent
    if (strength >= 50) return '📶'; // Bon
    if (strength >= 25) return '📶'; // Moyen
    return '📶'; // Faible
  }
}

/// Provider pour le service WiFi
final wifiServiceProvider = Provider<WiFiService>((ref) {
  return WiFiService();
});

/// Provider pour la liste des réseaux WiFi disponibles
final availableNetworksProvider = FutureProvider<List<WiFiAccessPoint>>((ref) async {
  final service = ref.watch(wifiServiceProvider);
  return await service.scanNetworks();
});

/// État des réseaux WiFi avec notifier
class WiFiNetworksNotifier extends StateNotifier<List<WiFiAccessPoint>> {
  WiFiNetworksNotifier(this.service) : super([]);

  final WiFiService service;
  bool isScanning = false;

  Future<void> scan() async {
    if (isScanning) return;
    
    isScanning = true;
    try {
      state = await service.scanNetworks();
    } finally {
      isScanning = false;
    }
  }

  Future<void> refresh() async {
    state = await service.getAvailableNetworks();
  }
}

/// Provider pour gérer l'état des réseaux WiFi
final wifiNetworksNotifierProvider = 
    StateNotifierProvider<WiFiNetworksNotifier, List<WiFiAccessPoint>>((ref) {
  final service = ref.watch(wifiServiceProvider);
  return WiFiNetworksNotifier(service);
});
