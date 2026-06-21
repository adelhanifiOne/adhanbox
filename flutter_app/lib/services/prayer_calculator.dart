import 'dart:math' as math;

/// Calcul des horaires de prière en Dart pur (algorithme Adhan standard).
/// Utilisé localement pour le fitting — pas de requête ESP32 nécessaire.
class PrayerCalculator {
  // ── Helpers trigonométriques ──────────────────────────────────────────
  static double _r(double d) => d * math.pi / 180.0;
  static double _d(double r) => r * 180.0 / math.pi;
  static double _fix(double a) => a - 360.0 * (a / 360.0).floor();
  static double _fixH(double h) => h - 24.0 * (h / 24.0).floor();

  static double _sin(double deg) => math.sin(_r(deg));
  static double _cos(double deg) => math.cos(_r(deg));
  static double _tan(double deg) => math.tan(_r(deg));
  static double _asin(double x) => _d(math.asin(x.clamp(-1, 1)));
  static double _acos(double x) => _d(math.acos(x.clamp(-1, 1)));
  static double _atan(double x) => _d(math.atan(x));
  static double _atan2(double y, double x) => _d(math.atan2(y, x));

  // ── Calcul Julian Date ────────────────────────────────────────────────
  static double _julianDate(int year, int month, int day) {
    int y = year, m = month;
    if (m <= 2) { y -= 1; m += 12; }
    final A = (y / 100).floor();
    final B = 2 - A + (A / 4).floor();
    return (365.25 * (y + 4716)).floor() +
           (30.6001 * (m + 1)).floor() +
           day + B - 1524.5;
  }

  // ── Position du soleil ────────────────────────────────────────────────
  static ({double decl, double eqt}) _sunPosition(double jd) {
    final D = jd - 2451545.0;
    final g = _fix(357.529 + 0.98560028 * D); // anomalie moyenne
    final q = _fix(280.459 + 0.98564736 * D); // longitude moyenne
    final L = _fix(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g)); // longitude écliptique
    final e = 23.439 - 0.00000036 * D; // obliquité de l'écliptique
    // Ascension droite (heures)
    final RA = _fixH(_fix(_atan2(_cos(e) * _sin(L), _cos(L))) / 15.0);
    final decl = _asin(_sin(e) * _sin(L)); // déclinaison solaire
    final eqt  = _fixH(q / 15.0 - RA);    // équation du temps (heures)
    return (decl: decl, eqt: eqt);
  }

  // ── Angle horaire pour une dépression angulaire α (degrés) ───────────
  // Retourne les heures entre midi solaire et l'heure de la prière.
  // Retourne double.nan si pas de solution (conditions polaires).
  static double _hourAngle(double alpha, double lat, double decl) {
    final x = (_sin(-alpha) - _sin(lat) * _sin(decl)) /
               (_cos(lat) * _cos(decl));
    if (x < -1 || x > 1) return double.nan;
    return _acos(x) / 15.0; // heures
  }

  // ── Angle horaire pour Asr ────────────────────────────────────────────
  // shadowFactor: 1 (Shafi) ou 2 (Hanafi)
  static double _asrHourAngle(double shadowFactor, double lat, double decl) {
    final elevAngle = _atan(1.0 / (shadowFactor + _tan((lat - decl).abs())));
    final x = (_sin(elevAngle) - _sin(lat) * _sin(decl)) /
               (_cos(lat) * _cos(decl));
    if (x < -1 || x > 1) return double.nan;
    return _acos(x) / 15.0;
  }

  // ── API publique ──────────────────────────────────────────────────────

  /// Calcule les horaires de prière.
  /// Retourne des minutes depuis minuit (heure locale).
  /// Retourne null pour une prière si conditions polaires.
  static Map<String, int?> calculate({
    required double lat,
    required double lon,
    required int year,
    required int month,
    required int day,
    required int tzOffsetMinutes,
    required double fajrAngle,
    required double ishaAngle,
    required int school, // 0 = Shafi, 1 = Hanafi
  }) {
    final jd   = _julianDate(year, month, day);
    final sp   = _sunPosition(jd);
    // Midi solaire en UT (heures)
    final noon = 12.0 - lon / 15.0 - sp.eqt;

    final fajrH    = _hourAngle(fajrAngle, lat, sp.decl);
    final sunriseH = _hourAngle(0.833,     lat, sp.decl); // réfraction + demi-disque
    final asrH     = _asrHourAngle(school == 1 ? 2.0 : 1.0, lat, sp.decl);
    final ishaH    = _hourAngle(ishaAngle, lat, sp.decl);

    int? toLocal(double utHours) {
      if (utHours.isNaN) return null;
      final totalMin = (utHours * 60).round() + tzOffsetMinutes;
      return ((totalMin % 1440) + 1440) % 1440;
    }

    return {
      'fajr':    toLocal(noon - fajrH),
      'sunrise': toLocal(noon - sunriseH),
      'dhuhr':   toLocal(noon + 1.0 / 60.0), // 1 min après midi solaire
      'asr':     toLocal(noon + asrH),
      'maghrib': toLocal(noon + sunriseH),
      'isha':    toLocal(noon + ishaH),
    };
  }

  // ── Utilitaires de formatage ──────────────────────────────────────────

  static String minutesToHHMM(int? mins) {
    if (mins == null) return '--:--';
    final m = ((mins % 1440) + 1440) % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
           '${(m % 60).toString().padLeft(2, '0')}';
  }

  static int? hhmmToMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
