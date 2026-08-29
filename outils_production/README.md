# Banc de production AdhanBox V3

Flashe une carte et la teste de A à Z, puis archive un rapport par numéro de
série.

```bash
python3 outils_production/banc_gui.py
```

Ça ouvre une fenêtre dans le navigateur. **Chaque contrôle a son propre bouton
▶** : tu lances celui que tu veux, quand tu veux, autant de fois que tu veux.
« Tout tester » enchaîne simplement les treize.

Rien à installer — un petit serveur local, et une page qui l'interroge.

## Le déroulé d'un boîtier

1. **Flasher le firmware** — compile si besoin, téléverse par USB, attend.
2. **Chercher la carte** — mDNS, point d'accès, ou l'adresse que tu saisis.
3. **Tout tester** — l'outil s'arrête aux questions et aux appuis.
4. **N° de série** puis **Enregistrer le rapport**.
5. **Carte suivante** — remet les compteurs à zéro.

Un contrôle en échec ? Corrige, et relance **ce seul contrôle** avec son ▶.

## En ligne de commande

L'interface n'est qu'une façade : les contrôles vivent dans `banc_test.py`, qui
s'utilise aussi seul.

| commande | ce qu'elle fait |
|---|---|
| `flash` | téléverse le firmware par USB (port auto-détecté) |
| `test` | teste une carte déjà flashée, par le réseau |
| `serie` | enchaîne les deux, avec l'attente de redémarrage |

Options : `--port` si plusieurs cartes sont branchées, `--recompiler` pour
forcer la compilation, `--hote <ip>` si la carte n'est pas trouvée toute seule,
`--sans-operateur` pour ne lancer que les contrôles automatiques.

## Ce qui est testé

**Sans intervention** — l'outil interroge la carte et juge seul :

| contrôle | critère |
|---|---|
| Identité | matériel = v3, version du firmware, identifiant unique |
| PSRAM | présente — son absence était la loterie des modules V2 |
| Débit carte SD | ≥ 16 ko/s, le seuil sous lequel l'audio se coupe |
| Mémoire libre | > 60 ko de tas |
| Contenu audio | les 4 automatismes s'ouvrent et démarrent (voir plus bas) |
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

Trois verdicts, et la nuance compte :

| verdict | quand |
|---|---|
| `CONFORME` | les 13 contrôles joués, les 13 passés |
| `NON CONFORME` | au moins un échec — **ne pas expédier** |
| `PARTIEL` | tout est passé, mais tout n'a pas été joué |

`PARTIEL` liste nommément ce qui n'a pas été fait. Un rapport ne prétend jamais
plus que ce qui a vraiment été mesuré — c'est toute la différence entre une
preuve et une impression. Pour la même raison, l'outil efface les résultats dès
qu'il voit une autre carte ou qu'un flash a réussi, et un contrôle interrompu
n'est pas compté en échec : il reste simplement à refaire.

Ce n'est pas de la décoration. Ton email client annonce que chaque boîtier est
testé — « audio, lumière, connexion et déclenchement de l'adhan à l'heure » —
et la pièce 05 de ton dossier CE décrit un contrôle unitaire. Ces fichiers en
sont la preuve, datée et par numéro de série. Garde-les avec le dossier
technique.

## Trouver la carte sur le réseau

L'outil essaie `adhanbox.local` (mDNS), puis `192.168.4.1` (le point d'accès
que la box ouvre quand elle n'a pas de Wi-Fi). Sinon, saisis l'adresse.

## Le jeton, et sa fenêtre de 10 minutes

Le jeton d'API est récupéré tout seul — mais le firmware ne le publie que
pendant la **fenêtre d'appairage** : en mode point d'accès, ou dans les
10 minutes qui suivent le démarrage (`handleDeviceInfo`, `adhanbox_v3.ino`).
Passé ce délai, `/api/device/info` répond `paired: true` sans le jeton, et
toute route qui **modifie** quelque chose renvoie 401.

En production, on flashe puis on teste : la carte vient de redémarrer, on est
toujours dans la fenêtre. Le problème n'apparaît que sur un boîtier allumé
depuis un moment — un exemplaire d'atelier, typiquement.

Deux remèdes, et l'interface les affiche d'elle-même dès qu'elle voit une
carte sans jeton :

- **débrancher puis rebrancher la carte**, et recliquer sur « Chercher la
  carte » — la fenêtre se rouvre pour 10 minutes ;
- **coller le jeton** dans le champ prévu (ou `--jeton` en ligne de commande),
  si tu l'as.

À ne pas faire : appeler `/api/pair` pour forcer un redémarrage. Cette route
redémarre bien la carte, mais en mode appairage BLE — qui **saute la
reconnexion Wi-Fi**. La carte sortirait du réseau, et le banc la perdrait.

Six des sept contrôles automatiques ne lisent que des routes ouvertes : ils
passent dans tous les cas. Le septième — le contenu audio — ouvre les fichiers,
et demande donc le jeton.

## Pourquoi le contenu ne se vérifie pas par la liste

`/api/audio/list` **exclut volontairement `/quran`** (`v2ListDir`) : les 456
récitations feraient expirer l'app et fragmenteraient la RAM. Al-Kahf et
Al-Mulk n'y figurent donc jamais, même bien présentes sur la carte.

Le banc les ouvre une par une via `/api/audio/play?f=…`, exactement comme
`v2Fire()` le fait à l'heure dite. C'est une preuve plus forte qu'une présence
dans une liste : le décodeur démarre vraiment, et on relève la taille du
fichier au passage. Chaque ouverture est stoppée aussitôt — quatre brefs
sons pendant le contrôle, c'est normal.

## Codes de sortie

`0` conforme · `1` carte introuvable ou flash échoué · `2` non conforme.
De quoi enchaîner dans un script si tu automatises davantage.
