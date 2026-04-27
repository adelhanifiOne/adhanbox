import 'package:dio/dio.dart';
import '../models/models.dart';

class ApiService {
  late Dio _dio;

  ApiService(String baseUrl) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  void updateBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  // ── Prières ────────────────────────────────────────────────────────────────

  Future<PrayerTimesResponse> getPrayerTimes({String? date}) async {
    final r = await _dio.get('/prayers/times', queryParameters: date != null ? {'date': date} : null);
    return PrayerTimesResponse.fromJson(r.data);
  }

  Future<PrayerTime> getNextPrayer() async {
    final r = await _dio.get('/prayers/next');
    return PrayerTime.fromJson(r.data);
  }

  Future<void> updatePrayerConfig({
    required double lat, required double lon,
    required String method, required String madhab, required int tzOffset,
  }) async {
    await _dio.post('/prayers/config', data: {
      'latitude': lat, 'longitude': lon, 'method': method,
      'madhab': madhab, 'timezone_offset': tzOffset,
    });
  }

  // ── Azkar ──────────────────────────────────────────────────────────────────

  Future<List<Zikr>> getAzkar(String category) async {
    final r = await _dio.get('/azkar/$category');
    return (r.data['azkar'] as List).map((z) => Zikr.fromJson(z)).toList();
  }

  // ── Coran ──────────────────────────────────────────────────────────────────

  Future<List<Surah>> getSurahs() async {
    final r = await _dio.get('/quran/surahs');
    return (r.data as List).map((s) => Surah.fromJson(s)).toList();
  }

  Future<List<ReciterInfo>> getReciters() async {
    final r = await _dio.get('/quran/reciters');
    return (r.data as List).map((r) => ReciterInfo.fromJson(r)).toList();
  }

  Future<String> getAudioUrl(int surah, int reciterId) async {
    final r = await _dio.get('/quran/audio/$surah/$reciterId');
    return r.data['url'] as String;
  }

  // ── Assistant ──────────────────────────────────────────────────────────────

  Future<ChatResponse> sendMessage({
    required String message,
    required String madhab,
    required String language,
    List<ChatMessage> history = const [],
  }) async {
    final r = await _dio.post('/assistant/chat', data: {
      'message': message,
      'madhab': madhab,
      'language': language,
      'history': history.map((m) => {'role': m.role, 'content': m.content}).toList(),
    });
    return ChatResponse.fromJson(r.data);
  }

  // ── Devices ────────────────────────────────────────────────────────────────

  Future<void> triggerAdhan({int track = 2}) async {
    await _dio.post('/devices/adhanbox/adhan', data: {'track': track});
  }

  Future<void> setLed({required int scenario, int? brightness}) async {
    await _dio.post('/devices/adhanbox/led', data: {
      'scenario': scenario,
      if (brightness != null) 'brightness': brightness,
    });
  }

  Future<Map<String, dynamic>> getAdhanboxStatus() async {
    final r = await _dio.get('/devices/adhanbox/status');
    return r.data;
  }

  Future<bool> checkHealth() async {
    try {
      final r = await _dio.get('/health');
      return r.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
