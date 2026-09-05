# Halo v1 : schéma électrique et notes de conception

Support de téléphone de bureau avec anneau lumineux, dérivé de l'AdhanBox.
Reprend la logique de l'overlay : anneau à l'entrée d'une prière, 30 min avant
la fin de l'horaire, 10 min avant la fin. Pas d'audio, pas de microSD, pas de RTC.

Fichiers du dossier :

| Fichier | Contenu |
|---|---|
| `Halo_BOM.csv` | BOM PCB au format JLCPCB (mêmes colonnes que `AdhanBoxPCBV3_BOM.csv`) |
| `Halo_BOM_produit.csv` | BOM complète du produit fini : coque, pied, câble, boîte |
| `Halo_schema.svg` | Schéma de principe dessiné, un bloc par feuille ci-dessous |
| `SCHEMA.md` | Ce document : connexions nette par nette, GPIO, budget, placement |

## 1. Périmètre v1

- Alimentation 5 V par USB-C, câble fourni, pas de bloc secteur.
- ESP32-C3-MINI-1 : Wi-Fi + BLE, module pré-certifié, USB natif pour le flash.
- 24 LEDs WS2812B-2020 en face arrière, sur un cercle de diamètre 76 mm.
- 3 boutons : RESET, BOOT, utilisateur.
- Capteur de lumière ambiante en option pour le mode nuit automatique.
- Aimants MagSafe : hors PCB, anneau adhésif collé en face avant, option.
- Provisioning Wi-Fi par BLE et calcul des horaires : repris du firmware v3 et de l'app.

Ce qu'on retire volontairement par rapport à la V3 : MAX98357A, microSD,
RX8025T et sa pile, Keystone 3000, BAT54C, 2 enceintes. L'heure vient du NTP,
resynchronisée toutes les heures. Sans Wi-Fi au démarrage, le halo respire en
blanc faible pour dire "pas d'heure".

## 2. Synoptique

```
 USB-C J1 ──► F1 1.1A ──► rail 5V ──┬──► C7 100uF ──► LED1 … LED24 (face arrière)
   │  │                             │                      ▲
   │  └── CC1/CC2 : R5/R6 5.1k      └──► U2 AMS1117 ──► 3V3 ──► U1 ESP32-C3-MINI-1
   │                                                          │
   └── D+/D- ── D1 USBLC6 ── GPIO19/GPIO18 (USB natif)        │ GPIO10
                                                              ▼
                                                   U3 74AHCT1G125 ── R7 330R ── DIN LED1
   SW1 RESET ─► EN        SW2 BOOT ─► GPIO9        SW3 USER ─► GPIO3        Q1 lumière ─► GPIO4 (ADC)
```

## 3. Schéma détaillé, bloc par bloc

Convention : une ligne par connexion, colonne "Net" = nom du signal à donner
dans KiCad. Tout ce qui n'est pas listé sur une broche est laissé en l'air.

### 3.1 Entrée USB-C et protection

| Composant | Broche | Net | Remarque |
|---|---|---|---|
| J1 USB-C | VBUS (A4, A9, B4, B9) | VBUS | les 4 broches ensemble |
| J1 USB-C | GND (A1, A12, B1, B12) + SHIELD | GND | blindage à la masse via les 4 pattes mécaniques |
| J1 USB-C | CC1 (A5) | CC1 | R5 5.1k vers GND |
| J1 USB-C | CC2 (B5) | CC2 | R6 5.1k vers GND. Deux résistances séparées, jamais une seule sur les deux CC |
| J1 USB-C | D+ (A6, B6) | USB_DP | A6 et B6 reliés ensemble |
| J1 USB-C | D- (A7, B7) | USB_DM | A7 et B7 reliés ensemble |
| J1 USB-C | SBU1, SBU2 | NC | |
| F1 fusible | 1 | VBUS | |
| F1 fusible | 2 | 5V | tout le reste de la carte est sur 5V, après le fusible |
| D1 USBLC6-2SC6 | 1 (I/O1) | USB_DP | |
| D1 USBLC6-2SC6 | 2 (GND) | GND | |
| D1 USBLC6-2SC6 | 3 (I/O2) | USB_DM | |
| D1 USBLC6-2SC6 | 4 (I/O2) | USB_DM | côté module |
| D1 USBLC6-2SC6 | 5 (VBUS) | 5V | |
| D1 USBLC6-2SC6 | 6 (I/O1) | USB_DP | côté module |
| C7 100uF | + | 5V | au plus près de J1, réservoir pour les LEDs |
| C7 100uF | - | GND | |
| J2 pads fils (DNP) | 1 | 5V | alim alternative |
| J2 pads fils (DNP) | 2 | GND | |
| TP1 (DNP) | | 5V | |

