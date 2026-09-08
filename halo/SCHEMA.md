# Halo v1 : schéma électrique et notes de conception

Support de téléphone de bureau avec anneau lumineux, dérivé de l'AdhanBox.
Reprend la logique de l'overlay : anneau à l'entrée d'une prière, 30 min avant
la fin de l'horaire, 10 min avant la fin. Pas d'audio, pas de microSD, pas de RTC.

Fichiers du dossier :

| Fichier | Contenu |
|---|---|
| `Halo_BOM.csv` | BOM PCB au format JLCPCB (mêmes colonnes que `AdhanBoxPCBV3_BOM.csv`), écrite à la main |
| `GERBER_HALO/` | Dossier de fabrication : Gerbers, perçage Excellon, `Halo_CPL.csv` (positions JLCPCB) |
| `Halo_GERBER.zip` | Les Gerbers et le perçage seuls, l'archive à téléverser chez JLCPCB |
| `export_fab.py` | Produit `GERBER_HALO/` et le zip, et vérifie que BOM, CPL et PCB concordent |
| `Halo_BOM_produit.csv` | BOM complète du produit fini : coque, pied, câble, boîte |
| `Halo.kicad_pro` | Projet KiCad : à ouvrir en premier, il relie le schéma et le PCB |
| `Halo.kicad_sch` | Schéma KiCad 10, même structure que la V3 : symboles + labels globaux, prêt pour le PCB |
| `gen_kicad_sch.py` | Générateur du `.kicad_sch`, à relancer après toute modification de placement ou de net |
| `Halo.kicad_pcb` | PCB KiCad 10 : disque D85 + languette USB-C, entièrement routé (anneau LED + centre), DRC à zéro erreur |
| `gen_kicad_pcb.py` | Générateur du `.kicad_pcb` : placement, anneau 5V, arcs de data. Importe composants et nets de `gen_kicad_sch.py` |
| `route_center.py` | Routeur du centre : Dijkstra sur grille 0,1 mm, F.Cu + B.Cu, vias, stitching GND. Réécrit `Halo.kicad_pcb` |
| `drc.py` | DRC programmatique (règles par défaut KiCad, connectivité, courtyards, antenne). Code retour 1 si erreur |
| `gen_kicad_libs.py` | Extrait `Halo.kicad_sym`, `Halo.pretty/` et les tables de librairies du projet |
| `build.sh` | Enchaîne schéma, PCB, routage, DRC, librairies, dossier de fabrication, 3D |
| `firmware/halo/halo.ino` | Firmware ESP32-C3, dérivé de la V3 : BLE, horaires, halo de prière, mode nuit. Voir `firmware/README.md` |
| `Halo_routage.png` | Rendu des deux couches de cuivre après routage |
| `gen_coque_pied.py` | Coque et pied en CadQuery, avec contrôles de collision ; écrit `3d/` |
| `3d/Halo_coque.step` `.stl` | Coque arrière translucide, à imprimer fond sur le plateau |
| `3d/Halo_pied.step` `.stl` | Pied incliné à 65°, à imprimer à plat |
| `3d/Halo_pcb.step` `Halo_assemblage.step` | PCB nu et assemblage complet, pour Fusion |
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

Numéros de broches du module MINI-1 (53 broches), d'après la table "Pin
Definitions" de la datasheet Espressif. À contre-vérifier sur la datasheet
avant de router, le WROOM-02 a une numérotation différente.

| Broche module | Nom | Net | Remarque |
|---|---|---|---|
| 3 | 3V3 | 3V3 | C5 10uF + C4 100nF entre 3V3 et GND, à 2 mm du module |
| 1, 2, 11, 14, 36 à 53 | GND | GND | toutes les masses, y compris le pad thermique |
| 8 | EN | EN | R1 10k vers 3V3, C6 1uF vers GND, SW1 vers GND |
| 5 | IO2 | STRAP_IO2 | R4 10k vers 3V3. Doit être haut au boot, ne rien y brancher d'autre |
| 22 | IO8 | STRAP_IO8 | R3 10k vers 3V3. Doit être haut au boot pour le mode téléchargement |
| 23 | IO9 | BOOT | R2 10k vers 3V3, SW2 vers GND. Bas au boot = mode téléchargement |
| 26 | IO18 | USB_DM | USB natif, direct, pas de résistance série |
| 27 | IO19 | USB_DP | USB natif |
| 16 | IO10 | LED_DATA_3V3 | vers U3 entrée. Pas de fonction de strapping sur IO10 |
| 6 | IO3 | BTN_USER | SW3 vers GND, pull-up interne activée dans le firmware |
| 18 | IO4 | ALS | capteur de lumière, entrée ADC1_CH4 |
| 12, 13, 19, 20, 21 | IO0, IO1, IO5, IO6, IO7 | NC | libres, croix de non-connexion dans le schéma |
| 30, 31 | IO20 RXD0, IO21 TXD0 | NC | UART0, à sortir sur TP si on veut les logs série |
| 4, 7, 9, 10, 15, 17, 24, 25, 28, 29, 32 à 35 | NC | | non connectés en interne |
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
| LED1 | 4 VDD | 5V | C10 100nF entre VDD et GND |
| LED1 | 3 DI | LED_DIN1 | |
| LED1 | 1 DO | LED_DIN2 | |
| LED1 | 2 GND | GND | |
| LED2 à LED24 | idem | LED_DINn / LED_DINn+1 | chaîne en série, DO de LED24 en l'air |

