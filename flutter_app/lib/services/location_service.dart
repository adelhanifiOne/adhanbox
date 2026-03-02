import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service pour gérer la localisation GPS
class LocationService {
  /// Vérifie et demande les permissions de localisation
  Future<bool> checkAndRequestPermission() async {
    // Vérifie si les services de localisation sont activés
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // Vérifie les permissions
    var permission = await Permission.location.status;
    
    if (permission.isDenied) {
      permission = await Permission.location.request();
    }

    if (permission.isPermanentlyDenied) {
      // Ouvre les paramètres pour que l'utilisateur active manuellement
      await openAppSettings();
      return false;
    }

    return permission.isGranted;
  }

  /// Obtient la position actuelle
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('Erreur lors de la récupération de la position: $e');
      return null;
    }
  }

  /// Obtient la dernière position connue
  Future<Position?> getLastKnownLocation() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      print('Erreur lors de la récupération de la dernière position: $e');
      return null;
    }
  }

  /// Convertit la position en format lisible
  String formatPosition(Position position) {
    return '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
  }
}

/// Provider pour le service de localisation
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Provider pour la position actuelle
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final service = ref.watch(locationServiceProvider);
  return await service.getCurrentLocation();
});

/// État de la localisation avec notifier
class LocationNotifier extends StateNotifier<Position?> {
  LocationNotifier(this.service) : super(null);

  final LocationService service;

  Future<void> updateLocation() async {
    state = await service.getCurrentLocation();
  }

  Future<void> loadLastKnown() async {
    state = await service.getLastKnownLocation();
  }
}

/// Provider pour gérer l'état de la position
final locationNotifierProvider = StateNotifierProvider<LocationNotifier, Position?>((ref) {
  final service = ref.watch(locationServiceProvider);
  return LocationNotifier(service);
});
