import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/adhanbox_provider.dart';

class MawaqitOffsetsScreen extends ConsumerStatefulWidget {
  const MawaqitOffsetsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MawaqitOffsetsScreen> createState() =>
      _MawaqitOffsetsScreenState();
}

class _MawaqitOffsetsScreenState extends ConsumerState<MawaqitOffsetsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  final Map<String, int> _offsets = {
    'fajr': 0,
    'sunrise': 0,
    'dhuhr': 0,
    'asr': 0,
    'maghrib': 0,
    'isha': 0,
  };

  final Map<String, String> _prayerNames = {
    'fajr': 'Fajr',
    'sunrise': 'Lever du soleil',
    'dhuhr': 'Dhuhr',
    'asr': 'Asr',
    'maghrib': 'Maghrib',
    'isha': 'Isha',
  };

  final Map<String, IconData> _prayerIcons = {
    'fajr': Icons.nights_stay,
    'sunrise': Icons.wb_sunny,
    'dhuhr': Icons.wb_sunny_outlined,
    'asr': Icons.light_mode,
    'maghrib': Icons.wb_twilight,
    'isha': Icons.dark_mode,
  };

  @override
  void initState() {
    super.initState();
    _loadOffsets();
  }

  Future<void> _loadOffsets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deviceIp = ref.read(currentDeviceIpProvider);
      if (deviceIp == null) {
        setState(() {
          _errorMessage = 'Aucun appareil sélectionné';
          _isLoading = false;
        });
        return;
      }

      final url = Uri.parse('http://$deviceIp/api/mawaqit/offsets');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('Timeout', 408),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _offsets['fajr'] = data['fajr'] ?? 0;
          _offsets['sunrise'] = data['sunrise'] ?? 0;
          _offsets['dhuhr'] = data['dhuhr'] ?? 0;
          _offsets['asr'] = data['asr'] ?? 0;
          _offsets['maghrib'] = data['maghrib'] ?? 0;
          _offsets['isha'] = data['isha'] ?? 0;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Erreur lors du chargement: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveOffsets() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final deviceIp = ref.read(currentDeviceIpProvider);
      if (deviceIp == null) {
        setState(() {
          _errorMessage = 'Aucun appareil sélectionné';
          _isSaving = false;
        });
        return;
      }

      final url = Uri.parse('http://$deviceIp/api/mawaqit/offsets');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_offsets),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('Timeout', 408),
      );

      if (response.statusCode == 200) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Ajustements sauvegardés'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          // Trigger a new sync to apply offsets
          await _triggerSync();
        }
      } else {
        setState(() {
          _errorMessage = 'Erreur lors de la sauvegarde: ${response.statusCode}';
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: $e';
        _isSaving = false;
      });
    }
  }

  Future<void> _triggerSync() async {
    try {
      final deviceIp = ref.read(currentDeviceIpProvider);
      if (deviceIp == null) return;

      final url = Uri.parse('http://$deviceIp/api/mawaqit/sync');
      await http.post(url).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Sync trigger error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustement des horaires'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.tune,
                            size: 48,
                            color: Color(0xFF2E7D32),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Fine Tuning',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ajustez chaque horaire de prière pour correspondre exactement aux horaires de votre mosquée locale',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ..._offsets.keys.map((prayer) {
                    return _buildOffsetSlider(prayer);
                  }).toList(),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveOffsets,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving
                        ? 'Sauvegarde en cours...'
                        : 'Sauvegarder et synchroniser'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _offsets.updateAll((key, value) => 0);
                      });
                    },
                    child: const Text('Réinitialiser tous les ajustements'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOffsetSlider(String prayer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _prayerIcons[prayer],
                  color: const Color(0xFF2E7D32),
                ),
                const SizedBox(width: 12),
                Text(
                  _prayerNames[prayer]!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _offsets[prayer]! == 0
                        ? Colors.grey[200]
                        : (_offsets[prayer]! > 0
                            ? Colors.green[100]
                            : Colors.orange[100]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _offsets[prayer]! == 0
                        ? 'Aucun ajustement'
                        : '${_offsets[prayer]! > 0 ? '+' : ''}${_offsets[prayer]} min',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _offsets[prayer]! == 0
                          ? Colors.grey[700]
                          : (_offsets[prayer]! > 0
                              ? Colors.green[800]
                              : Colors.orange[800]),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '-30',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _offsets[prayer]!.toDouble(),
                    min: -30,
                    max: 30,
                    divisions: 60,
                    activeColor: const Color(0xFF2E7D32),
                    inactiveColor: Colors.grey[300],
                    onChanged: (value) {
                      setState(() {
                        _offsets[prayer] = value.round();
                      });
                    },
                  ),
                ),
                Text(
                  '+30',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            if (_offsets[prayer]! != 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _offsets[prayer]! > 0
                      ? 'Ajouté ${_offsets[prayer]} minute${_offsets[prayer]! > 1 ? 's' : ''} après l\'horaire calculé'
                      : 'Retiré ${-_offsets[prayer]!} minute${-_offsets[prayer]! > 1 ? 's' : ''} avant l\'horaire calculé',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