Brochage WS2812B-2020 Worldsemi (datasheet V1.4, LCSC C965555) : 1 DO, 2 GND,
3 DI, 4 VDD ; vu de dessus, DI et VDD d'un côté, GND et DO de l'autre.

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

Tout ce paragraphe est réalisé dans `Halo.kicad_pcb`, généré par
`gen_kicad_pcb.py`. Les cotes ci-dessous sont celles du fichier.

### 6.1 Carte

- Disque de diamètre 85 mm, 2 couches, 1,6 mm, masque noir mat, sérigraphie
  blanche, finition HASL sans plomb. ENIG uniquement si on veut le logo en
  cuivre nu doré sur la face avant.
- Languette de 14 x 8 mm en bas du disque, cachée dans le pied, qui porte le
  connecteur USB-C. Sans elle, le connecteur (7,3 mm de profondeur depuis le
  bord) rentre dans l'anneau de LEDs quel que soit l'angle.
- Convention de faces : **F.Cu = face arrière du produit** (composants, LEDs,
  tournée vers le mur), **B.Cu = face avant visible** derrière le téléphone,
  plan de masse plein et logo "HALO" en sérigraphie miroir. Assemblage JLCPCB
  sur une seule face, F.Cu.
- Plan de masse sur les deux faces, avec une encoche sans cuivre de 16 x 8,1 mm
  sous l'antenne du module (la zone antenne du module fait 5,4 mm, datasheet
  fig. 11-1 ; l'encoche va jusqu'à 0,7 mm de la rangée GND 36-48).
- 4 trous de fixation diamètre 2,2 mm (H1 à H4) à 45°, 135°, 225°, 315° sur
  un cercle de rayon 30 mm, pour les vis autotaraudeuses M2 de la coque.

### 6.2 Anneau de LEDs, face F.Cu

24 LEDs sur un cercle de rayon 38 mm, pas 15°, LED1 à 277,5° soit en bas à
droite, puis sens trigonométrique (anti-horaire) vu côté composants. Ce sens
est imposé par le brochage du WS2812B-2020 : VDD et DI sont du même côté du
boîtier, donc pour avoir VDD vers l'anneau 5V extérieur, DO regarde forcément
dans le sens trigonométrique. Il n'y a pas de LED exactement en bas : les deux
plus basses, LED1 et LED24, encadrent l'ouverture par où passent les pistes de
l'USB-C. Le haut du halo tombe entre LED12 et LED13. Le firmware ne présume
rien de la position de LED1. Centre de la carte en (0, 0), Y positif vers le
bas comme dans KiCad.

| LED | angle | X (mm) | Y (mm) |
|---|---|---|---|
| LED1 | 277,5° | +4,96 | +37,67 |
| LED2 | 292,5° | +14,54 | +35,11 |
| LED3 | 307,5° | +23,13 | +30,14 |
| LED4 | 322,5° | +30,14 | +23,13 |
| LED5 | 337,5° | +35,11 | +14,54 |
| LED6 | 352,5° | +37,67 | +4,96 |
| LED7 | 7,5° | +37,67 | -4,96 |
| LED8 | 22,5° | +35,11 | -14,54 |
| LED9 | 37,5° | +30,14 | -23,13 |
| LED10 | 52,5° | +23,13 | -30,14 |
| LED11 | 67,5° | +14,54 | -35,11 |
| LED12 | 82,5° | +4,96 | -37,67 |
| LED13 | 97,5° | -4,96 | -37,67 |
| LED14 | 112,5° | -14,54 | -35,11 |
| LED15 | 127,5° | -23,13 | -30,14 |
| LED16 | 142,5° | -30,14 | -23,13 |
| LED17 | 157,5° | -35,11 | -14,54 |
| LED18 | 172,5° | -37,67 | -4,96 |
| LED19 | 187,5° | -37,67 | +4,96 |
| LED20 | 202,5° | -35,11 | +14,54 |
| LED21 | 217,5° | -30,14 | +23,13 |
| LED22 | 232,5° | -23,13 | +30,14 |
| LED23 | 247,5° | -14,54 | +35,11 |
| LED24 | 262,5° | -4,96 | +37,67 |

