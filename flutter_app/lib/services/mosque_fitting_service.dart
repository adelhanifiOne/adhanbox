import 'dart:math' as math;
import 'prayer_calculator.dart';

/// Résultat du fitting automatique des paramètres de la mosquée.
class CalibrationResult {
  final String methodName;  // Nom affiché (ex: "UOIF — France")
  final String methodCode;  // Code API (ex: "uoif" ou "custom")
  final double fajrAngle;
  final double ishaAngle;
  final int school;          // 0 = Shafi, 1 = Hanafi
  final Map<String, int> residualOffsets; // offsets résiduels en minutes
  final double rmsError;     // erreur RMS en minutes (0 = parfait)
  final Map<String, int> perPrayerDelta; // écart par prière (mosquée - calculé)

  const CalibrationResult({
    required this.methodName,
    required this.methodCode,
    required this.fajrAngle,
    required this.ishaAngle,
    required this.school,
    required this.residualOffsets,
    required this.rmsError,
    required this.perPrayerDelta,
  });

  /// Vrai si une méthode connue correspond exactement (erreur < 2 min)
  bool get isKnownMethod => methodCode != 'custom';

  String get schoolName => school == 1 ? 'Hanafi' : 'Shafi\'i';

  String get angleDescription =>
      'Fajr ${fajrAngle.toStringAsFixed(1)}° / Isha ${ishaAngle.toStringAsFixed(1)}°';
}

/// Service qui reverse-ingénierise les paramètres de calcul d'une mosquée
/// à partir des horaires qu'elle affiche pour une journée donnée.
class MosqueFittingService {
  // ── Méthodes connues : (nom affiché, fajrAngle, ishaAngle) ───────────
  static const _knownMethods = <String, (String, double, double)>{
    'mwl':     ('Ligue Islamique Mondiale (MWL)',     18.0, 17.0),
    'isna':    ('ISNA — Amérique du Nord',             15.0, 15.0),
    'uoif':    ('UOIF — France',                       12.0, 12.0),
    'egypt':   ('Autorité Égyptienne',                 19.5, 17.5),
    'karachi': ('Sciences Islamiques — Karachi',        18.0, 18.0),
  };

  // ── Recherche dichotomique de l'angle ─────────────────────────────────
  // Trouve l'angle (°) qui donne exactement [targetMinutes] pour Fajr ou Isha.
  static double _fitAngle({
    required int targetMinutes,
    required double lat,
    required double lon,
    required int year, required int month, required int day,
    required int tzOffsetMinutes,
    required int school,
    required bool isFajr,
    double lo = 5.0,
    double hi = 28.0,
  }) {
    // Vérification que la solution est dans [lo, hi]
    double calcFor(double angle) {
      final times = PrayerCalculator.calculate(
        lat: lat, lon: lon,
        year: year, month: month, day: day,
        tzOffsetMinutes: tzOffsetMinutes,
        fajrAngle: isFajr ? angle : 15.0,
        ishaAngle: isFajr ? 15.0 : angle,
        school: school,
      );
      return (times[isFajr ? 'fajr' : 'isha'] ?? 0).toDouble();
    }

    for (int i = 0; i < 60; i++) {
      final mid  = (lo + hi) / 2.0;
      final calc = calcFor(mid).round();
      if (calc == targetMinutes) return mid;
      if (isFajr) {
        // Angle plus grand → Fajr plus tôt (valeur plus petite)
        if (calc < targetMinutes) hi = mid; else lo = mid;
      } else {
        // Angle plus grand → Isha plus tard (valeur plus grande)
        if (calc > targetMinutes) hi = mid; else lo = mid;
      }
    }
    return (lo + hi) / 2.0;
  }

  // ── Correspondance avec une méthode connue ────────────────────────────
  static String _matchMethod(double fajr, double isha) {
    String best = 'custom';
    double bestErr = double.infinity;
    for (final entry in _knownMethods.entries) {
      final (_, mFajr, mIsha) = entry.value;
      final err = (fajr - mFajr).abs() + (isha - mIsha).abs();
      if (err < bestErr) { bestErr = err; best = entry.key; }
    }
    // Seuil : ±1.5° total pour considérer comme méthode connue
    return bestErr <= 1.5 ? best : 'custom';
  }

