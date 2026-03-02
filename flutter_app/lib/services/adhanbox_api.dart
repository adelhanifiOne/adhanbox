// lib/services/adhanbox_api.dart

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../models/prayer_time.dart';

class AdhanBoxAPI {
  final String baseUrl;
  final Duration timeout;

  AdhanBoxAPI({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
  });

  // ===== STATUS =====
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/status')).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load status: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<Map<String, dynamic>> getTime() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/time')).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load time: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== PRAYER TIMES =====
  Future<PrayerTimes> getPrayerTimes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/prayer/times'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return PrayerTimes.fromJson(json);
      }
      throw Exception('Failed to load prayer times: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<List<PrayerTimes>> getPrayerTimesWeek() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/prayer/times/week'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final weekList = (json['week'] as List?) ?? [];
        return weekList
            .map((e) => PrayerTimes.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      throw Exception('Failed to load week times: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<Map<String, dynamic>> getPrayerConfig() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/prayer/config'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load prayer config: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setPrayerConfig(
      int prayerIndex, bool enabled, int track, bool duaaAfter) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/prayer/config'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'prayer_index': prayerIndex,
              'enabled': enabled,
              'track': track,
              'duaa_after': duaaAfter,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save prayer config: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> testPrayer(int prayerIndex, int track) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/prayer/test'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'prayer_index': prayerIndex,
              'track': track,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to test prayer: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== MAWAQIT =====
  Future<Map<String, dynamic>> getMawaqitTimes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/mawaqit/times'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 503) {
        throw Exception('WiFi not connected');
      }
      throw Exception('Failed to load Mawaqit times: ${response.statusCode}');
    } catch (e) {
      throw Exception('Mawaqit API Error: $e');
    }
  }

  Future<Map<String, dynamic>> getMawaqitComparison() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/mawaqit/comparison'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to compare times: ${response.statusCode}');
    } catch (e) {
      throw Exception('Comparison API Error: $e');
    }
  }

  Future<void> syncMawaqit() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/mawaqit/sync'))
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to sync Mawaqit: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Sync Error: $e');
    }
  }

  // ===== LOCATION =====
  Future<Map<String, dynamic>> getLocation() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/config/location'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load location: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setLocation(double lat, double lon, double accuracy) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/config/location'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lat': lat,
              'lon': lon,
              'accuracy': accuracy,
              'source': 'mobile',
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save location: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== TIMEZONE =====
  Future<Map<String, dynamic>> getTimezone() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/config/timezone'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load timezone: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setTimezone(int offsetMin) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/config/timezone'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'offset_min': offsetMin}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save timezone: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== LED =====
  Future<Map<String, dynamic>> getLedStatus() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/led/status')).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load LED status: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setLedScenario(int scenario) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/led/scenario'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'scenario': scenario}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to set LED scenario: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setLedBrightness(int brightness) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/led/brightness'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'brightness': brightness}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to set LED brightness: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== AUDIO =====
  Future<void> setAudioVolume(int volume) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/audio/volume'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'volume': volume}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to set audio volume: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== AUDIO =====
  Future<Map<String, dynamic>> getAudioStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/audio/status'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to load audio status: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setVolume(int level) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/audio/volume'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'level': level}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to set volume: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== WIFI =====
  Future<Map<String, dynamic>> getWiFiStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/wifi/status'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      // Fallback to global status endpoint
      final fallback = await http
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(timeout);
      if (fallback.statusCode == 200) {
        final data = jsonDecode(fallback.body) as Map<String, dynamic>;
        final wifi = data['wifi'] as Map<String, dynamic>? ?? {};
        return {
          'connected': wifi['connected'] == true,
          'ssid': wifi['ssid']?.toString() ?? '',
          'ip': wifi['ip']?.toString() ?? '',
          'signal': wifi['signal'] ?? 0,
        };
      }
      throw Exception('Failed to load WiFi status: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> scanWiFiNetworks() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/wifi/scan')).timeout(timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as List;
        return json.map((e) => e as Map<String, dynamic>).toList();
      }
      // Fallback to legacy endpoint
      final fallback =
          await http.get(Uri.parse('$baseUrl/scan_wifi')).timeout(timeout);
      if (fallback.statusCode == 200) {
        final json = jsonDecode(fallback.body) as List;
        return json
            .map((e) {
              final item = e as Map<String, dynamic>;
              return {
                'ssid': item['ssid']?.toString() ?? '',
                'rssi': item['rssi'] ?? 0,
                'secure': item['secure'] == 1 || item['secure'] == true,
              };
            })
            .toList();
      }
      throw Exception('Failed to scan networks: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  /// Scanner les réseaux WiFi disponibles (visibles par l'ESP32)
  Future<Map<String, dynamic>> scanWifiNetworks() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/wifi/scan'))
          .timeout(const Duration(seconds: 15)); // Scan prend du temps

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to scan WiFi networks: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> connectWiFi(String ssid, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/wifi/connect'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ssid': ssid, 'password': password}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        // Fallback to legacy endpoint
        final fallback = await http
            .post(
              Uri.parse('$baseUrl/connect_wifi'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'ssid': ssid, 'pass': password}),
            )
            .timeout(const Duration(seconds: 30));

        if (fallback.statusCode != 200) {
          throw Exception('Failed to connect WiFi: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }
}
