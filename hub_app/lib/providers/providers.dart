import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_service.dart';

// ── Preferences ───────────────────────────────────────────────────────────────

class PrefsNotifier extends StateNotifier<UserPreferences> {
  PrefsNotifier() : super(const UserPreferences()) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = UserPreferences(
      madhab: p.getString('madhab') ?? 'hanafi',
      language: p.getString('language') ?? 'fr',
      latitude: p.getDouble('lat') ?? 48.8566,
      longitude: p.getDouble('lon') ?? 2.3522,
      timezoneOffset: p.getInt('tz_offset') ?? 60,
      calculationMethod: p.getString('calc_method') ?? 'MWL',
      favoriteReciterId: p.getInt('reciter_id') ?? 7,
      azkarMorningEnabled: p.getBool('azkar_morning') ?? true,
      azkarEveningEnabled: p.getBool('azkar_evening') ?? true,
      azkarAfterPrayerEnabled: p.getBool('azkar_after') ?? true,
      hubIp: p.getString('hub_ip') ?? 'http://192.168.1.100:8000',
      darkMode: p.getBool('dark_mode') ?? true,
    );
  }

  Future<void> update(UserPreferences prefs) async {
    state = prefs;
    final p = await SharedPreferences.getInstance();
    await p.setString('madhab', prefs.madhab);
    await p.setString('language', prefs.language);
    await p.setDouble('lat', prefs.latitude);
    await p.setDouble('lon', prefs.longitude);
    await p.setInt('tz_offset', prefs.timezoneOffset);
    await p.setString('calc_method', prefs.calculationMethod);
    await p.setInt('reciter_id', prefs.favoriteReciterId);
    await p.setBool('azkar_morning', prefs.azkarMorningEnabled);
    await p.setBool('azkar_evening', prefs.azkarEveningEnabled);
    await p.setBool('azkar_after', prefs.azkarAfterPrayerEnabled);
    await p.setString('hub_ip', prefs.hubIp);
    await p.setBool('dark_mode', prefs.darkMode);
  }
}

final prefsProvider = StateNotifierProvider<PrefsNotifier, UserPreferences>(
  (_) => PrefsNotifier(),
);

// ── API Service ───────────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) {
  final prefs = ref.watch(prefsProvider);
  return ApiService(prefs.hubIp);
});

// ── Hub connectivity ──────────────────────────────────────────────────────────

final hubConnectedProvider = FutureProvider<bool>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.checkHealth();
});

// ── Prayer times ──────────────────────────────────────────────────────────────

final prayerTimesProvider = FutureProvider<PrayerTimesResponse>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getPrayerTimes();
});

final nextPrayerProvider = FutureProvider<PrayerTime>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getNextPrayer();
});

// ── Azkar ─────────────────────────────────────────────────────────────────────

final azkarProvider = FutureProvider.family<List<Zikr>, String>((ref, category) async {
  final api = ref.watch(apiServiceProvider);
  return api.getAzkar(category);
});

// ── Quran ─────────────────────────────────────────────────────────────────────

final surahsProvider = FutureProvider<List<Surah>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getSurahs();
});

final recitersProvider = FutureProvider<List<ReciterInfo>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getReciters();
});

// ── Assistant chat ────────────────────────────────────────────────────────────

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier() : super([]);

  final _history = <ChatMessage>[];

  void addMessage(ChatMessage msg) {
    _history.add(msg);
    state = List.from(_history);
  }

  void clear() {
    _history.clear();
    state = [];
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>(
  (_) => ChatNotifier(),
);
