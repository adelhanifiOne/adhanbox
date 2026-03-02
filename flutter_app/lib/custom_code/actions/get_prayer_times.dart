// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:convert';
import 'package:http/http.dart' as http;

Future<String> getPrayerTimes(double latitude, double longitude) async {
  final String apiUrl =
      'https://api.mawaqit.net/v1/times?latitude=$latitude&longitude=$longitude';

  final response = await http.get(Uri.parse(apiUrl));

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    print('Full JSON response: $data'); // Debug

    // Essayons d'explorer les clés disponibles
    if (data != null &&
        data['data'] != null &&
        data['data']['timings'] != null) {
      final timings = data['data']['timings'];
      print('Timings: $timings'); // Debug

      String fajr = timings['Fajr'] ?? "";
      String dhuhr = timings['Dhuhr'] ?? "";
      String asr = timings['Asr'] ?? "";
      String maghrib = timings['Maghrib'] ?? "";
      String isha = timings['Isha'] ?? "";

      return jsonEncode({
        'fajr': fajr,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      });
    } else {
      throw Exception('Invalid JSON structure: ${data.toString()}');
    }
  } else {
    throw Exception('Failed to load prayer times: ${response.statusCode}');
  }
}