  // ── Fitting principal ─────────────────────────────────────────────────
  /// [mosqueTimes] : prayer key → minutes depuis minuit (null si non fourni).
  /// Retourne le meilleur [CalibrationResult] après analyse.
  static Future<CalibrationResult> fit({
    required Map<String, int?> mosqueTimes,
    required double lat,
    required double lon,
    required int year, required int month, required int day,
    required int tzOffsetMinutes,
  }) async {
    // Calcul en microtask pour libérer le frame UI avant de démarrer
    return await Future.microtask(() => _fitSync(
      mosqueTimes: mosqueTimes,
      lat: lat, lon: lon,
      year: year, month: month, day: day,
      tzOffsetMinutes: tzOffsetMinutes,
    ));
  }

  static CalibrationResult _fitSync({
    required Map<String, int?> mosqueTimes,
    required double lat,
    required double lon,
    required int year, required int month, required int day,
    required int tzOffsetMinutes,
  }) {
    CalibrationResult? best;

    for (final school in [0, 1]) {
      // 1. Fitter Fajr et Isha par dichotomie angulaire
      final fajrTarget = mosqueTimes['fajr'];
      final ishaTarget = mosqueTimes['isha'];

      final fajrAngle = fajrTarget != null
          ? _fitAngle(
              targetMinutes: fajrTarget, lat: lat, lon: lon,
              year: year, month: month, day: day,
              tzOffsetMinutes: tzOffsetMinutes, school: school, isFajr: true,
            )
          : 15.0; // valeur neutre si non fourni

      final ishaAngle = ishaTarget != null
          ? _fitAngle(
              targetMinutes: ishaTarget, lat: lat, lon: lon,
              year: year, month: month, day: day,
              tzOffsetMinutes: tzOffsetMinutes, school: school, isFajr: false,
            )
          : 15.0;

      // 2. Calculer tous les horaires avec les angles fittés
      final times = PrayerCalculator.calculate(
        lat: lat, lon: lon,
        year: year, month: month, day: day,
        tzOffsetMinutes: tzOffsetMinutes,
        fajrAngle: fajrAngle, ishaAngle: ishaAngle,
        school: school,
      );

      // 3. Calculer écarts et offsets résiduels
      final residual = <String, int>{};
      final delta    = <String, int>{};
      double sumSq = 0;
      int n = 0;

      for (final prayer in ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha']) {
        final mosqueMin = mosqueTimes[prayer];
        final calcMin   = times[prayer];

        if (mosqueMin == null || calcMin == null) {
          residual[prayer] = 0;
          delta[prayer]    = 0;
          continue;
        }

        final diff = mosqueMin - calcMin;
        delta[prayer] = diff;

        // Fajr/Isha : l'angle absorbe la différence → offset résiduel ≈ 0
        // Autres : différence = offset fixe de la mosquée
        final offset = (prayer == 'fajr' || prayer == 'isha') ? 0 : diff;
        residual[prayer] = offset.clamp(-30, 30);
        sumSq += diff * diff;
        n++;
      }

      final rms = n > 0 ? math.sqrt(sumSq / n) : 0.0;

      // 4. Identifier la méthode connue la plus proche
      final methodCode = _matchMethod(fajrAngle, ishaAngle);
      final methodName = methodCode == 'custom'
          ? 'Angles personnalisés'
          : _knownMethods[methodCode]!.$1;

      final result = CalibrationResult(
        methodName: methodName,
        methodCode: methodCode,
        fajrAngle: double.parse(fajrAngle.toStringAsFixed(2)),
        ishaAngle: double.parse(ishaAngle.toStringAsFixed(2)),
        school: school,
        residualOffsets: residual,
        rmsError: double.parse(rms.toStringAsFixed(2)),
        perPrayerDelta: delta,
      );

      // Conserver le meilleur résultat (RMS le plus faible)
      if (best == null || rms < best.rmsError) best = result;
    }

    return best!;
  }
}
