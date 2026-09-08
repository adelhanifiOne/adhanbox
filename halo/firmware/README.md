# Firmware Halo v1

Sketch Arduino pour l'ESP32-C3-MINI-1 du Halo, dérivé du firmware AdhanBox V3
(`adhanbox_v3/`) sans audio, sans microSD, sans RTC. L'app AdhanBox lui parle
exactement comme à une box : mêmes UUID BLE, mêmes routes HTTP, même jeton.

| Fichier | Rôle |
|---|---|
| `halo/halo.ino` | Le firmware, un seul fichier, ~2400 lignes |
| `halo/build_opt.h` | `-DUPDATE_SIGN` : les OTA non signées sont refusées |
| `../../firmware_version_halo.json` | Manifeste OTA lu par l'app (canal `halo`) |
| `../../deploy_firmware_halo.py` | Compile, signe, publie (comme `deploy_firmware_v2.py`) |

## Compiler

Carte : `esp32:esp32:esp32c3`, options `PartitionScheme=min_spiffs` (deux
partitions OTA de 1,9 Mo) et `CDCOnBoot=cdc` (le port USB natif est le seul
port série du Halo). Bibliothèques : Adafruit NeoPixel ; tout le reste vient du
core arduino-esp32 3.x (BLE, WebServer, Preferences, Update, ArduinoOTA, ESPmDNS,
HTTPClient, WiFiClientSecure).

```
arduino-cli compile --fqbn esp32:esp32:esp32c3:PartitionScheme=min_spiffs,CDCOnBoot=cdc \
  --libraries ~/Documents/Arduino/libraries --output-dir build_temp_halo halo/firmware/halo
```

`deploy_firmware_halo.py` fait cette compilation, signe le binaire avec
`keys/ota_private.pem` (même clé que V2 et V3), écrit
`firmware_version_halo.json` et pousse sur `main`.

Ce firmware n'a pas encore été compilé sur une vraie chaîne arduino-esp32
(environnement de génération sans accès aux dépôts Espressif) : seule une
vérification de syntaxe et de noms sur l'hôte a été faite. Première compilation
à faire sur le Mac de développement, comme pour la V3.

## Premier flash

Pas de CP2102 : USB-C sur le PC, maintenir SW2 (BOOT), appuyer SW1 (RESET),
relâcher SW2. Le C3 apparaît en port série USB, `esptool` flashe directement.
Ensuite l'OTA par l'app (`/ota/upload`) ou ArduinoOTA (`espota.py`) suffit.

## Ce que fait le Halo

- **Démarrage** : Wi-Fi mémorisé (15 s), sinon appairage BLE `AdhanBox-XXXXXX`
  pendant 5 min (anneau rouge clignotant). Puis NTP, resynchronisé toutes les
  heures. Tant qu'il n'y a pas d'heure, l'anneau respire en blanc faible.
- **Heure sans RTC** : l'horloge système du C3 tourne sur son timer RTC
  interne, qui survit à un reset logiciel (OTA, watchdog, appairage) et ne
  repart à zéro que sur coupure de courant. L'heure est sauvegardée en NVS
  toutes les 15 min ; après un reset logiciel, si l'horloge interne est
  cohérente avec cette sauvegarde, elle est gardée (source `carry`) et le
  halo en cours reprend là où il en était. Le NTP est alors retenté toutes
  les 5 min. Sur coupure de courant : pas d'heure jusqu'au NTP ou au
  téléphone.
- **Heure de secours** : l'app envoie l'heure du téléphone (`/set_rtc_manual`)
  à l'appairage puis toutes les 10 min ; elle est prise tant que le NTP n'a
  pas répondu, ce qui rend le Halo utilisable sur un Wi-Fi sans internet.
- **Déclenchement** : pas d'alarme matérielle, le Halo est toujours alimenté.
  Une fois par seconde, la boucle compare l'heure locale à la prochaine
  prière ; anti-doublon par jour en NVS, comme la V3.
- **Prières** : calcul local (NOAA, méthodes MWL/ISNA/UOIF/Egypte/Karachi/
  personnalisée) ou Mawaqit si une mosquée est configurée (synchro toutes les
  20 h, repli Aladhan), décalages par prière. À l'heure dite, le **halo** :
  scène « prière » (respiration turquoise avec un point qui tourne) pendant
  `halo_min` minutes (15 par défaut), puis retour à la scène précédente.
  Prières activables une à une (`/api/adhan/config`, mêmes clés que la V3).
- **Bouton** (IO3) : appui court = arrêt du halo en cours, sinon allume/éteint ;
  appui long (0,7 s) = scène suivante ; 5 s = redémarrage en appairage BLE.
- **Capteur de lumière** (IO4) : mode nuit automatique, l'anneau se limite à
  `night_brightness` % (15 par défaut) quand la pièce est sombre. Hystérésis
  x1,3. Désactivable, et réglage « capteur absent ».
- **Luminosité** : réglage 0-100 de l'app, plafonné à 60 % dans le firmware
  (budget USB, SCHEMA.md §5).
- **Scènes** : mêmes numéros que la V3 (0 éteint, 1-6 couleurs fixes, 8
  arc-en-ciel, 9 dégradé, 10 prière, 11 ciel étoilé, 12 bougie, 13 vague, 14
  aube), plus la couleur libre de la roue chromatique.
- **Sécurité** : jeton `X-API-Key` généré au premier démarrage, OTA signée
  ECDSA P-256 avec rollback automatique, watchdog 30 s, remise à zéro usine
  (`/api/factory_reset` avec l'identifiant de la carte, ou `t:usine` par USB).

## API propre au Halo

En plus des routes V3 (voir `adhanbox_v3.ino`, `setupServerRoutes`) :

| Route | Rôle |
|---|---|
| `GET /api/halo/config` | `duration_min`, `night_auto`, `night_threshold` (ADC 0-4095), `night_brightness`, `sensor_present`, `brightness_cap` |
| `POST /api/halo/config` | Mêmes clés, toutes optionnelles. Jeton requis |
| `GET /api/halo/status` | Halo en cours, prière, secondes restantes, ADC, nuit, heure, prochaine prière |
| `POST /api/halo/stop` | Arrête le halo en cours |
| `POST /api/halo/test?minutes=1` | Lance un halo de test |
| `GET /api/time` | `time`, `tz_min`, `ok`, `source` (`ntp`, `phone`, `carry`, `none`) |

Les routes audio de la V3 répondent « rien ne joue » (`"audio":false`) pour
que l'app, qui les sonde sur toutes les box, ne tombe pas en erreur.
`/api/device/info` et `/api/firmware/version` annoncent `"hardware":"halo"`,
et l'app route l'OTA sur `firmware_version_halo.json` d'après ce champ.

## Banc de production

Par le câble USB, réponses sur une ligne préfixée `<BANC>` : `t:info`
(matériel, version, identifiant, jeton), `t:diag` (RAM, ADC, bouton, heure,
Wi-Fi), `t:led N` (scène N), `t:usine` (remise à zéro et redémarrage). Une
carte neuve en attente d'appairage sort de l'attente à la première commande.

## À faire côté app

L'app n'a pas de notion de produit sans haut-parleur : les onglets Adhan,
Azkar/Coran et le mini-lecteur s'affichent pour un Halo, inopérants. Le champ
`hardware` de `/api/device/info` est le point d'ancrage pour les masquer.
