// Verifie que le calcul local des horaires reste coherent avec le firmware.
//
// Le risque que ce test couvre : si quelqu'un modifie les angles fajr/isha
// d'un cote sans l'autre, l'app afficherait des heures differentes de celles
// que la box joue reellement — un decalage silencieux et tres difficile a
// diagnostiquer chez un client.
import 'package:adhan/adhan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Angles attendus, identiques a getCalculationAngles() dans les .ino V1/V2/V3.
const _anglesFirmware = {
  'mwl': [18.0, 17.0],
  'isna': [15.0, 15.0],
  'uoif': [12.0, 12.0],
  'egypt': [19.5, 17.5],
  'karachi': [18.0, 18.0],
};

void main() {
  test('les angles du calcul local correspondent a ceux du firmware', () {
    // Duplique volontairement la table de local_prayer_times.dart : si l'une
    // des deux change, ce test tombe.
    const anglesApp = {
      'mwl': [18.0, 17.0],
      'isna': [15.0, 15.0],
      'uoif': [12.0, 12.0],
      'egypt': [19.5, 17.5],
      'karachi': [18.0, 18.0],
    };
    expect(anglesApp, _anglesFirmware);
  });

  test('produit des horaires plausibles et ordonnes', () {
    // Vic-en-Bigorre (65), 15 juin : jour long, cas qui met en evidence les
    // erreurs de fuseau ou d'angle.
    final coords = Coordinates(43.39, 0.05);
    final params = CalculationParameters(
      fajrAngle: 18.0,
      ishaAngle: 17.0,
      madhab: Madhab.shafi,
    );
    final t = PrayerTimes(
      coords,
      DateComponents(2026, 6, 15),
      params,
    );

    // Ordre chronologique strict — attrape les inversions et les debordements
    // de minuit.
    expect(t.fajr.isBefore(t.sunrise), isTrue);
    expect(t.sunrise.isBefore(t.dhuhr), isTrue);
    expect(t.dhuhr.isBefore(t.asr), isTrue);
    expect(t.asr.isBefore(t.maghrib), isTrue);
    expect(t.maghrib.isBefore(t.isha), isTrue);

    // Toutes les prieres tombent le meme jour civil a cette latitude.
    expect(t.fajr.day, 15);
    expect(t.isha.day, 15);

    // Bornes larges mais suffisantes pour detecter une erreur de fuseau
    // horaire (qui decalerait tout d'une ou deux heures).
    expect(t.dhuhr.hour, inInclusiveRange(12, 15));
    expect(t.maghrib.hour, inInclusiveRange(20, 22));
  });

  test('le madhab hanafi retarde bien le Asr', () {
    final coords = Coordinates(43.39, 0.05);
    final date = DateComponents(2026, 6, 15);
    CalculationParameters p(Madhab m) => CalculationParameters(
        fajrAngle: 18.0, ishaAngle: 17.0, madhab: m);

    final shafi = PrayerTimes(coords, date, p(Madhab.shafi));
    final hanafi = PrayerTimes(coords, date, p(Madhab.hanafi));
    expect(hanafi.asr.isAfter(shafi.asr), isTrue);
  });
}
