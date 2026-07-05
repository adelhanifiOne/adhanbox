// lib/services/adhanbox_api.dart

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../models/prayer_time.dart';

class AdhanBoxAPI {
  final String baseUrl;
  final Duration timeout;
  final String? apiKey;

  AdhanBoxAPI({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
    this.apiKey,
  });

  /// Headers for mutating (POST/PUT) requests — includes API key when set.
  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (apiKey != null && apiKey!.isNotEmpty) 'X-API-Key': apiKey!,
  };

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  // ===== STATUS =====
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/dump_status')).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('HTTP ${response.statusCode}');
    } on SocketException {
      throw Exception('Erreur réseau: Impossible de joindre $baseUrl');
    } on TimeoutException {
      throw Exception('Timeout: L\'ESP32 à $baseUrl ne répond pas');
    } catch (e) {
      throw Exception('Erreur API: $e');
    }
  }

  Future<Map<String, dynamic>> getTime() async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/time')).timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = _asMap(decoded);
        if (map != null) return map;
      }

      // Fallback firmware endpoint: plain text rtc string
      final fallback = await http.get(Uri.parse('$baseUrl/rtc_time')).timeout(timeout);
      if (fallback.statusCode == 200) {
        return {
          'time': fallback.body.trim(),
          'source': 'rtc_time',
        };
      }

      throw Exception('Failed to load time: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // ===== PRAYER TIMES =====
  Future<PrayerTimes> getPrayerTimes() async {
    try {
      // Use firmware endpoint directly: /prayer_times (top-level fajr/dhuhr/...)
      final response = await http
          .get(Uri.parse('$baseUrl/prayer_times'))
          .timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = _asMap(decoded);
        if (map == null) throw const FormatException('Invalid JSON: expected object');
        final normalized = {
          'times': {
            'fajr': map['fajr']?.toString() ?? '--:--',
            'dhuhr': map['dhuhr']?.toString() ?? '--:--',
            'asr': map['asr']?.toString() ?? '--:--',
            'maghreb': (map['maghreb'] ?? map['maghrib'])?.toString() ?? '--:--',
            'isha': map['isha']?.toString() ?? '--:--',
          },
          'next_index': map['next_index'],
          'date': DateTime.now().toIso8601String().split('T').first,
        };
        return PrayerTimes.fromJson(normalized);
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
            headers: _authHeaders,
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
            headers: _authHeaders,
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

  Future<void> stopAudio() async {
    try {
      await http.get(Uri.parse('$baseUrl/stopplay')).timeout(timeout);
    } catch (_) {}
  }

  /// Joue un fichier par chemin (Coran, azkar…) via /api/audio/play?f=...
  /// Endpoint protege -> on envoie le token en header X-API-Key.
  Future<void> playFile(String path, {int? volume}) async {
    final q = <String, String>{'f': path, if (volume != null) 'volume': '$volume'};
    final uri = Uri.parse('$baseUrl/api/audio/play').replace(queryParameters: q);
    final headers = <String, String>{
      if (apiKey != null && apiKey!.isNotEmpty) 'X-API-Key': apiKey!,
    };
    final r = await http.get(uri, headers: headers).timeout(timeout);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  }

  // ===== MAWAQIT =====
  Future<Map<String, dynamic>> getMawaqitTimes() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/mawaqit/times'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = _asMap(decoded);
        if (map != null) return map;
      } else if (response.statusCode == 503) {
        throw Exception('WiFi not connected');
      }

      // Firmware fallback: no dedicated mawaqit endpoint yet.
      // Return empty payload instead of hard failure to keep UI usable.
      return {
        'available': false,
        'reason': 'mawaqit endpoint not implemented on firmware',
      };
    } catch (e) {
      return {
        'available': false,
        'reason': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getMawaqitComparison() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/mawaqit/comparison'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = _asMap(decoded);
        if (map != null) return map;
      }

      return {
        'available': false,
        'reason': 'comparison endpoint not implemented on firmware',
      };
    } catch (e) {
      return {
        'available': false,
        'reason': e.toString(),
      };
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

  Future<Map<String, dynamic>> getCalculationConfig() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/calculation/config'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = _asMap(decoded);
        if (map != null) return map;
      }
      throw Exception('Failed to load calculation config: ${response.statusCode}');
    } catch (e) {
      throw Exception('Calculation Config Error: $e');
    }
  }

  Future<void> setCalculationConfig({
    required String method,
    double? fajrAngle,
    double? ishaAngle,
  }) async {
    try {
      final payload = <String, dynamic>{'method': method};
      if (fajrAngle != null) payload['fajr_angle'] = fajrAngle;
      if (ishaAngle != null) payload['isha_angle'] = ishaAngle;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/calculation/config'),
            headers: _authHeaders,
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save calculation config: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Calculation Config Error: $e');
    }
  }

  // ===== PRAYER OFFSETS (Fine-tuning) =====
  Future<Map<String, dynamic>> getOffsets() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/mawaqit/offsets'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final map = _asMap(decoded);
        if (map != null) return map;
      }
      throw Exception('Failed to load offsets: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error loading offsets: $e');
      // Return default offsets (all 0) on error
      return {
        'fajr': 0,
        'sunrise': 0,
        'dhuhr': 0,
        'asr': 0,
        'maghrib': 0,
        'isha': 0,
      };
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
            Uri.parse('$baseUrl/set_location'),
            headers: _authHeaders,
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
            Uri.parse('$baseUrl/set_tz'),
            headers: _authHeaders,
            body: jsonEncode({'tz_min': offsetMin}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save timezone: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  /// Synchronise l'heure du RTC avec l'heure du smartphone
  Future<void> setRtcTime(DateTime dateTime) async {
    try {
      final dateStr = '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
      final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
      
      final response = await http
          .post(
            Uri.parse('$baseUrl/set_rtc_manual'),
            headers: _authHeaders,
            body: jsonEncode({
              'date': dateStr,
              'time': timeStr,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to set RTC time: ${response.statusCode}');
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
            headers: _authHeaders,
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

  /// Couleur RGB libre (roue chromatique). Nécessite le firmware ≥ 1.4.7.
  Future<void> setLedRgb(int r, int g, int b) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/led/rgb'),
            headers: _authHeaders,
            body: jsonEncode({'r': r, 'g': g, 'b': b}),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to set LED rgb: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> setLedBrightness(int brightness) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/set_brightness'),
            headers: _authHeaders,
            body: jsonEncode({'bright': brightness}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to set LED brightness: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<int> getLedBrightness() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/get_brightness'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['bright'] ?? 50;
      }
      return 50; // Default
    } catch (e) {
      return 50; // Default on error
    }
  }

  Future<int> getAudioVolume() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/get_volume'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['vol'] ?? 20;
      }
      return 20; // Default
    } catch (e) {
      return 20; // Default on error
    }
  }

  // ===== AUDIO =====
  Future<void> setAudioVolume(int volume) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/set_volume'),
            headers: _authHeaders,
            body: jsonEncode({'vol': volume}),
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
            headers: _authHeaders,
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

  // ===== AZKAR / CORAN (V2) =====
  Future<Map<String, dynamic>> getAzkarCoran() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/azkarcoran'))
        .timeout(timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load azkar/coran: ${response.statusCode}');
  }

  /// [body] doit utiliser des bool envoyés en 1/0 (ex. sabah_en: 1).
  Future<void> setAzkarCoran(Map<String, dynamic> body) async {
    final response = await http
        .post(Uri.parse('$baseUrl/api/azkarcoran'),
            headers: _authHeaders, body: jsonEncode(body))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to save azkar/coran: ${response.statusCode}');
    }
  }

  // ===== CONTENU AUDIO (V2) =====
  Future<List<String>> listAudio() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/audio/list'))
        .timeout(timeout);
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body);
      if (list is List) return list.map((e) => e.toString()).toList();
      return <String>[];
    }
    throw Exception('Failed to list audio: ${response.statusCode}');
  }

  /// Déclenche la synchro (le device télécharge en tâche de fond).
  Future<void> syncContent() async {
    final r = await http
        .post(Uri.parse('$baseUrl/api/content/sync'), headers: _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw Exception('Failed to start sync: ${r.statusCode}');
    }
  }

  /// État de la synchro en cours : {"running":bool, "added":int}.
  Future<Map<String, dynamic>> getContentStatus() async {
    final r = await http
        .get(Uri.parse('$baseUrl/api/content/status'))
        .timeout(timeout);
    if (r.statusCode == 200) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to get sync status: ${r.statusCode}');
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
        final wifiRaw = data['wifi'];
        final wifi = wifiRaw is Map<String, dynamic>
            ? wifiRaw
            : (wifiRaw is Map ? Map<String, dynamic>.from(wifiRaw) : <String, dynamic>{});
        return {
          'connected': wifi['connected'] == true || wifiRaw?.toString().toLowerCase() == 'connected',
          'ssid': wifi['ssid']?.toString() ?? '',
          'ip': wifi['ip']?.toString() ?? data['ip']?.toString() ?? '',
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

  Future<Map<String, dynamic>> checkWifiStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/wifi/status'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> connectWiFi(String ssid, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/connect_wifi'),
            headers: _authHeaders,
            body: jsonEncode({'ssid': ssid, 'pass': password}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) return; // already connected

      if (response.statusCode == 202) {
        // Async connect — poll until done
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(seconds: 2));
          try {
            final status = await checkWifiStatus();
            final st = status['status'] as String? ?? '';
            if (st == 'connected') return;
            if (st == 'failed') throw Exception('WiFi connection failed');
          } catch (pollErr) {
            // ESP may be switching networks; keep polling
          }
        }
        throw Exception('WiFi connection timed out');
      }

      throw Exception('Failed to connect WiFi: ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  /// Returns device info including API token (unauthenticated bootstrap).
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/device/info'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('HTTP ${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<Map<String, dynamic>> getFirmwareVersion() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/firmware/version'))
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('${response.statusCode}');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<void> uploadFirmware(List<int> bytes) async {
    try {
      // size = taille exacte du .bin (firmware + trailer de signature 512o) :
      // requis par le firmware OTA signé pour séparer firmware et signature.
      final uri = Uri.parse('$baseUrl/ota/upload?token=${apiKey ?? ""}&size=${bytes.length}');
      final request = http.MultipartRequest('POST', uri);
      
      if (apiKey != null && apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = apiKey!;
      }
      
      request.files.add(http.MultipartFile.fromBytes(
        'update',
        bytes,
        filename: 'update.bin',
      ));
      
      final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode != 200) {
        String msg = 'HTTP ${response.statusCode}';
        try {
          final d = jsonDecode(response.body);
          if (d is Map && d['error'] != null) msg = d['error'].toString();
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      // Si on obtient une erreur de socket/connexion lors de la fin du téléversement,
      // c'est généralement parce que la box a accepté le firmware et a initié le redémarrage
      // avant que la réponse HTTP ne soit complètement lue et fermée proprement.
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || 
          errStr.contains('connection failed') || 
          errStr.contains('host is down') ||
          errStr.contains('connection aborted') ||
          errStr.contains('connection reset') ||
          errStr.contains('handshake') ||
          errStr.contains('errno = 64')) {
        // Succès probable (la box est en train de redémarrer avec le nouveau firmware)
        return;
      }
      throw Exception('Erreur de flashage : $e');
    }
  }
}