Chaque LED est tournée de angle + 90° : son axe Y local pointe vers
l'extérieur (VDD et DO sur la rangée extérieure), son axe X local vers la LED
suivante (DO et GND de ce côté). Routage déjà fait dans le fichier :

- Anneau 5V à l'extérieur des LEDs, rayon 40,6 mm, largeur 0,8 mm, ouvert de
  266° à 274° en bas pour laisser passer les pistes de l'USB-C. Alimenté par
  F1 à son extrémité gauche (266°).
- Un stub de 0,4 mm de chaque pad VDD vers l'anneau 5V.
- 23 pistes de data de 0,3 mm, du DO de la LED n (rangée extérieure, rayon
  38,55) au DI de la LED n+1 (rangée intérieure, rayon 37,45) : segments
  droits de 8 mm qui passent à 0,4 mm du pad GND du 100nF intercalé. R7 vers
  DI de LED1.
- Les 24 condensateurs 100nF (C10 à C33) sont radiaux au rayon 40 mm, à 5° de
  leur LED, du côté opposé à l'ouverture du bas. Leur pad 1 chevauche
  l'anneau 5V, leur pad 2 va à la masse par le plan.
- Les pads GND des LEDs se raccordent au plan de masse F.Cu par thermiques.

### 6.3 Centre de la carte

Routé par `route_center.py` (voir 6.4). Placement :

- U1 en haut, centre à (0, -24), antenne vers le haut. Empreinte = land
  pattern de la datasheet Espressif (fig. 11-1) : broches en retrait sous le
  module à x = ±5,9 mm, rangées y = -2,2 et +7,6, masse centrale 3 x 3 avec un
  via par pastille, pastilles d'angle 50-53 raccordées par un court segment.
  La zone antenne (y < -2,9 mm du module) est à 5 mm des LEDs les plus
  proches, LED12 et LED13. Point à vérifier sur le proto :
  mesurer le RSSI avec et sans téléphone posé. Si la perte dépasse 10 dB,
  passer au ESP32-C3-MINI-1U avec antenne externe déportée dans la coque.
- Découplage et pull-ups en deux colonnes à x = ±10,5 mm le long des
  broches : à gauche C5, C4 (3V3, broche 3), R1, C6 (EN, broche 8) et R4 à
  x = -14 (IO2, broche 5) ; à droite R3 et R2 (IO8 et IO9, rangée basse).
  SW1 et SW2 à gauche du module, SW3 à droite, TP4 (EN) à côté de SW2.
- Q1 et R8 en haut à gauche à (-17, -29), avec une fenêtre dans la coque.
- J1 USB-C sur la languette à (0, +46,6), ouverture vers le bas. F1 à
  gauche, D1 au centre, C7 à droite juste au-dessus dans le disque ; U3, R7
  et C8 à droite, sous LED1. Les pistes VBUS, D+, D-, CC1, CC2 montent
  par l'ouverture de l'anneau 5V.
- U2 et ses capas en bas à gauche à (-12, +20). R5, R6 à droite. TP1 à TP3
  et J2 sur la droite.
- U3, C8 et R7 en bas, entre LED1 et LED2, pour que la data parte au plus
  court vers LED1.

### 6.4 Mécanique

Réalisée dans `gen_coque_pied.py`, fichiers dans `3d/`. Même principe que
`fusion_scripts/` : la conception est un script rejouable, les valeurs de
contrôle sont mesurées à l'exécution.

**Coque arrière**, PETG translucide blanc, 22 g de matière pleine

- Bol de diamètre extérieur 98,2 mm, paroi 1,6 mm, fond 1,6 mm, hauteur 11,2 mm.
  Le rayon intérieur est de 47,5 mm pour un PCB de 42,5 mm : les 5 mm de jour
  tout autour du PCB sont la surface lumineuse vue de face. Les LEDs éclairent
  le fond du bol, la lumière ressort par ce jour et par la paroi.
