import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Représente un appareil ESP32 découvert
class DiscoveredDevice {
  final String name;
  final String host;
  final int port;
  final String? type;

  DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    this.type,
  });

  String get fullUrl => 'http://$host:$port';

  @override
  String toString() => '$name ($host:$port)';
}

/// Service pour découvrir l'ESP32 sur le réseau local
class ESP32DiscoveryService {
  final List<DiscoveredDevice> _devices = [];

  /// Démarre la découverte mDNS pour trouver l'ESP32
  /// Type de service typique: "_http._tcp" ou "_adhanbox._tcp"
  /// Note: mDNS désactivé, utilise scan réseau uniquement
  Future<List<DiscoveredDevice>> discoverDevices({
    String serviceType = '_http._tcp',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    print('Lancement du scan réseau local...');
    _devices.clear();

    try {
      // Vérifie la connectivité réseau
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        print('Pas de connexion réseau');
        return [];
      }

      // Scan le sous-réseau local
      final subnet = await getLocalSubnet();
      if (subnet == null) {
        print('Impossible de déterminer le sous-réseau');
        return [];
      }

      final hosts = await scanLocalNetwork(subnet: subnet);
      return hosts.map((host) => DiscoveredDevice(
        name: 'ESP32',
        host: host,
        port: 80,
      )).toList();
    } catch (e) {
      print('Erreur lors de la découverte: $e');
      return [];
    }
  }

  /// Arrête la découverte
  Future<void> stopDiscovery() async {
    // Rien à faire pour le scan réseau
  }

  /// Découvre l'ESP32 AdhanBox spécifiquement
  Future<DiscoveredDevice?> findAdhanBox({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final devices = await discoverDevices(
      serviceType: '_http._tcp',
      timeout: timeout,
    );

    if (devices.isEmpty) {
      return null;
    }

    // Retourne le premier AdhanBox trouvé
    return devices.first;
  }

  /// Scan le sous-réseau local pour trouver l'ESP32
  /// Méthode de fallback si mDNS ne fonctionne pas
  Future<List<String>> scanLocalNetwork({
    String subnet = '192.168.1',
    int startRange = 1,
    int endRange = 254,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final List<String> activeHosts = [];
    final List<Future<void>> futures = [];

    for (int i = startRange; i <= endRange; i++) {
      final host = '$subnet.$i';
      
      futures.add(
        _checkHost(host, 80, timeout).then((isActive) {
          if (isActive) {
            activeHosts.add(host);
          }
        }),
      );

      // Limite à 50 requêtes simultanées pour ne pas surcharger
      if (futures.length >= 50) {
        await Future.wait(futures);
        futures.clear();
      }
    }

    // Attend les dernières requêtes
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    return activeHosts;
  }

  /// Vérifie si un host est accessible
  Future<bool> _checkHost(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Obtient l'IP locale de l'appareil
  Future<String?> getLocalIp() async {
    if (kIsWeb) {
      return null; // Pas disponible sur web
    }
    
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // Cherche les IP locales (192.168.x.x ou 10.x.x.x)
          if (addr.address.startsWith('192.168.') || 
              addr.address.startsWith('10.')) {
            return addr.address;
          }
        }
      }
      return null;
    } catch (e) {
      print('Erreur lors de la récupération de l\'IP locale: $e');
      return null;
    }
  }

  /// Obtient le sous-réseau local (ex: "192.168.1")
  Future<String?> getLocalSubnet() async {
    final ip = await getLocalIp();
    if (ip == null) return null;

    final parts = ip.split('.');
    if (parts.length != 4) return null;

    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }
}

/// Provider pour le service de découverte ESP32
final esp32DiscoveryServiceProvider = Provider<ESP32DiscoveryService>((ref) {
  return ESP32DiscoveryService();
});

/// Provider pour découvrir l'AdhanBox
final adhanBoxDiscoveryProvider = FutureProvider<DiscoveredDevice?>((ref) async {
  final service = ref.watch(esp32DiscoveryServiceProvider);
  return await service.findAdhanBox();
});

/// État de la découverte avec notifier
class DiscoveryNotifier extends StateNotifier<List<DiscoveredDevice>> {
  DiscoveryNotifier(this.service) : super([]);

  final ESP32DiscoveryService service;
  bool isDiscovering = false;

  Future<void> discover() async {
    if (isDiscovering) return;
    
    isDiscovering = true;
    try {
      state = await service.discoverDevices();
    } finally {
      isDiscovering = false;
    }
  }

  Future<void> scanNetwork() async {
    if (isDiscovering) return;
    
    isDiscovering = true;
    try {
      final subnet = await service.getLocalSubnet();
      if (subnet == null) {
        state = [];
        return;
      }

      final hosts = await service.scanLocalNetwork(subnet: subnet);
      state = hosts.map((host) => DiscoveredDevice(
        name: 'Device',
        host: host,
        port: 80,
      )).toList();
    } finally {
      isDiscovering = false;
    }
  }

  void clear() {
    state = [];
  }
}

/// Provider pour gérer l'état de la découverte
final discoveryNotifierProvider = 
    StateNotifierProvider<DiscoveryNotifier, List<DiscoveredDevice>>((ref) {
  final service = ref.watch(esp32DiscoveryServiceProvider);
  return DiscoveryNotifier(service);
});
