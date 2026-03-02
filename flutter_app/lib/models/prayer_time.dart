// lib/models/prayer_time.dart

class PrayerTime {
  final int index; // 1-5
  final String name; // Fajr, Dhuhr, etc.
  final String calculatedTime; // HH:MM
  final String? mawaqitTime; // HH:MM (null si non disponible)
  final bool enabled;
  final int trackIndex;
  final bool duaaAfter;

  PrayerTime({
    required this.index,
    required this.name,
    required this.calculatedTime,
    this.mawaqitTime,
    this.enabled = true,
    this.trackIndex = 0,
    this.duaaAfter = true,
  });

  // Calcule la différence en minutes (Mawaqit - Calculé)
  int? getDifferenceMinutes() {
    if (mawaqitTime == null) return null;

    final calc = _timeToMinutes(calculatedTime);
    final mawaqit = _timeToMinutes(mawaqitTime!);
    return mawaqit - calc;
  }

  // Retourne un statut de synchronisation
  String getSyncStatus() {
    final diff = getDifferenceMinutes();
    if (diff == null) return 'unknown';
    if (diff.abs() <= 2) return 'excellent'; // ✓
    if (diff.abs() <= 5) return 'good'; // ⚠️
    return 'warning'; // ❌
  }

  static int _timeToMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return 0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return hours * 60 + minutes;
  }

  factory PrayerTime.fromJson(Map<String, dynamic> json) {
    return PrayerTime(
      index: json['index'] as int? ?? 1,
      name: json['name'] as String? ?? 'Unknown',
      calculatedTime: json['calculated_time'] as String? ?? '--:--',
      mawaqitTime: json['mawaqit_time'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      trackIndex: json['track_index'] as int? ?? 0,
      duaaAfter: json['duaa_after'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'calculated_time': calculatedTime,
        'mawaqit_time': mawaqitTime,
        'enabled': enabled,
        'track_index': trackIndex,
        'duaa_after': duaaAfter,
      };
}

class PrayerTimes {
  final List<PrayerTime> times;
  final String date;
  final String source; // 'calculated' ou 'mawaqit'
  final int? nextPrayerIndex;
  final int? minutesUntilNextPrayer;

  PrayerTimes({
    required this.times,
    required this.date,
    required this.source,
    this.nextPrayerIndex,
    this.minutesUntilNextPrayer,
  });

  factory PrayerTimes.fromJson(Map<String, dynamic> json) {
    final timesList = <PrayerTime>[];
    final timesJson = json['times'] as Map?;
    final mawaqitJson = json['mawaqit_times'] as Map?;
    
    if (timesJson != null) {
      final names = ['fajr', 'dhuhr', 'asr', 'maghreb', 'isha'];
      for (int i = 0; i < names.length; i++) {
        final calcTime = timesJson[names[i]] as String? ?? '--:--';
        final mawaqitTime = mawaqitJson?[names[i]] as String?;
        
        timesList.add(
          PrayerTime(
            index: i + 1,
            name: names[i].replaceFirst(names[i][0], names[i][0].toUpperCase()),
            calculatedTime: calcTime,
            mawaqitTime: mawaqitTime, // Add Mawaqit time if available
          ),
        );
      }
    }

    return PrayerTimes(
      times: timesList,
      date: json['date'] as String? ?? '',
      source: mawaqitJson != null ? 'mawaqit' : 'calculated',
      nextPrayerIndex: json['next_index'] as int?,
      minutesUntilNextPrayer: json['minutes_until_next'] as int?,
    );
  }
}
