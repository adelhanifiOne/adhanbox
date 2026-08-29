# Banc de production AdhanBox V3

Flashe une carte et la teste de A à Z, puis archive un rapport par numéro de
série.

```bash
python3 outils_production/banc_test.py serie      # flash + test enchaînés
```

## Les trois commandes

| commande | ce qu'elle fait |
|---|---|
| `flash` | téléverse le firmware par USB (port auto-détecté) |
| `test` | teste une carte déjà flashée, par le réseau |
| `serie` | enchaîne les deux, avec l'attente de redémarrage |

Options utiles : `--port` si plusieurs cartes sont branchées, `--recompiler`
pour forcer la compilation, `--hote <ip>` si la carte n'est pas trouvée toute
seule, `--sans-operateur` pour ne lancer que les contrôles automatiques.

## Ce qui est testé

**Sans intervention** — l'outil interroge la carte et juge seul :

| contrôle | critère |
|---|---|
| Identité | matériel = v3, version du firmware, identifiant unique |
| PSRAM | présente — son absence était la loterie des modules V2 |
| Débit carte SD | ≥ 16 ko/s, le seuil sous lequel l'audio se coupe |
| Mémoire libre | > 60 ko de tas |
| Contenu audio | les 4 fichiers d'automatisme sont sur la carte |
| Horloge temps réel | date plausible |
| Wi-Fi | connectée, avec son SSID et son IP |

**Avec l'opérateur** — ce que seuls les yeux et les oreilles constatent :
les trois couleurs de LED, le réglage de luminosité, le haut-parleur, la
montée du volume.

**Le bouton tactile se vérifie tout seul.** Il fait défiler les scénarios LED
et les enregistre : l'outil lit l'état, te demande d'appuyer, puis constate le
changement. Même principe pour l'arrêt de la lecture. Pas de « oui je crois »,
une vraie mesure.

## Le rapport

Chaque passage écrit `rapports/<serie>_<date>.json` : verdict, identifiant de
l'appareil, version du firmware, et le détail de chaque contrôle.

Ce n'est pas de la décoration. Ton email client annonce que chaque boîtier est
testé — « audio, lumière, connexion et déclenchement de l'adhan à l'heure » —
et la pièce 05 de ton dossier CE décrit un contrôle unitaire. Ces fichiers en
sont la preuve, datée et par numéro de série. Garde-les avec le dossier
technique.

## Trouver la carte sur le réseau

L'outil essaie `adhanbox.local` (mDNS), puis `192.168.4.1` (le point d'accès
que la box ouvre quand elle n'a pas de Wi-Fi). Sinon, passe `--hote`.

**Le jeton d'API est récupéré automatiquement**, mais le firmware ne l'expose
que pendant la fenêtre d'appairage : en mode point d'accès, ou dans les
10 minutes qui suivent le démarrage. Sur un banc de production on est toujours
dedans. Si un test échoue en disant que le jeton manque, redémarre la carte.

## Codes de sortie

`0` conforme · `1` carte introuvable ou flash échoué · `2` non conforme.
De quoi enchaîner dans un script si tu automatises davantage.
