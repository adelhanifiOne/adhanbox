import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
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

  Future<void> _verifyConnection() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    int attempts = 0;
    const maxAttempts = 5;
    Exception? lastError;

    while (attempts < maxAttempts) {
      attempts++;
      try {
        developer.log('Tentative $attempts/$maxAttempts: connexion à 192.168.4.1/dump_status');
        
        setState(() {
          _error = 'Tentative $attempts/$maxAttempts...';
        });
        
        final response = await http
            .get(Uri.parse('http://192.168.4.1/dump_status'))
            .timeout(const Duration(seconds: 30));

        developer.log('Réponse reçue - statut: ${response.statusCode}');

        if (response.statusCode == 200) {
          developer.log('Succès!');
          setState(() {
            _step = 2;
            _isLoading = false;
            _error = null;
          });
          return;
        } else {
          lastError = Exception('Statut HTTP: ${response.statusCode}');
        }
      } catch (e) {
        developer.log('Tentative $attempts échouée: $e', error: e);
        lastError = e as Exception;
        
        if (attempts < maxAttempts) {
          developer.log('Attente 5 secondes avant prochaine tentative');
          await Future.delayed(const Duration(seconds: 5));
        }
      }
    }

    // Toutes les tentatives ont échoué
    setState(() {
      _error = 'Impossible après $maxAttempts tentatives.\n\n'
          'Erreur: ${lastError.toString()}\n\n'
          'Assurez-vous que:\n'
          '1. Vous êtes connecté au WiFi AdhanBox\n'
          '2. L\'ESP32 est alimenté\n'
          '3. Vous êtes proche de l\'appareil';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration AdhanBox'),
      ),
      body: _step == 1 ? _buildStep1() : _buildStep2(),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📱 Étape 1: Connexion au WiFi',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.blue[50],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Instructions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Allez dans Paramètres > WiFi\n'
                    '2. Connectez-vous à "AdhanBox_XXXX"\n'
                    '3. Revenez ici et appuyez sur le bouton',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Card(
              color: Colors.red[100],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _verifyConnection,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _isLoading ? 'Vérification en cours...' : 'Vérifier la connexion',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✅ Connexion réussie!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.green[100],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'L\'AdhanBox est accessible!',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
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
              label: const Text('Continuer vers configuration'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