- Le bord avant dépasse le PCB de 1,6 mm. Le téléphone s'appuie sur la face
  avant du PCB, masque noir.
- Le PCB repose par sa face arrière sur 4 plots de diamètre 6 mm à r = 30 mm,
  chacun avec un pion de 1,8 mm dans les trous H1 à H4. Il est retenu par
  4 crochets de 0,6 mm portés par des nervures à 45°, 135°, 225°, 315° : on le
  clipse, pas de vis en face avant.
- Fente de 16,6 mm en bas de la paroi pour la languette et le connecteur USB-C.
- Fond : 2 trous de 2,2 mm au droit de RESET et BOOT, une membrane de 10 mm
  amincie à 0,6 mm avec un téton de 3 mm sur le bouton utilisateur, un trou de
  3 mm sur le capteur de lumière.
- Impression fond sur le plateau, ouverture en l'air, sans support. Les
  crochets ont 0,6 mm de porte-à-faux.

**Pied**, PETG noir, 81 cm³ de volume, environ 40 g à 15 % de remplissage

- Bloc 70 x 52 x 24 mm à chanfreins de 4 mm, butée avant de 3 mm pour le bas
  du téléphone.
- Fente à la forme exacte de la coque inclinée à 65°, jeu 0,3 mm. La coque s'y
  emboîte sur 8,6 mm de profondeur. Hauteur totale du produit : 109 mm.
- Poche pour la languette USB-C et une **prise USB-C coudée**. C'est un choix
  important : avec une prise droite, le pied ferait 35 mm de haut. Le câble
  fourni doit donc être coudé, voir la BOM produit.
- Rainure de câble de 7 x 7 mm de la prise vers la face droite du pied.
- 4 logements de diamètre 10 mm dessous pour les pads silicone.
- Impression à plat, sans support : la rainure est un pont de 7 mm.

**Valeurs de contrôle** mesurées à l'exécution du script

| contrôle | valeur |
|---|---|
| intersection coque / PCB | 0 mm³ |
| intersection coque / composants | 0 mm³ |
| intersection coque / pied | 0 mm³ |
| coque en place, Z | 15,4 à 109,2 mm |
| emboîtement dans le pied | 8,6 mm |
| bas de la prise coudée au-dessus du plancher | 4,2 mm |
| rainure de câble | Y = -15,1, Z = 11,2 |

- Anneau aimanté MagSafe adhésif collé en face avant, centré à 20 mm sous le
  centre du disque pour que l'appareil photo de l'iPhone ne dépasse pas.

### 6.4 Routage du centre et DRC

kicad-cli n'étant pas disponible dans l'environnement de génération, le centre
est routé par `route_center.py` et vérifié par `drc.py`, tous deux en Python
(shapely, numpy, scipy).