### 3.2 Régulateur 3,3 V

| Composant | Broche | Net | Remarque |
|---|---|---|---|
| U2 AMS1117-3.3 | 3 (VIN) | 5V | |
| U2 AMS1117-3.3 | 2 (VOUT) et languette | 3V3 | |
| U2 AMS1117-3.3 | 1 (GND) | GND | |
| C1 10uF | 5V / GND | | entrée, à 3 mm de U2 |
| C3 100nF | 5V / GND | | entrée |
| C2 10uF | 3V3 / GND | | sortie, obligatoire pour la stabilité de l'AMS1117 |
| TP2 (DNP) | | 3V3 | |
| TP3 (DNP) | | GND | |

Dissipation : l'ESP32-C3 tire 350 mA crête en émission Wi-Fi. (5 - 3,3) x 0,35 = 0,6 W
crête, 0,15 W en moyenne. Le SOT-223 avec sa languette sur un plan de cuivre de
1 cm² suffit. C'est le même montage que la V3.

### 3.3 Module ESP32-C3-MINI-1

| Broche module | Nom | Net | Remarque |
|---|---|---|---|
| 3 | 3V3 | 3V3 | C5 10uF + C4 100nF entre 3V3 et GND, à 2 mm du module |
| 1, 2, 14, 36 à 53 | GND | GND | toutes les masses, y compris le pad thermique |
| 8 | EN | EN | R1 10k vers 3V3, C6 1uF vers GND, SW1 vers GND |
| 5 | IO2 | STRAP_IO2 | R4 10k vers 3V3. Doit être haut au boot, ne rien y brancher d'autre |
| 12 | IO8 | STRAP_IO8 | R3 10k vers 3V3. Doit être haut au boot pour le mode téléchargement |
| 23 | IO9 | BOOT | R2 10k vers 3V3, SW2 vers GND. Bas au boot = mode téléchargement |
| 21 | IO18 | USB_DM | USB natif, direct, pas de résistance série |
| 22 | IO19 | USB_DP | USB natif |
| 16 | IO10 | LED_DATA_3V3 | vers U3 entrée. Pas de fonction de strapping sur IO10 |
| 6 | IO3 | BTN_USER | SW3 vers GND, pull-up interne activée dans le firmware |
| 7 | IO4 | ALS | capteur de lumière, entrée ADC1_CH4 |
| 4 | IO0 | NC | libre, réservé |
| 9 à 11, 13, 15, 17 à 20 | IO1, IO5 à IO7, IO20, IO21 | NC | libres. IO20/IO21 = UART0, à sortir sur TP si on veut les logs série |
| TP4 (DNP) | | EN | |

Broches de strapping du C3 à ne pas oublier : IO2, IO8, IO9. Les trois sont
tirées à 3V3 par 10k. Contrairement au S3 de la V3, le C3 n'a pas de
périphérique tactile : pas de TTP223 ni de bouton capacitif natif, d'où le
tact switch SW3.

