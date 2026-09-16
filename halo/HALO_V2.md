# Halo v2 : charge sans fil intégrée

Décision du 16/09/2026. Le Halo v1 était un support éclairé sans charge : un
câble pour le Halo, un second pour le téléphone. Face aux supports passifs où le
client glisse son propre chargeur MagSafe, ce produit ne tenait pas. La v2
intègre la charge sans fil : **un seul câble USB-C**, le téléphone s'aimante au
centre du disque et charge, le halo de LEDs s'allume autour. L'aimantation
donne aussi l'effet « téléphone qui flotte » demandé.

**Le PCB v1 (`halo/`) ne doit pas être commandé tel quel.** Sa mécanique
(socle + col, cannelures), ses outils (`gen_kicad_*.py`, `route_center.py`,
`drc.py`, `export_fab.py`) et son firmware restent la base de la v2.

## 1. Architecture

```
USB-C (languette) ──CC1/CC2──► IP6829  ──LX1/LX2──► C résonance 4 x 250 nF ──► bobine A11 10 µH
                    VBUS 5 ou 9 V │  (PD sink + émetteur Qi 15 W, pont en H intégré)   + ferrite + anneau d'aimants
                                  │                                                     (face avant, sous le téléphone)
                                  ├──► MT2492 buck 5 V ──► 24 x WS2812C-2020, 74AHCT1G125
                                  │                    └──► LDO 3V3 AP2112K ──► ESP32-C3-MINI-1
                    D+/D- ────────┴──────────────────────────────────────────► ESP32 (USB natif, flash)
```

Un seul contrôleur fait la négociation USB-C et l'émission Qi : l'Injoinic
**IP6829**, variante `_MAG` livrée avec le firmware de charge magnétique
(profil MagSafe 5 / 7,5 / 10 / 15 W), Qi v1.3 BPP, pont en H et MOS de
puissance intégrés, PD 3.0 intégré (il demande 9 V lui-même sur CC1/CC2),
FOD statique et dynamique, NTC, gestion dynamique de puissance quand
l'alimentation faiblit. Le schéma de référence tient en une vingtaine de
passifs. Datasheet V1.10 (2023), note : le 12 V a été retiré, l'entrée est
4,5 à 9 V.

Les lignes D+/D- restent à l'ESP32 pour le flashage USB natif. L'IP6829 ne les
utilise que pour les protocoles QC, dont on se passe : sur un chargeur sans PD
il fonctionne en 5 V / 5 W, ce qui suffit pour tester.

## 2. Composants vérifiés en stock JLCPCB le 16/09/2026

| Rôle | Référence | LCSC | Stock | Prix |
|---|---|---|---|---|
| Émetteur Qi + PD sink | Injoinic IP6829_MAG_L05_WFNRG, QFN-32 5x5 | C42411075 | 798 | 0,94 $ |
| Buck 5 V (4,5 à 16 V, 2 A) | Aerosemi MT2492, SOT-23-6 | C89358 | 165 273 | 0,05 $ |
| Buck 5 V, alternative plus propre | Diodes AP63205WU-7, TSOT-23-6 | C2071056 | 16 655 | 0,42 $ |
| Repli si l'IP6829 manque | Injoinic IP6808_NF (7,5 / 10 W, sans PD ni profil MAG) | C515682 | 3 424 | 1,12 $ |
| PD sink séparé, seulement si on abandonne l'IP6829 | WCH CH224D | C3975094 | 4 784 | 0,34 $ |

Le stock de l'IP6829 est le point faible : 798 pièces, une seule source. En
prendre 50 à la première commande, et ne pas attendre pour la seconde.

**À acheter hors JLCPCB** : la bobine A11 10 µH avec sa ferrite et l'anneau
d'aimants (format MagSafe, diamètre extérieur 56 mm), vendue en ensemble
« MagSafe 15W coil with magnet ring » sur AliExpress ou 1688, 2,5 à 4 € par
100. JLCPCB n'assemble pas de bobine : elle sera posée à la main, deux fils
soudés sur deux pastilles, comme le haut-parleur de l'AdhanBox. Commander
trois échantillons de deux fournisseurs avant de figer le PCB : le diamètre
de l'ensemble et l'épaisseur (5 à 6 mm) fixent la mécanique.

Condensateurs de résonance : 250 nF / 100 V au total (le schéma de référence
met deux 250 nF en série-parallèle en boîtier film traversant). En CMS, prendre
quatre 100 nF C0G/NP0 100 V en 1206 en parallèle, ou deux 220 nF PPS. À
choisir à la conception du schéma, en stock chez JLCPCB.

Coût matière ajouté par carte : environ 5 à 6 € (IP6829 0,94, bobine et
aimants 3 à 4, résonance et passifs 0,8, buck et LDO 0,3).

## 3. Budget de puissance

| Poste | Puissance |
|---|---|
| Charge Qi 15 W, rendement ~85 % | 17,5 W en entrée |
| Halo, 24 LEDs blanc plein (WS2812C) | 1,8 W |
| ESP32 en émission Wi-Fi, crête | 1,2 W |
| **Total** | **~20 W, soit 2,3 A sous 9 V** |

Un chargeur PD 9 V / 2 A (18 W) ne suffit pas au pire cas. Deux garde-fous :
l'IP6829 baisse lui-même la puissance émise quand la tension d'entrée fléchit
sous 4,3 V (gestion dynamique), et le firmware plafonne la luminosité du halo
pendant la charge. Recommander un chargeur 20 W ou plus dans la notice ; en
5 V sans PD, la charge tombe à 5 W et le halo reste complet.