Routeur : grille de 0,1 mm sur les deux couches, plus court chemin (Dijkstra)
entre les îlots de chaque net, les cellules à moins de 0,225 mm + w/2 d'un
cuivre étranger sont interdites. B.Cu (plan de masse, face avant) coûte le
double et un via coûte 3 mm de piste, pour garder le plan de masse aussi
entier que possible. Largeurs : 5V et VBUS 0,5 mm, 3V3 0,35, GND 0,3, USB et
CC 0,2 (pads du connecteur à 0,5 mm de pas), le reste 0,25 ; repli sur une
largeur plus fine si un net ne passe pas. Ordre : USB, CC, VBUS, 5V, 3V3 et
les nets longs, puis les nets locaux. Interdits : encoche antenne (aucun
cuivre, y compris vias) et corps du module U1 sur F.Cu (rien d'autre que GND).

GND : 4 vias dans le pavé thermique de U1, puis le remplissage des zones est
recalculé et chaque îlot GND isolé (pad enfermé par des pistes) reçoit un via
vers le plan B.Cu ou une courte piste vers la zone principale.

DRC (`drc.py`), mêmes valeurs que les règles par défaut de KiCad : isolation
0,2 mm, piste mini 0,2, cuivre-bord 0,5, trou-cuivre 0,25, courtyards
disjoints, contours de zone valides, chaque net en un seul îlot (zones GND
remplies comprises), pas de cuivre sous l'antenne. Résultat : 0 erreur,
44 vias, 88 mm de piste sur B.Cu.

Le résultat est brut de routeur : angles à 45°, quelques détours. Il est
correct électriquement et passe le DRC, mais on peut le retoucher dans KiCad
avant les Gerbers, en relançant le DRC de KiCad ensuite.

## 7. Le fichier KiCad

`Halo.kicad_sch` est généré par `gen_kicad_sch.py`, avec la même structure que
`AdhanBoxPCBV3.kicad_sch` : une feuille A3, symboles placés, un label global
sur chaque broche utilisée, croix de non-connexion sur les broches libres,
aucun fil. Les symboles R, C, SW_Push, USB-C, AMS1117, TestPoint, Conn_01x02
et PWR_FLAG sont copiés tels quels depuis la V3. Les symboles propres au Halo
(`Halo:ESP32-C3-MINI-1`, `Halo:WS2812B`, `Halo:USBLC6-2SC6`,
`Halo:74AHCT1G125`, `Halo:Polyfuse`, `Halo:Q_Photo_NPN`) sont embarqués dans
le fichier, comme le RX8025T de la V3 : pas de bibliothèque externe à installer.

Pour ouvrir : double-cliquer sur `Halo.kicad_pro`, le projet relie le schéma
et le PCB. Lancer l'ERC en premier.

`Halo.kicad_pcb` est généré par `gen_kicad_pcb.py`. Les empreintes 0805,
électrolytique 6,3 mm, SOT-223, TL3342, USB-C HRO, test point, pin header
sont copiées de la V3. Les autres sont dessinées dans le générateur avec des
cotes nominales : ESP32-C3-MINI-1, SOT-23-5, SOT-23-6, fusible 1206,
condensateur 0603, WS2812B-2020, phototransistor 0805, trou 2,2 mm.

Vérifications faites le 08/09/2026 : ESP32-C3-MINI-1 redessiné d'après la
fig. 11-1 de la datasheet Espressif v2.2 (identique à l'empreinte officielle
espressif/kicad-libraries) et table 3-1 des broches ; WS2812B-2020 redessiné
d'après la datasheet Worldsemi V1.4 (brochage 1 DO, 2 GND, 3 DI, 4 VDD,
pastilles 0,7 x 0,7) ; SOT-23-5/6 et fusible 1206 aux cotes des bibliothèques
KiCad 10. `gen_kicad_libs.py` extrait ces empreintes et symboles dans
`Halo.pretty` et `Halo.kicad_sym` avec les tables de librairies du projet.
ERC 0, DRC KiCad 0 erreur (`kicad-cli pcb drc --refill-zones`), `drc.py` 0
erreur. `export_fab.py` sort les Gerbers, le perçage et le CPL dans
`GERBER_HALO/` (kicad-cli 10.0.3) et contrôle que la BOM couvre exactement les
composants du schéma, avec les bonnes empreintes et les bonnes quantités.

Les composants DNP (Q1 le phototransistor, J2 les pads d'alimentation, TP1 à
TP4) portent le drapeau « ne pas monter » sur le PCB comme au schéma : ils
sortent de la BOM à poser et du CPL.

Ordre conseillé ensuite : Mettre à jour le PCB depuis le schéma (les
références et nets sont déjà cohérents), remplir les zones (B), lancer le DRC
de KiCad (le centre est déjà routé par `route_center.py`, voir 6.4).

Pour tout regénérer : `halo/build.sh` (schéma, PCB, routage, DRC, 3D). Le
routage prend environ 3 minutes.

Pour modifier le schéma : éditer la liste `parts` du générateur (référence,
symbole, valeur, empreinte, position, nets par broche), relancer le script.
Les UUID sont déterministes, le diff git reste lisible.

## 8. À confirmer avant de commander

1. Deux références LCSC manquent encore dans la BOM, `export_fab.py` les
   rappelle à chaque exécution : F1 (PTC 1206 1,1 A, type MF-MSMF110-2) et
   U3 (SN74AHCT1G125DBVR ou 74AHCT1G125GW). Les réf marquées "A CONFIRMER"
   (U1, D1, R7, LED, Q1) sont renseignées mais à revérifier en stock et en
   prix sur jlcpcb.com/parts le jour de la commande.
2. RSSI avec le téléphone posé, sur le premier proto. Décide entre MINI-1 et MINI-1U.
3. Rendu du halo à travers la lèvre PETG : tester deux épaisseurs, 1,2 et 1,6 mm.
4. Consommation réelle à 60 % sur une seule couleur, pour valider F1 à 1,1 A.
5. Nom du modèle pour le dossier CE, proposition : `HALO-V1`.