Antenne : le module se pose sur le bord de la carte, antenne vers l'extérieur,
avec un keep-out de 15 mm sans cuivre sur les deux faces. Voir 6.3 pour le
problème du téléphone devant l'antenne.

### 3.4 Boutons

| Composant | Broche 1 | Broche 2 | Rôle |
|---|---|---|---|
| SW1 | EN | GND | RESET |
| SW2 | BOOT | GND | BOOT, maintenu pendant un RESET = mode téléchargement |
| SW3 | BTN_USER | GND | appui court : snooze du halo en cours, appui long : cycle des scènes |

Séquence de flash sans CP2102 : brancher l'USB-C sur le PC, maintenir SW2,
appuyer SW1, relâcher SW2. Le C3 apparaît comme port série USB natif, `esptool`
flashe directement. Après le premier firmware, l'OTA de la V3 fait le reste.

### 3.5 Translateur de niveau et chaîne de LEDs

| Composant | Broche | Net | Remarque |
|---|---|---|---|
| U3 74AHCT1G125 | 1 (OE) | GND | sortie toujours active |
| U3 74AHCT1G125 | 2 (A) | LED_DATA_3V3 | depuis IO10 |
| U3 74AHCT1G125 | 3 (GND) | GND | |
| U3 74AHCT1G125 | 4 (Y) | LED_DATA_5V | vers R7 |
| U3 74AHCT1G125 | 5 (VCC) | 5V | C8 100nF entre VCC et GND |
| R7 330R | 1 | LED_DATA_5V | |
| R7 330R | 2 | LED_DIN1 | vers DIN de LED1 |
| LED1 | VDD | 5V | C10 100nF entre VDD et GND |
| LED1 | DIN | LED_DIN1 | |
| LED1 | DOUT | LED_DIN2 | |
| LED1 | GND | GND | |
| LED2 à LED24 | idem | LED_DINn / LED_DINn+1 | chaîne en série, DOUT de LED24 en l'air |

Pourquoi un translateur : le WS2812B-2020 demande un niveau haut d'au moins
0,7 x VDD, soit 3,5 V sous 5 V. Les 3,3 V du C3 sont juste en dessous. La V3
s'en sort avec des SK6812 plus tolérants, mais sur un produit vendu en série
on ne parie pas là-dessus. Le 74AHCT1G125 coûte moins de 0,10 EUR et supprime
le problème.

Une capa 100nF par LED est la règle du fabricant, sinon les LEDs les plus
éloignées clignotent au changement de couleur.

### 3.6 Capteur de lumière (option)

| Composant | Broche | Net | Remarque |
|---|---|---|---|
| Q1 ALS-PT19 | collecteur | 3V3 | |
| Q1 ALS-PT19 | émetteur | ALS | vers IO4 |
| R8 10k | ALS | GND | charge, donne 0 V dans le noir, ~3 V en plein jour |

Le capteur doit voir la pièce : à placer sur le bord haut de la carte, en face
arrière, hors de la zone couverte par le téléphone. Si on ne pose pas Q1, R8
tire IO4 à GND et le firmware voit "nuit" en permanence : prévoir un réglage
"capteur absent" dans l'app.

## 4. Table des GPIO

| GPIO | Fonction | Direction | Strapping |
|---|---|---|---|
| EN | reset | entrée | RC 10k / 1uF |
| IO2 | libre, tiré haut | | oui, haut au boot |
| IO3 | bouton utilisateur | entrée, pull-up interne | non |
| IO4 | capteur lumière | entrée ADC | non |
| IO8 | libre, tiré haut | | oui, haut au boot |
| IO9 | BOOT | entrée | oui, bas = téléchargement |
| IO10 | data LED | sortie | non |
| IO18 | USB D- | | non |
| IO19 | USB D+ | | non |
| IO20 / IO21 | UART0 RX / TX, non câblés | | non |

