import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/adhanbox_provider.dart';

class AdhanConfigScreen extends ConsumerStatefulWidget {
  const AdhanConfigScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AdhanConfigScreen> createState() => _AdhanConfigScreenState();
}

class _AdhanConfigScreenState extends ConsumerState<AdhanConfigScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _deviceIp;

  // Configuration des adhans par prière
  final Map<String, int> _selectedTracks = {
    'fajr': 2,
    'dhuhr': 2,
    'asr': 2,
    'maghrib': 2,
    'isha': 2,
  };

  // Configuration du duaa
  final Map<String, bool> _playDuaa = {
    'fajr': true,
    'dhuhr': true,
    'asr': true,
    'maghrib': true,
    'isha': true,
  };

  final Map<String, String> _prayerNames = {
    'fajr': 'Fajr',
    'dhuhr': 'Dhuhr',
    'asr': 'Asr',
    'maghrib': 'Maghrib',
    'isha': 'Isha',
  };

  String _getTrackLabel(int trackNumber) {
    if (trackNumber == 2 || trackNumber == 3) {
      return 'Adhan Sobh';
    }
    return 'Adhan';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConfiguration();
    });
  }

  Future<void> _loadConfiguration() async {
    try {
      final deviceIpAsync = ref.read(currentDeviceIpProvider);
      if (deviceIpAsync == null) {
        setState(() {
          _errorMessage = 'Aucun appareil configuré';
          _isLoading = false;
        });
        return;
      }

      setState(() => _deviceIp = deviceIpAsync);

      // Charger la configuration actuelle (optionnel, par défaut tous les sliders à 1)
      try {
        final configUrl = Uri.parse('http://$_deviceIp/api/adhan/config');
        final response = await http.get(configUrl).timeout(
          const Duration(seconds: 5),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _selectedTracks['fajr'] = (data['fajr_track'] == 1) ? 2 : (data['fajr_track'] ?? 2);
            _selectedTracks['dhuhr'] = (data['dhuhr_track'] == 1) ? 2 : (data['dhuhr_track'] ?? 2);
            _selectedTracks['asr'] = (data['asr_track'] == 1) ? 2 : (data['asr_track'] ?? 2);
            _selectedTracks['maghrib'] = (data['maghrib_track'] == 1) ? 2 : (data['maghrib_track'] ?? 2);
            _selectedTracks['isha'] = (data['isha_track'] == 1) ? 2 : (data['isha_track'] ?? 2);

            _playDuaa['fajr'] = data['fajr_duaa'] ?? true;
            _playDuaa['dhuhr'] = data['dhuhr_duaa'] ?? true;
            _playDuaa['asr'] = data['asr_duaa'] ?? true;
            _playDuaa['maghrib'] = data['maghrib_duaa'] ?? true;
            _playDuaa['isha'] = data['isha_duaa'] ?? true;
          });
        }
      } catch (e) {
        debugPrint('Config load error: $e (using defaults)');
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('IP loading error: $e');
      setState(() {
        _errorMessage = 'Erreur au chargement de l\'IP: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfiguration() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (_deviceIp == null) {
        throw Exception('Aucun appareil connecté');
      }

      final configUrl = Uri.parse('http://$_deviceIp/api/adhan/config');
      final payload = {
        'fajr_track': _selectedTracks['fajr'],
        'fajr_duaa': _playDuaa['fajr'],
        'dhuhr_track': _selectedTracks['dhuhr'],
        'dhuhr_duaa': _playDuaa['dhuhr'],
        'asr_track': _selectedTracks['asr'],
        'asr_duaa': _playDuaa['asr'],
        'maghrib_track': _selectedTracks['maghrib'],
        'maghrib_duaa': _playDuaa['maghrib'],
        'isha_track': _selectedTracks['isha'],
        'isha_duaa': _playDuaa['isha'],
      };

      final response = await http.post(
        configUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Échec sauvegarde (HTTP ${response.statusCode})');
      }

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Configuration des adhans enregistrée'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Impossible de sauvegarder: $e';
        _isSaving = false;
      });
    }
  }

  Future<void> _playTestAdhan(int track) async {
    try {
      if (_deviceIp == null) return;

      final url = Uri.parse('http://$_deviceIp/play?track=$track');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('▶️ Lecture track ${track.toString().padLeft(4, '0')}.mp3'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur ${response.statusCode}: ${response.body}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur connexion: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Configuration des Adhans',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF1B5E20),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Erreur: $_errorMessage',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🎵 Sélectionner un adhan par prière',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._prayerNames.entries.map((entry) {
                              final prayerKey = entry.key;
                              final prayerName = entry.value;
                              final selectedTrack = _selectedTracks[prayerKey]!;
                              final playDuaa = _playDuaa[prayerKey]!;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prayerName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButton<int>(
                                            isExpanded: true,
                                            value: selectedTrack,
                                            items: List.generate(
                                              10, // Max track 11 -> so 10 items starting at 2
                                              (index) {
                                                final trackNum = index + 2;
                                                return DropdownMenuItem(
                                                value: trackNum, // Starts at track 2
                                                child: Text(
                                                  'Track ${trackNum.toString().padLeft(4, '0')}.mp3 (${_getTrackLabel(trackNum)})',
                                                ),
                                              );
                                              },
                                            ),
                                            onChanged: (value) {
                                              if (value != null) {
                                                setState(() {
                                                  _selectedTracks[prayerKey] =
                                                      value;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.play_circle),
                                          color: Colors.green,
                                          onPressed: () =>
                                              _playTestAdhan(selectedTrack),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        'Jouer le duaa après l\'adhan (track 1)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      value: playDuaa,
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() {
                                            _playDuaa[prayerKey] = value;
                                          });
                                        }
                                      },
                                    ),
                                    if (entry.key !=
                                        _prayerNames.keys.last)
                                      Divider(
                                        color: Colors.grey[300],
                                        height: 24,
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveConfiguration,
                      icon: const Icon(Icons.save),
                      label: _isSaving
                          ? const Text('Enregistrement...')
                          : const Text('Enregistrer la configuration'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: const Color(0xFF1B5E20),
                        disabledBackgroundColor: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
    );
  }
}
