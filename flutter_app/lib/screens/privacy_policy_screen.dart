import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Politique de confidentialité'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('AdhanBox — Politique de confidentialité'),
            _date('Dernière mise à jour : avril 2026'),
            const SizedBox(height: 24),

            _section('1. Données collectées'),
            _body(
              'L\'application AdhanBox collecte uniquement les données strictement nécessaires à son fonctionnement :\n'
              '• Votre position GPS (latitude, longitude) — utilisée uniquement pour calculer les horaires de prière locaux et envoyée directement à votre appareil AdhanBox sur votre réseau local.\n'
              '• L\'adresse IP de votre appareil AdhanBox sur votre réseau local.\n'
              '• Le réseau WiFi sélectionné pour la configuration de l\'appareil.',
            ),
            const SizedBox(height: 16),

            _section('2. Utilisation des données'),
            _body(
              'Toutes les données restent sur votre réseau local et sur votre appareil. '
              'Aucune donnée personnelle n\'est transmise à des serveurs externes, ni partagée avec des tiers.\n\n'
              'La position GPS est :\n'
              '• Transmise uniquement à votre appareil AdhanBox (communication locale)\n'
              '• Non stockée sur des serveurs distants\n'
              '• Non partagée avec des tiers',
            ),
            const SizedBox(height: 16),

            _section('3. Accès à la localisation'),
            _body(
              'L\'application demande l\'accès à votre localisation en premier plan uniquement. '
              'Cet accès est utilisé pour :\n'
              '• Calculer les horaires de prière selon votre position\n'
              '• Rechercher des mosquées à proximité via Mawaqit.net\n\n'
              'L\'accès à la localisation en arrière-plan n\'est pas utilisé.',
            ),
            const SizedBox(height: 16),

            _section('4. Services tiers'),
            _body(
              'L\'application peut contacter les services suivants :\n'
              '• Mawaqit.net — pour récupérer les horaires de prière d\'une mosquée sélectionnée (votre position approximative peut être transmise lors de la recherche de mosquée).\n\n'
              'Ces services sont soumis à leurs propres politiques de confidentialité.',
            ),
            const SizedBox(height: 16),

            _section('5. Stockage local'),
            _body(
              'L\'application stocke localement sur votre téléphone :\n'
              '• L\'adresse IP de votre appareil AdhanBox\n'
              '• Vos préférences (volume, luminosité, thème)\n'
              '• Un token d\'authentification pour sécuriser la communication avec votre appareil\n\n'
              'Ces données ne quittent jamais votre appareil.',
            ),
            const SizedBox(height: 16),

            _section('6. Contact'),
            _body(
              'Pour toute question concernant la confidentialité, contactez-nous à :\n'
              'adel.hanifi@yahoo.fr',
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Text(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );

  Widget _date(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppTheme.darkTextMuted)),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: AppTheme.emerald)),
      );

  Widget _body(String text) => Text(text,
      style: const TextStyle(fontSize: 14, height: 1.6));
}