Changement firmware par rapport à la V3 : `LED_DATA_PIN` passe de 8 à 10,
`LED_NUM` de 25 à 24, et on garde `NEO_GRB + NEO_KHZ800`. Le pilotage par RMT
du C3 est supporté par Adafruit_NeoPixel.

## 5. Budget de puissance

| Poste | Courant |
|---|---|
| ESP32-C3 en émission Wi-Fi, crête | 350 mA sur 3V3, soit 250 mA sur 5V |
| ESP32-C3 en veille légère, moyenne | 20 mA |
| 24 LED WS2812B-2020 blanc à 100 % | 24 x 36 mA = 860 mA |
| 24 LED une seule couleur à 100 % | 24 x 12 mA = 290 mA |
| 24 LED une couleur à 40 % (réglage usine) | 115 mA |

Le halo n'affiche qu'une couleur à la fois et le firmware plafonne la
luminosité à 60 %. Le pire cas réaliste reste sous 500 mA, ce qui passe sur
n'importe quel port USB, même un vieux port USB-A avec un câble A vers C. Le
fusible F1 à 1,1 A protège si l'app force le blanc plein.

Avec R5/R6 à 5.1k, un chargeur USB-C annonce 5 V jusqu'à 3 A : il n'y a donc
aucune négociation à faire côté firmware.

## 6. Placement PCB

### 6.1 Carte

- Disque de diamètre 85 mm, 2 couches, 1,6 mm, masque noir mat, sérigraphie
  blanche, finition HASL sans plomb. ENIG uniquement si on veut le logo en
  cuivre nu doré sur la face avant.
- Assemblage JLCPCB sur une seule face, la face arrière. La face avant ne
  porte aucun composant : c'est la surface visible derrière le téléphone,
  masque noir + logo en sérigraphie ou en cuivre exposé.
- Plan de masse sur les deux faces, cousu de vias, sauf sous l'antenne.
- 4 trous de fixation diamètre 2,2 mm à 90° sur un cercle de 60 mm pour les
  vis de la coque arrière.

### 6.2 Anneau de LEDs, face arrière

24 LEDs sur un cercle de rayon 38 mm, pas 15°, LED1 en haut, sens horaire vu de
l'arrière. Centre de la carte en (0, 0), Y positif vers le bas comme dans KiCad.

| LED | angle | X (mm) | Y (mm) |
|---|---|---|---|
| LED1 | 90° | +0.00 | -38.00 |
| LED2 | 75° | +9.84 | -36.71 |
| LED3 | 60° | +19.00 | -32.91 |
| LED4 | 45° | +26.87 | -26.87 |
| LED5 | 30° | +32.91 | -19.00 |
| LED6 | 15° | +36.71 | -9.84 |
| LED7 | 0° | +38.00 | 0.00 |
| LED8 | 345° | +36.71 | +9.84 |
| LED9 | 330° | +32.91 | +19.00 |
| LED10 | 315° | +26.87 | +26.87 |
| LED11 | 300° | +19.00 | +32.91 |
| LED12 | 285° | +9.84 | +36.71 |
| LED13 | 270° | 0.00 | +38.00 |
| LED14 | 255° | -9.84 | +36.71 |
| LED15 | 240° | -19.00 | +32.91 |
| LED16 | 225° | -26.87 | +26.87 |
| LED17 | 210° | -32.91 | +19.00 |
| LED18 | 195° | -36.71 | +9.84 |
| LED19 | 180° | -38.00 | 0.00 |
| LED20 | 165° | -36.71 | -9.84 |
| LED21 | 150° | -32.91 | -19.00 |
| LED22 | 135° | -26.87 | -26.87 |
| LED23 | 120° | -19.00 | -32.91 |
| LED24 | 105° | -9.84 | -36.71 |

Chaque LED tournée pour que DOUT pointe vers la suivante, rotation = angle - 90°.
Sa capa 100nF juste derrière elle, côté centre. Le rail 5V et la masse font le
tour en deux anneaux de cuivre de 2 mm de large, r = 34 mm et r = 42 mm.

