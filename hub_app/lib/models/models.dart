// ── Prayer ────────────────────────────────────────────────────────────────────

class PrayerTime {
  final String name;
  final String nameAr;
  final String time;
  final int timestamp;
  final bool isNext;
  final bool passed;

  const PrayerTime({
    required this.name,
    required this.nameAr,
    required this.time,
    required this.timestamp,
    required this.isNext,
    required this.passed,
  });

  factory PrayerTime.fromJson(Map<String, dynamic> j) => PrayerTime(
    name: j['name'],
    nameAr: j['name_ar'],
    time: j['time'],
    timestamp: j['timestamp'],
    isNext: j['is_next'] ?? false,
    passed: j['passed'] ?? false,
  );
}

class PrayerTimesResponse {
  final String date;
  final String location;
  final String method;
  final String madhab;
  final List<PrayerTime> prayers;

  const PrayerTimesResponse({
    required this.date,
    required this.location,
    required this.method,
    required this.madhab,
    required this.prayers,
  });

  factory PrayerTimesResponse.fromJson(Map<String, dynamic> j) => PrayerTimesResponse(
    date: j['date'],
    location: j['location'],
    method: j['method'],
    madhab: j['madhab'],
    prayers: (j['prayers'] as List).map((p) => PrayerTime.fromJson(p)).toList(),
  );
}

// ── Azkar ─────────────────────────────────────────────────────────────────────

class Zikr {
  final int id;
  final String textAr;
  final String textFr;
  final String textEn;
  final String source;
  final int count;
  final String category;

  const Zikr({
    required this.id,
    required this.textAr,
    required this.textFr,
    required this.textEn,
    required this.source,
    required this.count,
    required this.category,
  });

  factory Zikr.fromJson(Map<String, dynamic> j) => Zikr(
    id: j['id'],
    textAr: j['text_ar'],
    textFr: j['text_fr'],
    textEn: j['text_en'],
    source: j['source'],
    count: j['count'] ?? 1,
    category: j['category'],
  );
}

// ── Quran ─────────────────────────────────────────────────────────────────────

class Surah {
  final int number;
  final String nameAr;
  final String nameEn;
  final String nameFr;
  final int versesCount;
  final String revelationType;

  const Surah({
    required this.number,
    required this.nameAr,
    required this.nameEn,
    required this.nameFr,
    required this.versesCount,
    required this.revelationType,
  });

  factory Surah.fromJson(Map<String, dynamic> j) => Surah(
    number: j['number'],
    nameAr: j['name_ar'],
    nameEn: j['name_en'],
    nameFr: j['name_fr'],
    versesCount: j['verses_count'],
    revelationType: j['revelation_type'],
  );
}

class ReciterInfo {
  final int id;
  final String name;
  final String style;

  const ReciterInfo({required this.id, required this.name, required this.style});

  factory ReciterInfo.fromJson(Map<String, dynamic> j) =>
    ReciterInfo(id: j['id'], name: j['name'], style: j['style']);
}

// ── Assistant ─────────────────────────────────────────────────────────────────

class ChatMessage {
  final String role;
  final String content;
  final DateTime createdAt;

  ChatMessage({required this.role, required this.content, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();
}

class ChatResponse {
  final String answer;
  final List<String> sources;
  final String madhab;
  final String language;

  const ChatResponse({
    required this.answer,
    required this.sources,
    required this.madhab,
    required this.language,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> j) => ChatResponse(
    answer: j['answer'],
    sources: List<String>.from(j['sources'] ?? []),
    madhab: j['madhab'],
    language: j['language'],
  );
}

// ── User prefs ────────────────────────────────────────────────────────────────

class UserPreferences {
  final String madhab;
  final String language;
  final double latitude;
  final double longitude;
  final int timezoneOffset;
  final String calculationMethod;
  final int favoriteReciterId;
  final bool azkarMorningEnabled;
  final bool azkarEveningEnabled;
  final bool azkarAfterPrayerEnabled;
  final String hubIp;
  final bool darkMode;

  const UserPreferences({
    this.madhab = 'hanafi',
    this.language = 'fr',
    this.latitude = 48.8566,
    this.longitude = 2.3522,
    this.timezoneOffset = 60,
    this.calculationMethod = 'MWL',
    this.favoriteReciterId = 7,
    this.azkarMorningEnabled = true,
    this.azkarEveningEnabled = true,
    this.azkarAfterPrayerEnabled = true,
    this.hubIp = 'http://192.168.1.100:8000',
    this.darkMode = true,
  });

  UserPreferences copyWith({
    String? madhab, String? language, double? latitude, double? longitude,
    int? timezoneOffset, String? calculationMethod, int? favoriteReciterId,
    bool? azkarMorningEnabled, bool? azkarEveningEnabled, bool? azkarAfterPrayerEnabled,
    String? hubIp, bool? darkMode,
  }) => UserPreferences(
    madhab: madhab ?? this.madhab,
    language: language ?? this.language,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    timezoneOffset: timezoneOffset ?? this.timezoneOffset,
    calculationMethod: calculationMethod ?? this.calculationMethod,
    favoriteReciterId: favoriteReciterId ?? this.favoriteReciterId,
    azkarMorningEnabled: azkarMorningEnabled ?? this.azkarMorningEnabled,
    azkarEveningEnabled: azkarEveningEnabled ?? this.azkarEveningEnabled,
    azkarAfterPrayerEnabled: azkarAfterPrayerEnabled ?? this.azkarAfterPrayerEnabled,
    hubIp: hubIp ?? this.hubIp,
    darkMode: darkMode ?? this.darkMode,
  );
}
