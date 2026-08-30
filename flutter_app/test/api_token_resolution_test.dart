// Le jeton d'API doit survivre a un changement d'adresse IP, et un second
// telephone doit pouvoir le recuperer pendant la fenetre d'appairage.
//
// Ces tests rejouent l'incident du 29/08 : une box dont l'IP change (ou une
// app qui n'a jamais eu le jeton) perdait tout controle — LED, azkar, Coran
// refuses — et seul l'adhan passait, /play etant la seule route sans
// authentification. La resolution est testee contre un vrai serveur HTTP
// local qui repond comme handleDeviceInfo() du firmware.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adhanbox/providers/adhanbox_provider.dart';

/// Fausse box : ne sert que /api/device/info, comme le firmware —
/// avec ou sans jeton selon qu'on est dans la fenetre d'appairage.
Future<HttpServer> fausseBox({String? token, String id = 'AABBCCDDEEFF'}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final corps = <String, dynamic>{
      'version': '3.0.6',
      'hardware': 'v3',
      'device_id': id,
      if (token != null) 'token': token else 'paired': true,
    };
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(corps));
    req.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test remplace le client HTTP par un simulacre qui repond 400 a
  // tout. Ici on parle a un VRAI serveur local : on retablit le vrai client.
  setUpAll(() => HttpOverrides.global = null);

  test('fenetre ouverte : le jeton publie est adopte et mis en cache '
      'sous l\'IP ET sous l\'identifiant materiel', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final box = await fausseBox(token: 'JETON-FRAIS');
    final ip = '127.0.0.1:${box.port}';

    expect(await resolveApiToken(prefs, ip), 'JETON-FRAIS');
    expect(prefs.getString('api_token_$ip'), 'JETON-FRAIS');
    expect(prefs.getString('api_token_id_AABBCCDDEEFF'), 'JETON-FRAIS');
    await box.close();
  });

  test('IP changee : le jeton indexe par identifiant suffit — '
      'le scenario qui desautorisait un telephone appaire', () async {
    // Le cache par IP pointe vers l'ANCIENNE adresse : il est introuvable
    // sous la nouvelle. Seul l'identifiant materiel permet de le retrouver.
    SharedPreferences.setMockInitialValues({
      'api_token_id_AABBCCDDEEFF': 'JETON-HISTORIQUE',
    });
    final prefs = await SharedPreferences.getInstance();
    final box = await fausseBox(token: null); // fenetre fermee, usage normal
    final ip = '127.0.0.1:${box.port}';

    expect(await resolveApiToken(prefs, ip), 'JETON-HISTORIQUE');
    // Et le cache historique par IP est realigne au passage.
    expect(prefs.getString('api_token_$ip'), 'JETON-HISTORIQUE');
    await box.close();
  });

  test('installation existante : le vieux cache par IP est migre '
      'vers l\'identifiant materiel', () async {
    final box = await fausseBox(token: null);
    final ip = '127.0.0.1:${box.port}';
    SharedPreferences.setMockInitialValues({'api_token_$ip': 'JETON-LEGACY'});
    final prefs = await SharedPreferences.getInstance();

    expect(await resolveApiToken(prefs, ip), 'JETON-LEGACY');
    expect(prefs.getString('api_token_id_AABBCCDDEEFF'), 'JETON-LEGACY');
    await box.close();
  });

  test('second telephone, fenetre fermee, aucun cache : null — '
      'et c\'est le parcours « Autoriser ce telephone » qui prend le relais',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final box = await fausseBox(token: null);
    final ip = '127.0.0.1:${box.port}';

    expect(await resolveApiToken(prefs, ip), isNull);
    await box.close();
  });

  test('box injoignable mais jeton en cache sous l\'IP : on garde la main',
      () async {
    SharedPreferences.setMockInitialValues({
      'api_token_10.0.0.9': 'JETON-CACHE',
    });
    final prefs = await SharedPreferences.getInstance();
    // Personne n'ecoute sur cette adresse : le fetch echoue, le cache repond.
    expect(await resolveApiToken(prefs, '10.0.0.9'), 'JETON-CACHE');
  });
}