### 6.3 Module, USB-C, boutons

- U1 en haut de la carte, antenne vers le haut, dépassant de la zone couverte
  par le téléphone. Un iPhone de 71 mm de large posé au centre laisse 7 mm de
  chaque côté et tout le haut du disque au-dessus de son bord supérieur si le
  téléphone repose sur le pied avec 15 mm de dépassement du disque. C'est cette
  bande haute qui accueille l'antenne. Point à vérifier sur le proto : mesurer
  le RSSI avec et sans téléphone posé. Si la perte dépasse 10 dB, passer au
  ESP32-C3-MINI-1U avec antenne externe déportée dans la coque.
- J1 USB-C en bas, au centre, connecteur horizontal sortant vers le bas dans le
  pied. F1, C7 et D1 à côté.
- U2 et ses capas entre J1 et U1, sur le plan de masse.
- SW1 et SW2 accessibles par deux trous de 2 mm dans la coque arrière, en bas
  à gauche. SW3 en haut à droite, avec un bossage sur la coque.
- Q1 tout en haut, à côté de l'antenne, avec une fenêtre dans la coque.

### 6.4 Mécanique

- Coque arrière imprimée en PETG blanc translucide, 1,6 mm d'épaisseur, qui
  dépasse le disque de 5 mm sur tout le tour. Cette lèvre est le diffuseur : la
  lumière des LEDs tournées vers l'arrière sort par la tranche et dessine
  l'anneau autour du téléphone vu de face.
- Pied imprimé en PETG noir, angle 65°, rainure pour le câble.
- Anneau aimanté MagSafe adhésif collé en face avant, centré à 20 mm sous le
  centre du disque pour que l'appareil photo de l'iPhone ne dépasse pas.

## 7. Reprise dans KiCad

Symboles à copier depuis `AdhanBoxPCBV3.kicad_sch`, ils sont déjà dans la
bibliothèque du projet :
`AdhanBoxV3:AMS1117-3.3`, `Connector:USB_C_Receptacle_USB2.0_16P`,
`Switch:SW_Push`, `Device:C`, `Device:R`, `Connector:TestPoint`,
`Connector_Generic:Conn_01x02`, `power:PWR_FLAG`.

À ajouter depuis les bibliothèques standard KiCad :
`RF_Module:ESP32-C3-MINI-1`, `LED:WS2812B` (le symbole 5050 convient au 2020,
seule l'empreinte change), `Power_Protection:USBLC6-2SC6`,
`74xGxx:74AHCT1G125`, `Device:Polyfuse`, `Device:Q_Photo_NPN`.

Empreinte du WS2812B-2020 : importer depuis LCSC, réf C965555, via le plugin
"LCSC to KiCad", ou dessiner 4 pastilles 0,9 x 0,7 mm sur un corps 2 x 2 mm.

Ordre conseillé : feuille 1 alimentation et USB (3.1 + 3.2), feuille 2 module
et boutons (3.3 + 3.4 + 3.6), feuille 3 LEDs (3.5), avec un label hiérarchique
`LED_DATA_3V3` entre les feuilles 2 et 3.

## 8. À confirmer avant de commander

1. Les réf LCSC marquées "A CONFIRMER" dans la BOM : U1, U3, D1, F1, R7, LED, Q1.
   Vérifier stock et prix sur jlcpcb.com/parts le jour de la commande.
2. RSSI avec le téléphone posé, sur le premier proto. Décide entre MINI-1 et MINI-1U.
3. Rendu du halo à travers la lèvre PETG : tester deux épaisseurs, 1,2 et 1,6 mm.
4. Consommation réelle à 60 % sur une seule couleur, pour valider F1 à 1,1 A.
5. Nom du modèle pour le dossier CE, proposition : `HALO-V1`.
