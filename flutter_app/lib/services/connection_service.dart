import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import './adhanbox_api.dart';
import '../providers/adhanbox_provider.dart';

/// État de connexion à l'ESP32
enum ConnectionStatus {
  connected,
  disconnected,
  checking,
  error,
}

/// Résultat du test de connexion
class ESP32ConnectionState {
  final ConnectionStatus status;
  final String? message;
  final DateTime? lastCheck;

  ESP32ConnectionState({
    required this.status,
    this.message,
    this.lastCheck,
  });

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isChecking => status == ConnectionStatus.checking;

  ESP32ConnectionState copyWith({
    ConnectionStatus? status,
    String? message,
    DateTime? lastCheck,
  }) {
    return ESP32ConnectionState(
      status: status ?? this.status,
      message: message ?? this.message,
      lastCheck: lastCheck ?? this.lastCheck,
    );
  }
}

/// Service pour tester la connexion à l'ESP32
class ConnectionService {
  final AdhanBoxAPI api;
  Timer? _periodicTimer;

  ConnectionService(this.api);

  /// Teste si l'ESP32 est accessible
  Future<ESP32ConnectionState> checkConnection() async {
    try {
      // Vérifie d'abord la connectivité réseau
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        return ESP32ConnectionState(
          status: ConnectionStatus.disconnected,
          message: 'Pas de connexion réseau',
          lastCheck: DateTime.now(),
        );
      }

      // Essaye de contacter l'API status avec timeout court
      await api.getStatus();

      return ESP32ConnectionState(
        status: ConnectionStatus.connected,
        message: 'Connecté à l\'ESP32',
        lastCheck: DateTime.now(),
      );
    } catch (e) {
      return ESP32ConnectionState(
        status: ConnectionStatus.error,
        message: 'Impossible de joindre l\'ESP32: ${e.toString().substring(0, 50)}',
        lastCheck: DateTime.now(),
      );
    }
  }

  /// Démarre un test périodique de connexion
  Stream<ESP32ConnectionState> startPeriodicCheck({
    Duration interval = const Duration(seconds: 30),
  }) async* {
    // Premier check immédiat
    yield ESP32ConnectionState(status: ConnectionStatus.checking);
    yield await checkConnection();

    // Checks périodiques
    _periodicTimer = Timer.periodic(interval, (_) {});
    
    await for (final _ in Stream.periodic(interval)) {
      yield ESP32ConnectionState(status: ConnectionStatus.checking);
      yield await checkConnection();
    }
  }

  /// Arrête les tests périodiques
  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void dispose() {
    stopPeriodicCheck();
  }
}

/// Notifier pour gérer l'état de connexion
class ConnectionNotifier extends StateNotifier<ESP32ConnectionState> {
  ConnectionNotifier(this.service) : super(
    ESP32ConnectionState(status: ConnectionStatus.checking)
  ) {
    // Lance un check initial
    checkNow();
  }

  final ConnectionService service;
  Timer? _timer;

  /// Lance un check immédiat
  Future<void> checkNow() async {
    if (!mounted) return;
    state = ESP32ConnectionState(status: ConnectionStatus.checking);
    final result = await service.checkConnection();
    if (!mounted) return;
    state = result;
  }

  /// Démarre les checks périodiques (toutes les 30 secondes)
  void startPeriodicChecks() {
    stopPeriodicChecks();
    
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final result = await service.checkConnection();
      if (!mounted) return;
      state = result;
    });
  }

  /// Arrête les checks périodiques
  void stopPeriodicChecks() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stopPeriodicChecks();
    service.dispose();
    super.dispose();
  }
}

/// Provider pour le service de connexion
final connectionServiceProvider = Provider.family<ConnectionService, AdhanBoxAPI>((ref, api) {
  return ConnectionService(api);
});

/// Provider pour l'état de connexion
final connectionStateProvider = StateNotifierProvider<ConnectionNotifier, ESP32ConnectionState>((ref) {
  final api = ref.watch(adhanboxApiProvider);
  if (api == null) {
    return ConnectionNotifier(ConnectionService(AdhanBoxAPI(baseUrl: 'http://localhost')));
  }
  final service = ConnectionService(api);
  final notifier = ConnectionNotifier(service);
  
  // Lance les checks périodiques
  notifier.startPeriodicChecks();
  
  return notifier;
});
