import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/adhanbox_provider.dart';
import 'mawaqit_config_screen.dart';

class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen> {
  int _step = 1;
  String? _error;
  bool _isLoading = false;

  Future<void> _connectToAdhanBox() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Simple check: essayer de ping 192.168.4.1
      final response = await http
          .get(Uri.parse('http://192.168.4.1/dump_status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _step = 2;
          _isLoading = false;
        });
      } else {
        throw Exception('Statut: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = 'Impossible de se connecter à l\'AdhanBox.\nVérifiez que vous êtes connecté au WiFi de l\'ESP32';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration AdhanBox'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _step == 1 ? _buildStep1() : _buildStep2(),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📱 Étape 1: Connexion au WiFi AdhanBox',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Card(
          color: Colors.blue,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instructions:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Allez dans les paramètres WiFi de votre téléphone\n'
                  '2. Cherchez et connectez-vous au réseau "AdhanBox_XXXX"\n'
                  '3. Revenez dans cette application\n'
                  '4. Appuyez sur "Vérifier la connexion"',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Card(
            color: Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _connectToAdhanBox,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isLoading ? 'Vérification...' : 'Vérifier la connexion'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '✅ Connexion réussie!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Card(
          color: Colors.green,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.check_circle, size: 48, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'L\'AdhanBox est accessible',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Prochaines étapes:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text('• Configurer le WiFi maison'),
        const Text('• Ajouter votre mosquée (Mawaqit)'),
        const Text('• Régler le fuseau horaire'),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const MawaqitConfigScreen(),
                ),
              );
            },
            icon: const Icon(Icons.mosque),
            label: const Text('Continuer'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
