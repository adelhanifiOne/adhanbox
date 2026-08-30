// lib/utils/autorisation.dart
//
// Récupérer le droit de piloter une box, depuis n'importe quel écran.
//
// Le firmware ne publie son jeton d'API que pendant les 10 minutes qui suivent
// son branchement (handleDeviceInfo). Un téléphone ajouté hors de cette
// fenêtre n'a donc aucun jeton : tout ce qui est protégé refuse — LED, azkar,
// Coran, volume — et seul l'adhan passe, /play étant la seule route ouverte.
//
// L'app SAIT qu'elle est refusée : elle reçoit un 401. Elle doit donc proposer
// la réparation au moment du refus, pas laisser l'utilisateur chercher un
// réglage. C'est tout l'objet de ce fichier.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/adhanbox_provider.dart';
import '../services/adhanbox_api.dart';
import '../theme/app_theme.dart';
import 'friendly_error.dart';

/// Un seul dialogue d'autorisation à la fois.
///
/// Le curseur de luminosité envoie une commande à chaque cran : sans ce
/// verrou, un refus ouvrirait une vingtaine de popups empilés en un seul
/// glissement. La garde vit ici, pas dans chaque écran — c'est une propriété
/// du parcours, pas de ses appelants.
bool _dialogueEnCours = false;

/// Affiche une erreur venant de la box — et, si c'est un refus d'autorisation,
/// propose de le réparer immédiatement plutôt que de constater la panne.
///
/// À utiliser partout où l'on affichait un simple message d'erreur.
Future<void> afficherErreurBox(
  BuildContext context,
  WidgetRef ref,
  Object? erreur, {
  String? repli,
  VoidCallback? reessayer,
}) async {
  if (!context.mounted) return;

  if (!estRefusAutorisation(erreur)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(messageAmical(erreur, repli: repli)),
      backgroundColor: Colors.red.shade700,
    ));
    return;
  }

  if (_dialogueEnCours) return;
  _dialogueEnCours = true;
  try {
    await _proposerReparation(context, ref, reessayer);
  } finally {
    _dialogueEnCours = false;
  }
}

Future<void> _proposerReparation(
  BuildContext context,
  WidgetRef ref,
  VoidCallback? reessayer,
) async {
  final reparer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ce téléphone n\'est pas autorisé'),
      content: const Text(
        "Votre AdhanBox n'accepte les commandes que des téléphones qu'elle "
        "a autorisés. Celui-ci ne l'est pas encore : il peut lancer l'adhan, "
        "mais pas régler la lumière ni les récitations.\n\n"
        "L'autorisation prend moins d'une minute.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Autoriser'),
        ),
      ],
    ),
  );

  if (reparer != true || !context.mounted) return;
  final obtenu = await autoriserCeTelephone(context, ref);
  if (obtenu && reessayer != null) reessayer();
}

/// Le parcours complet : expliquer, attendre le redémarrage, saisir le jeton.
///
/// Renvoie true si le téléphone est désormais autorisé.
///
/// La clé de la porte, c'est la prise électrique : débrancher puis rebrancher
/// rouvre la fenêtre. On ne passe surtout PAS par un réappairage Bluetooth,
/// qui couperait la box du Wi-Fi et compliquerait tout.
Future<bool> autoriserCeTelephone(BuildContext context, WidgetRef ref) async {
  final ip = ref.read(currentDeviceIpProvider);
  if (ip == null || ip.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun appareil connecté.'),
      ));
    }
    return false;
  }

  final pret = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Autoriser ce téléphone'),
      content: const Text(
        "Par sécurité, votre AdhanBox ne donne son autorisation que dans les "
        "10 minutes qui suivent son branchement électrique.\n\n"
        "1. Débranchez votre AdhanBox.\n"
        "2. Rebranchez-la. Ne touchez à rien d'autre.\n"
        "3. Laissez cet écran ouvert : l'autorisation sera récupérée "
        "automatiquement dès qu'elle revient en ligne.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("C'est fait"),
        ),
      ],
    ),
  );
  if (pret != true || !context.mounted) return false;

  var annule = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: const Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(
            child: Text("En attente de la box…\n"
                "Elle met environ une minute à revenir en ligne."),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            annule = true;
            Navigator.pop(ctx);
          },
          child: const Text('Annuler'),
        ),
      ],
    ),
  );

  // On attend le jeton FRAIS publié par la box — surtout pas un cache : c'est
  // justement parce que ce téléphone n'en a pas qu'on est ici.
  String? jeton;
  final fin = DateTime.now().add(const Duration(minutes: 5));
  while (!annule && DateTime.now().isBefore(fin)) {
    try {
      final info = await AdhanBoxAPI(
        baseUrl: 'http://$ip',
        timeout: const Duration(seconds: 3),
      ).getDeviceInfo();
      final t = info['token'] as String?;
      if (t != null && t.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('api_token_$ip', t);
        final id = info['device_id'] as String?;
        if (id != null && id.isNotEmpty) {
          await prefs.setString('api_token_id_$id', t);
        }
        ref.read(adhanboxApiKeyProvider.notifier).state = t;
        jeton = t;
        break;
      }
    } catch (_) {
      // box en plein redémarrage : normal, on repassera
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  if (annule || !context.mounted) return false;
  Navigator.pop(context); // ferme l'attente

  if (jeton != null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Téléphone autorisé — vous avez le contrôle complet.'),
      backgroundColor: AppTheme.emerald,
    ));
    return true;
  }

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text(
        "La box n'a pas rouvert sa fenêtre d'autorisation. Vérifiez qu'elle a "
        "bien été débranchée puis rebranchée, et réessayez."),
    backgroundColor: Colors.red.shade700,
  ));
  return false;
}