Le buck 5 V ne peut pas réguler quand VBUS vaut 5 V : il passe à 100 % de
rapport cyclique et sort 4,6 à 4,8 V. Les WS2812C acceptent 3,7 à 5,3 V, le
74AHCT1G125 est spécifié à 4,5 V minimum : marge faible mais acceptable. C'est
pour cela que l'AMS1117 (chute 1,2 V) est remplacé par un LDO à faible chute
pour le 3V3.

## 4. Implantation : ce qui change sur le circuit

- **Centre de la face avant** : la bobine et sa ferrite, diamètre 45 à 50 mm,
  collées sur le vernis. Aucun cuivre plein sous la bobine sur la face avant,
  la ferrite fait écran vers l'arrière mais le plan de masse doit être
  découpé sous la bobine sur les deux faces, sinon courants de Foucault et
  échauffement.
- **L'ESP32 quitte le centre** : il part au bord haut du disque, antenne vers
  le bord, loin de la bobine et de son champ à 100 à 200 kHz. Le bord de
  carte est de toute façon la bonne place pour l'antenne.
- **Étage de puissance en bas**, près de la languette USB-C : IP6829,
  résistance de mesure 20 mΩ, condensateurs d'entrée, résonance. Le datasheet
  impose des pistes de puissance courtes et larges, PGND avec beaucoup de vias,
  V_DECODE et VDET loin de la bobine et des condensateurs de résonance.
- **Thermique** : 2 à 3 W à dissiper dans un disque fermé. Pad exposé de
  l'IP6829 sur un pavé de cuivre avec vias vers la face arrière, fentes
  d'aération dans la paroi de la coque, et un essai au thermocouple sur le
  proto : surface sous 60 °C, le PETG ramollit vers 80 °C. Si c'est trop
  chaud, brider le profil à 10 W dans le firmware de l'IP6829, qui se
  reprogramme avec l'outil Injoinic.
- **Retour d'état** : les sorties LED1/LED2 de l'IP6829 (charge en cours,
  charge terminée, défaut) vont sur deux GPIO de l'ESP32 à travers un pont
  diviseur. Le halo peut alors animer la pose du téléphone et signaler un
  objet étranger. Les GPIO libres de la v1 (IO0, IO1, IO5, IO6, IO7) suffisent.
- Les 24 LEDs, le translateur, les boutons, le capteur de lumière restent
  tels quels sur la face arrière. R5/R6 (5,1 k sur CC) disparaissent : les CC
  vont à l'IP6829.

## 5. Mécanique

L'aimantation remplace la languette d'appui : le téléphone se pose au centre,
l'anneau d'aimants le cale, il ne touche rien d'autre. Devant le PCB, une
fine coupelle (1,2 mm) tient l'ensemble bobine + aimants contre la carte et
donne la surface de contact du téléphone ; le disque garde le jour lumineux de
5 mm sur son pourtour et les cannelures. Le socle et le col v1 restent, le
col se redessine en ruban cannelé qui prolonge le disque, dans l'esprit des
supports du marché. Fentes d'aération dans la paroi, côté mur.

## 6. Conformité

La charge sans fil est un équipement radio au sens de la directive RED
(transfert de puissance sans fil, bande 100 à 148,5 kHz, norme EN 303 417) :
essais CEM en laboratoire à prévoir, de l'ordre de 1 à 2 k€, en plus du
dossier CE existant (`conformite/`) à compléter d'une annexe Halo. Le module
ESP32-C3-MINI-1 apporte sa propre certification radio. La certification Qi
auprès du WPC est facultative pour vendre ; l'IP6829 est prêt pour le BPP.

## 7. Plan de travail

1. **Adel** : commander les échantillons de bobine A11 + aimants (trois pièces,
   deux fournisseurs) et 50 IP6829 chez LCSC pour sécuriser le stock.
2. Schéma v2 dans `gen_kicad_sch.py` : bloc IP6829 d'après le schéma de
   référence (figure 14 du datasheet), buck 5 V, LDO 3V3, CC vers l'IP6829,
   D+/D- vers l'ESP32, deux GPIO d'état. ERC à zéro.
3. PCB v2 dans `gen_kicad_pcb.py` et `route_center.py` : découpe du plan de
   masse sous la bobine, ESP32 au bord haut, puissance en bas, thermique.
   DRC KiCad et `drc.py` à zéro, `export_fab.py` pour BOM, CPL et Gerbers.
4. Mécanique v2 dans `gen_coque_pied.py` : coupelle avant, aération, col en
   ruban. Contrôles de collision et de stabilité conservés.
5. Firmware : lecture de l'état de charge, animation, plafond de luminosité
   pendant la charge.
6. Prototypes : 5 cartes assemblées, bobines posées à la main. Essais :
   charge iPhone et Android, température, portée Wi-Fi téléphone posé.
7. Commande de série, essais CEM, annexe CE.

Points ouverts pour Adel : puissance cible (15 W nécessite un chargeur 20 W ;
10 W est plus sobre thermiquement et suffit pour un support de bureau) ;
diamètre du disque (garder 85 mm ou descendre à 80 avec la couronne de LEDs
à 35 mm) ; couleurs des pièces imprimées.
