import 'dart:async';
import 'dart:io';

/// Traduit une exception technique en une phrase compréhensible.
///
/// Les messages bruts de Dart (« TimeoutException after 0:00:10.000000:
/// Future not completed », « SocketException: Connection refused »…) n'ont
/// aucun sens pour quelqu'un qui veut juste écouter le Coran. On les
/// remplace par une explication et, surtout, par ce qu'il faut faire.
String messageAmical(Object? erreur, {String? repli}) {
  final defaut = repli ?? "Une erreur est survenue. Réessayez dans un instant.";
  if (erreur == null) return defaut;

  if (erreur is TimeoutException) {
    return "La box ne répond pas. Vérifiez qu'elle est branchée et que "
        "votre téléphone est sur le même réseau Wi-Fi.";
  }

  if (erreur is SocketException) {
    return "Impossible de joindre la box. Vérifiez votre connexion Wi-Fi "
        "et que la box est bien allumée.";
  }

  if (erreur is HttpException || erreur is HandshakeException) {
    return "La connexion avec la box a été interrompue. Réessayez.";
  }

  if (erreur is FormatException) {
    return "La box a envoyé une réponse inattendue. Réessayez, et "
        "redémarrez-la si le problème persiste.";
  }

  // Dernier filet : on inspecte le texte, sans jamais l'afficher tel quel.
  final t = erreur.toString().toLowerCase();

  if (t.contains('timeout') || t.contains('timed out')) {
    return "La box met trop de temps à répondre. Vérifiez qu'elle est "
        "allumée et sur le même réseau Wi-Fi.";
  }
  if (t.contains('connection refused') ||
      t.contains('connection failed') ||
      t.contains('network is unreachable') ||
      t.contains('no route to host') ||
      t.contains('failed host lookup')) {
    return "Impossible de joindre la box. Vérifiez votre Wi-Fi et que la "
        "box est allumée.";
  }
  if (t.contains('401') || t.contains('403') || t.contains('unauthorized')) {
    // Surtout ne pas envoyer vers un reappairage Bluetooth : il couperait la
    // box du Wi-Fi. Le bon remede est le parcours guide des reglages, qui ne
    // demande qu'un debranchement.
    return "Ce téléphone n'est pas autorisé à piloter cette box. "
        "Allez dans Réglages → « Autoriser ce téléphone ».";
  }
  if (t.contains('404')) {
    return "Contenu introuvable sur la box. Vérifiez que la carte mémoire "
        "est bien insérée.";
  }
  if (t.contains('500') || t.contains('502') || t.contains('503')) {
    return "La box a rencontré un problème interne. Redémarrez-la, puis "
        "réessayez.";
  }
  if (t.contains('sd') && (t.contains('mount') || t.contains('card'))) {
    return "La carte mémoire n'est pas lue. Vérifiez qu'elle est bien "
        "enfoncée dans son logement.";
  }

  return defaut;
}
