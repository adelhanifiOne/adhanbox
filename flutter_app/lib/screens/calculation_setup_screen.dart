import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/prayer_time.dart';
import '../providers/adhanbox_provider.dart';

class CalculationSetupScreen extends ConsumerStatefulWidget {
  const CalculationSetupScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CalculationSetupScreen> createState() =>
      _CalculationSetupScreenState();
}

class _CalculationSetupScreenState
    extends ConsumerState<CalculationSetupScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _deviceIp;

  // Configuration actuelle
  String _method = 'mwl'; // Muslim World League par défaut
  int _school = 0; // Shafi par défaut
  
  // Offsets pour fine-tuning
  final Map<String, int> _offsets = {
    'fajr': 0,
    'sunrise': 0,
    'dhuhr': 0,
    'asr': 0,
    'maghrib': 0,
    'isha': 0,
  };

  // Preview des horaires
  Map<String, String> _basePreviewTimes = {};
  Map<String, String> _previewTimes = {};

  final Map<String, String> _methods = {
    'mwl': 'Ligue islamique mondiale (MWL)',
    'karachi': 'Université des sciences islamiques (Karachi)',
    'uoif': 'Union des organisations islamiques de France (UOIF)',
    'egypt': 'Autorité générale égyptienne de sondage',
    'isna': 'ISNA (Amérique du Nord)',
  };

  final Map<int, String> _schools = {
    0: 'École Shafi (standard)',
    1: 'École Hanafi',
  };

  final Map<String, String> _prayerNames = {
    'fajr': 'Fajr',
    'sunrise': 'Chourouk',
    'dhuhr': 'Dhuhr',
    'asr': 'Asr',
    'maghrib': 'Maghrib',
    'isha': 'Isha',
  };

  final Map<String, IconData> _prayerIcons = {
    'fajr': Icons.wb_twilight,
    'sunrise': Icons.wb_sunny,
    'dhuhr': Icons.wb_sunny_outlined,
    'asr': Icons.light_mode,
    'maghrib': Icons.wb_twilight,
    'isha': Icons.nights_stay,
  };

  @override
  void initState() {
    super.initState();
    // Charger l'IP depuis les SharedPreferences via le provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadIpAndConfig();
    });
  }

  Future<void> _loadIpAndConfig() async {
    try {
      // Charger l'IP depuis le provider (FutureProvider)
      final deviceIpAsync = await ref.read(deviceIpProvider.future);
      
      if (deviceIpAsync == null) {
        setState(() {
          _errorMessage = 'Aucun appareil configuré';
          _isLoading = false;
        });
        return;
      }
      
      setState(() => _deviceIp = deviceIpAsync);
      await _loadConfiguration();
    } catch (e) {
      debugPrint('IP loading error: $e');
      setState(() {
        _errorMessage = 'Erreur au chargement de l\'IP: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_deviceIp == null) {
        setState(() {
          _errorMessage = 'Aucun appareil connecté';
          _isLoading = false;
        });
        return;
      }

      // Charger la config de calcul (continue même si ça échoue)
      try {
        final configUrl = Uri.parse('http://$_deviceIp/api/calculation/config');
        final configResponse = await http.get(configUrl).timeout(
          const Duration(seconds: 5),
        );

        if (configResponse.statusCode == 200) {
          final data = jsonDecode(configResponse.body);
          setState(() {
            final methodFromApi = (data['method'] ?? 'mwl').toString().toLowerCase();
            _method = _methods.containsKey(methodFromApi) ? methodFromApi : 'mwl';
            _school = data['school'] ?? 0;
          });
        }
      } catch (e) {
        debugPrint('Config load error: $e (using defaults)');
      }

      // Charger les offsets (continue même si ça échoue)
      try {
        final offsetsUrl = Uri.parse('http://$_deviceIp/api/mawaqit/offsets');
        final offsetsResponse = await http.get(offsetsUrl).timeout(
          const Duration(seconds: 5),
        );

        if (offsetsResponse.statusCode == 200) {
          final data = jsonDecode(offsetsResponse.body);
          setState(() {
            _offsets['fajr'] = data['fajr'] ?? 0;
            _offsets['sunrise'] = data['sunrise'] ?? 0;
            _offsets['dhuhr'] = data['dhuhr'] ?? 0;
            _offsets['asr'] = data['asr'] ?? 0;
            _offsets['maghrib'] = data['maghrib'] ?? 0;
            _offsets['isha'] = data['isha'] ?? 0;
          });
        }
      } catch (e) {
        debugPrint('Offsets load error: $e (using defaults)');
      }

      // Charger le preview des horaires
      try {
        await _loadPreview();
      } catch (e) {
        debugPrint('Preview load error: $e');
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Config initialization error: $e');
      setState(() {
        _errorMessage = 'Erreur de connexion au ESP32';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPreview() async {
    try {
      if (_deviceIp == null) return;

      final url = Uri.parse('http://$_deviceIp/prayer_times');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final base = {
          'fajr': (data['fajr'] ?? '--:--').toString(),
          'sunrise': (data['sunrise'] ?? '--:--').toString(),
          'dhuhr': (data['dhuhr'] ?? '--:--').toString(),
          'asr': (data['asr'] ?? '--:--').toString(),
          'maghrib': (data['maghrib'] ?? '--:--').toString(),
          'isha': (data['isha'] ?? '--:--').toString(),
        };
        setState(() {
          _basePreviewTimes = base;
          _previewTimes = _applyOffsetsToTimes(base, _offsets);
        });
      }
    } catch (e) {
      debugPrint('Preview load error: $e');
    }
  }

  Future<void> _refreshPreviewForMethodOrSchool() async {
    if (_deviceIp == null) return;
    try {
      final configUrl = Uri.parse('http://$_deviceIp/api/calculation/config');
      final response = await http.post(
        configUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'method': _method, 'school': _school}),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _loadPreview();
      }
    } catch (e) {
      debugPrint('Live method/school preview error: $e');
    }
  }

  Map<String, String> _applyOffsetsToTimes(
    Map<String, String> base,
    Map<String, int> offsets,
  ) {
    final result = <String, String>{};
    for (final key in _prayerNames.keys) {
      final source = base[key] ?? '--:--';
      result[key] = _addMinutes(source, offsets[key] ?? 0);
    }
    return result;
  }

  String _addMinutes(String time, int delta) {
    final parts = time.split(':');
    if (parts.length != 2) return time;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return time;

    var total = h * 60 + m + delta;
    while (total < 0) total += 24 * 60;
    while (total >= 24 * 60) total -= 24 * 60;
    final hh = (total ~/ 60).toString().padLeft(2, '0');
    final mm = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _saveAndApply() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      if (_deviceIp == null) {
        throw Exception('Aucun appareil connecté');
      }

      // Sauvegarder la méthode de calcul
      final configUrl = Uri.parse('http://$_deviceIp/api/calculation/config');
      final configResponse = await http.post(
        configUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'method': _method, 'school': _school}),
      ).timeout(const Duration(seconds: 10));

      if (configResponse.statusCode < 200 || configResponse.statusCode >= 300) {
        throw Exception('Échec sauvegarde configuration (HTTP ${configResponse.statusCode})');
      }

      // Sauvegarder les offsets (optionnel si endpoint indisponible)
      try {
        final offsetsUrl = Uri.parse('http://$_deviceIp/api/mawaqit/offsets');
        await http.post(
          offsetsUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_offsets),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}

      // Recharger le preview
      await _loadPreview();
      
      // Invalider les providers pour rafraîchir
      ref.invalidate(prayerTimesProvider);
      ref.invalidate(prayerOffsetsProvider);
      ref.invalidate(adjustedPrayerTimesProvider);

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Configuration enregistrée'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Impossible de sauvegarder (${_deviceIp ?? 'IP inconnue'}): $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerPreview = _previewFromPrayerTimes(ref.watch(prayerTimesProvider).valueOrNull);

    if (_basePreviewTimes.isEmpty && providerPreview.isNotEmpty && _previewTimes.isEmpty) {
      _basePreviewTimes = Map<String, String>.from(providerPreview);
      _previewTimes = _applyOffsetsToTimes(_basePreviewTimes, _offsets);
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Configuration des horaires',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF1B5E20),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header avec preview des horaires
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF1B5E20),
                          const Color(0xFF2E7D32),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Aperçu des horaires',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_deviceIp != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Appareil: $_deviceIp',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _buildPreviewGrid(providerPreview),
                      ],
                    ),
                  ),

                  // Configuration
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red[700]),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Méthode de calcul
                        _buildSectionHeader('Méthode de calcul', Icons.calculate),
                        const SizedBox(height: 12),
                        _buildMethodSelector(),
                        const SizedBox(height: 24),

                        // École juridique
                        _buildSectionHeader('École juridique', Icons.school),
                        const SizedBox(height: 12),
                        _buildSchoolSelector(),
                        const SizedBox(height: 32),

                        // Fine-tuning
                        _buildSectionHeader('Ajustements fins', Icons.tune),
                        const SizedBox(height: 8),
                        Text(
                          'Ajustez chaque horaire si nécessaire',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._buildOffsetSliders(providerPreview),
                        const SizedBox(height: 32),

                        // Bouton de sauvegarde
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveAndApply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Enregistrer',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPreviewGrid(Map<String, String> providerPreview) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildPreviewItem('fajr', providerPreview)),
              const SizedBox(width: 12),
              Expanded(child: _buildPreviewItem('sunrise', providerPreview)),
              const SizedBox(width: 12),
              Expanded(child: _buildPreviewItem('dhuhr', providerPreview)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPreviewItem('asr', providerPreview)),
              const SizedBox(width: 12),
              Expanded(child: _buildPreviewItem('maghrib', providerPreview)),
              const SizedBox(width: 12),
              Expanded(child: _buildPreviewItem('isha', providerPreview)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewItem(String prayer, Map<String, String> providerPreview) {
    final time = _previewTimes[prayer] ?? providerPreview[prayer] ?? '--:--';
    return Column(
      children: [
        Icon(
          _prayerIcons[prayer],
          color: Colors.white,
          size: 24,
        ),
        const SizedBox(height: 6),
        Text(
          _prayerNames[prayer]!,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Map<String, String> _previewFromPrayerTimes(PrayerTimes? prayerTimes) {
    if (prayerTimes == null) return const {};
    final Map<String, String> result = {};
    for (final prayer in prayerTimes.times) {
      final key = prayer.name.toLowerCase();
      if (key.contains('fajr')) result['fajr'] = prayer.calculatedTime;
      if (key.contains('sunrise') || key.contains('chour') || key.contains('shuru')) result['sunrise'] = prayer.calculatedTime;
      if (key.contains('dhuhr') || key.contains('dohr')) result['dhuhr'] = prayer.calculatedTime;
      if (key.contains('asr')) result['asr'] = prayer.calculatedTime;
      if (key.contains('maghrib')) result['maghrib'] = prayer.calculatedTime;
      if (key.contains('isha')) result['isha'] = prayer.calculatedTime;
    }
    return result;
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1B5E20), size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: _methods.entries.map((entry) {
          final isSelected = _method == entry.key;
          return InkWell(
            onTap: () {
              setState(() => _method = entry.key);
              _refreshPreviewForMethodOrSchool();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: entry.key != _methods.keys.last
                      ? BorderSide(color: Colors.grey[200]!)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? const Color(0xFF1B5E20)
                        : Colors.grey[400],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? Colors.black87 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSchoolSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: _schools.entries.map((entry) {
          final isSelected = _school == entry.key;
          return InkWell(
            onTap: () {
              setState(() => _school = entry.key);
              _refreshPreviewForMethodOrSchool();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: entry.key != _schools.keys.last
                      ? BorderSide(color: Colors.grey[200]!)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? const Color(0xFF1B5E20)
                        : Colors.grey[400],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? Colors.black87 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildOffsetSliders(Map<String, String> providerPreview) {
    return _offsets.keys.map((prayer) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _prayerIcons[prayer],
                      color: const Color(0xFF1B5E20),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _prayerNames[prayer]!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _offsets[prayer] == 0
                        ? Colors.grey[200]
                        : const Color(0xFF1B5E20).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _offsets[prayer] == 0
                        ? '0'
                        : '${_offsets[prayer]! > 0 ? '+' : ''}${_offsets[prayer]}\'',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _offsets[prayer] == 0
                          ? Colors.grey[700]
                          : const Color(0xFF1B5E20),
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _offsets[prayer]!.toDouble(),
              min: -30,
              max: 30,
              divisions: 60,
              activeColor: const Color(0xFF1B5E20),
              inactiveColor: Colors.grey[300],
              onChanged: (value) {
                setState(() {
                  _offsets[prayer] = value.round();
                  final source = _basePreviewTimes.isNotEmpty
                      ? _basePreviewTimes
                      : providerPreview;
                  _previewTimes = _applyOffsetsToTimes(source, _offsets);
                });
              },
            ),
          ],
        ),
      );
    }).toList();
  }
}
