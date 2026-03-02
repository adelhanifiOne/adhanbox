import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/adhanbox_provider.dart';

class LedControlScreen extends ConsumerStatefulWidget {
  const LedControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LedControlScreen> createState() => _LedControlScreenState();
}

class _LedControlScreenState extends ConsumerState<LedControlScreen> {
  final List<String> _scenarios = [
    'OFF',
    'Rainbow',
    'Prayer Times',
    'Breathing',
    'Party',
  ];

  int _selectedScenario = 0;
  int _brightness = 50;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(deviceStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contrôle LED'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scénario LED',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List.generate(_scenarios.length, (index) {
                      final selected = _selectedScenario == index;
                      return GestureDetector(
                        onTap: () async {
                          setState(() => _selectedScenario = index);
                          // Appel API
                          final api = ref.read(adhanboxApiProvider);
                          if (api != null) {
                            await api.setLedScenario(index);
                          }
                        },
                        child: Card(
                          color: selected ? Colors.green : Colors.grey[200],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lightbulb,
                                  color: selected ? Colors.white : Colors.grey,
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _scenarios[index],
                                  style: TextStyle(
                                    color:
                                        selected ? Colors.white : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Luminosité',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.brightness_low),
                      Expanded(
                        child: Slider(
                          value: _brightness.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (value) async {
                            setState(() => _brightness = value.toInt());
                            final api = ref.read(adhanboxApiProvider);
                            if (api != null) {
                              await api.setLedBrightness(_brightness);
                            }
                          },
                        ),
                      ),
                      const Icon(Icons.brightness_high),
                    ],
                  ),
                  Center(
                    child: Text(
                      '$_brightness%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'État actuel',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  statusAsync.when(
                    data: (status) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatusRow(
                            'Scénario', _scenarios[_selectedScenario]),
                        _buildStatusRow('Luminosité', '$_brightness%'),
                        _buildStatusRow(
                            'État', status['led']?['status'] ?? 'N/A'),
                      ],
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (error, stack) => Text('Erreur: $error'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
