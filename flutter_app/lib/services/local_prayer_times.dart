// lib/services/local_prayer_times.dart
//
// Calcul des horaires de priere DANS l'app, sans boitier.
//
// Pourquoi : jusqu'ici les horaires venaient exclusivement de l'AdhanBox
// (prayerTimesProvider -> api.getPrayerTimes()). Sans appareil appaire, l'ecran
// principal levait "Aucun appareil configure" et l'application entiere etait
// inutilisable — pour un client entre la precommande et la livraison, pour un
// testeur qui n'a pas de boitier, et pour tout le monde quand la box est hors
// ligne (coupure de courant).
//
// La box reste la SOURCE DE VERITE quand elle repond : c'est elle qui declenche
// l'adhan, les heures affichees doivent correspondre a ce qu'elle jouera. Ce
// module ne sert que de repli, et il reproduit volontairement les memes angles
// que le firmware (voir getCalculationAngles() dans adhanbox_v2.ino) pour que
// les deux sources concordent.
import 'package:adhan/adhan.dart' as adhan;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prayer_time.dart';

/// Cles de persistance partagees avec l'ecran de configuration du calcul.
const String kPrefLat = 'calc_lat';
const String kPrefLon = 'calc_lon';
const String kPrefMethod = 'calc_method';
const String kPrefSchool = 'calc_school';

/// Angles fajr/isha par methode — copie conforme du firmware. Toute
/// modification ici doit etre repercutee dans getCalculationAngles() cote
/// firmware, sinon l'app et la box afficheraient des heures differentes.
const Map<String, List<double>> _angles = {
  'mwl': [18.0, 17.0],
  'isna': [15.0, 15.0],
  'uoif': [12.0, 12.0],
  'egypt': [19.5, 17.5],
  'karachi': [18.0, 18.0],
};

/// Erreur explicite quand on ne sait pas ou se trouve l'utilisateur : sans
/// position, aucun calcul n'est possible et il faut le lui dire clairement
/// plutot que d'afficher des heures fausses.
class PositionInconnueException implements Exception {
  const PositionInconnueException();
  @override
  String toString() => 'Position inconnue';
}

/// Memorise la position pour les prochains calculs (et pour les lancements
/// hors ligne). Appele aussi quand on lit la config de la box, afin que le
/// repli reste aligne sur elle.
Future<void> memoriserPosition(double lat, double lon) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(kPrefLat, lat);
  await prefs.setDouble(kPrefLon, lon);
}

Future<void> memoriserMethode(String method, int school) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPrefMethod, method.toLowerCase());
  await prefs.setInt(kPrefSchool, school);
}

/// Recupere la position : cache d'abord (instantane, marche hors ligne), GPS
/// ensuite. On ne demande le GPS que si l'on n'a jamais rien memorise, pour ne
/// pas solliciter l'utilisateur a chaque ouverture.
Future<({double lat, double lon})> _position() async {
  final prefs = await SharedPreferences.getInstance();
  final lat = prefs.getDouble(kPrefLat);
  final lon = prefs.getDouble(kPrefLon);
  if (lat != null && lon != null) return (lat: lat, lon: lon);

  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const PositionInconnueException();
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const PositionInconnueException();
  }

  // Precision basse volontairement : une ville suffit pour les horaires, et
  // c'est bien plus rapide et econome en batterie qu'un point GPS precis.
  final p = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.low,
  );
  await memoriserPosition(p.latitude, p.longitude);
  return (lat: p.latitude, lon: p.longitude);
}

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Calcule les horaires du jour localement et les renvoie dans le meme modele
/// que ceux venant de la box, pour que l'interface n'ait pas a distinguer les
/// deux cas.
Future<PrayerTimes> calculerHorairesLocaux({DateTime? jour}) async {
  final pos = await _position();
  final prefs = await SharedPreferences.getInstance();
  final method = (prefs.getString(kPrefMethod) ?? 'mwl').toLowerCase();
  final school = prefs.getInt(kPrefSchool) ?? 0;

  final angles = _angles[method] ?? _angles['mwl']!;
  final params = adhan.CalculationParameters(
    fajrAngle: angles[0],
    ishaAngle: angles[1],
    madhab: school == 1 ? adhan.Madhab.hanafi : adhan.Madhab.shafi,
  );

  final date = jour ?? DateTime.now();
  final calcul = adhan.PrayerTimes(
    adhan.Coordinates(pos.lat, pos.lon),
    adhan.DateComponents.from(date),
    params,
  );

  final heures = <String, DateTime>{
    'fajr': calcul.fajr,
    'dhuhr': calcul.dhuhr,
    'asr': calcul.asr,
    'maghreb': calcul.maghrib,
    'isha': calcul.isha,
  };

  final liste = <PrayerTime>[];
  var i = 1;
  for (final e in heures.entries) {
    liste.add(PrayerTime(
      index: i,
      name: e.key.replaceFirst(e.key[0], e.key[0].toUpperCase()),
      calculatedTime: _hhmm(e.value),
    ));
    i++;
  }

  // Prochaine priere : la premiere encore a venir aujourd'hui, sinon le Fajr
  // de demain (l'interface affiche alors un compte a rebours qui traverse
  // minuit, comme avec les horaires de la box).
  final maintenant = DateTime.now();
  int? prochainIndex;
  int? minutesRestantes;
  var idx = 1;
  for (final t in heures.values) {
    if (t.isAfter(maintenant)) {
      prochainIndex = idx;
      minutesRestantes = t.difference(maintenant).inMinutes;
      break;
    }
    idx++;
  }
  if (prochainIndex == null) {
    final demain = adhan.PrayerTimes(
      adhan.Coordinates(pos.lat, pos.lon),
      adhan.DateComponents.from(date.add(const Duration(days: 1))),
      params,
    );
    prochainIndex = 1;
    minutesRestantes = demain.fajr.difference(maintenant).inMinutes;
  }

  return PrayerTimes(
    times: liste,
    date: '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    source: 'local',
    nextPrayerIndex: prochainIndex,
    minutesUntilNextPrayer: minutesRestantes,
  );
}
