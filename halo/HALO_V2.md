# Halo v2 : charge sans fil intégrée, par module certifié

Décisions du 16/09/2026. Le Halo v1 était un support éclairé sans charge : un
câble pour le Halo, un second pour le téléphone. Face aux supports passifs où le
client glisse son propre chargeur MagSafe, ce produit ne tenait pas. La v2
intègre la charge sans fil : **un seul câble USB-C**, le téléphone s'aimante au
centre du disque et charge, le halo de LEDs s'allume autour. L'aimantation
donne aussi l'effet « téléphone qui flotte » demandé.

Seconde décision, le même jour : la partie radio n'est pas conçue par nous.
Un émetteur Qi sur notre carte (puce Injoinic IP6829, étudiée puis écartée)
aurait exigé des mesures radio que nous n'avons pas les moyens de payer. On
achète donc un **module émetteur complet et certifié**, bobine et aimants
compris, dont le fabricant porte la conformité radio. Notre carte reste celle
de la v1, à quatre ajouts près. Le dossier CE se monte comme celui de
l'AdhanBox V3 : déclaration du module Qi, certificat du module ESP32, notre
évaluation de l'ensemble, sans laboratoire.

**Le PCB v1 ne doit pas être commandé tel quel** : il lui manque la
négociation 9 V, le 5 V abaissé et les pastilles du module.

## 1. Architecture

```
USB-C (languette) ──CC1/CC2──► CH224D (demande 9 V au chargeur PD)
        │ VBUS 9 V (5 V sur un chargeur sans PD)
        ├──► deux pastilles MOD_VIN / GND ──► module Qi certifié (bobine + aimants, face avant)
        └──► MT2492 buck 5 V ──► 24 x WS2812C-2020, 74AHCT1G125
                            └──► LDO 3V3 AP2112K ──► ESP32-C3-MINI-1
        D+/D- ─────────────────────────────────────► ESP32 (USB natif, flash)
```

Le câble entre par le col, dans notre connecteur, comme en v1. Notre carte
négocie le 9 V et le distribue au module par deux fils soudés, comme le
haut-parleur de l'AdhanBox. Le module fait tout le reste : détection du
téléphone, profil MagSafe, détection d'objets étrangers, protection thermique.

**Repli 5 V.** Si le module choisi ou le budget l'impose, la carte peut
rester en 5 V pur : ni CH224D ni buck, le module en 5 V charge à 5 W. C'est
le Halo v1 plus deux pastilles et un fusible plus gros. À trancher à la
réception des modules.

## 2. Le module : ce qu'il faut exiger du vendeur

La majorité des modules AliExpress portent un logo CE sans aucun document
derrière ; un tel module ne nous protège pas plus qu'une puce nue. Ne retenir
que les vendeurs qui fournissent, avant achat :

1. La **déclaration de conformité UE** au nom du fabricant, citant la
   directive radio 2014/53/UE et la directive CEM, avec les normes appliquées
   (EN 303 417 pour le transfert de puissance sans fil, EN 301 489-1 et -3
   pour la CEM radio).
2. Le **rapport d'essai** correspondant, même partiel. Une déclaration seule
   sans rapport est un papier, pas une preuve.
3. La **fiche technique** : tension d'entrée admise sur les pastilles VIN
   (il faut 9 V, et 5 V toléré), puissance par profil (5 / 7,5 / 10 / 15 W),
   présence de pastilles VIN/GND soudables en plus de l'éventuel USB-C,
   dimensions et épaisseur avec les aimants, type de bobine, sortie d'état
   (LED charge en cours) exploitable.
4. L'**identifiant de certification Qi** au WPC si le vendeur s'en réclame,
   vérifiable dans la base publique du WPC.
5. Disponibilité : quantité minimale, délai, engagement de fourniture sur un
   an. Trois échantillons de deux fournisseurs avant de figer la mécanique.

Ordre de grandeur : 5 à 9 € le module par 100, format galet de 56 à 60 mm de
diamètre, 5 à 7 mm d'épaisseur aimants compris.

## 2 bis. Fournisseurs identifiés le 16/09/2026

Recherche faite sur le web et le catalogue WPC. Aucun distributeur classique
(LCSC, Mouser, DigiKey) ne vend de module émetteur complet certifié : ce sont
des kits d'évaluation ou des puces. Le module se prend chez un fabricant
chinois de modules, et la certification se vérifie soi-même.

| Candidat | Ce qu'il annonce | Ce qui manque | Contact |
|---|---|---|---|
| **Shenzhen Huagon Technology** (Longhua, Shenzhen, depuis 2013), module Qi2 MPP 15 W | Entrée 9 V 3 A (autre fiche : 4,75 à 12,25 V), bobine 50 mm, PCBA 55 mm, anneau d'aimants 8 N, **Qi ID QI-21992** annoncé, « KC, FCC, CE, BSMI, NCC, BPP 5 W et EPP/MPP 15 W », MOQ 1 pièce, garantie 3 ans | Épaisseur avec aimants, pastilles VIN/GND, sortie d'état, prix, et surtout **la déclaration UE et le rapport d'essai radio** | mike@Huagon.cn, +86 152 1948 6699 (Mike Zhu), huagoncharging.com |
| **Shenzhen Wowoh Cool** (depuis 2013), chargeurs et modules Qi2 | « CE / FCC / Qi2 » | MOQ annoncé 500 et plus, pas de fiche module publique | wowohcool.com |
| **Shenzhen Yongchangtai Electronics** (yctpcba, depuis 2009), PCBA 15 W double bobine | Entrée 9 V QC, 85 x 71 mm, 0,50 à 1 $ par pièce | Pas magnétique, « CE, UL, RoHS » seulement dans le profil société, aucun rapport | made-in-china.com/yctpcba |
| **CowinLink** (Shenzhen), PCBA 10 / 15 W | Module de référence honnête : « ne revendique aucune certification sans dossier correspondant », propose d'identifier les essais manquants | Pas magnétique, prix et MOQ sur devis | info@mail.cowinlink.com |
| **Shenzhen LazyCat** (chargingelfcat), PCBA Qi2 MPP 15 W | Entrée PD 20 W, une bobine, MOQ 1 000 en personnalisé, sans minimum sur stock | Aucune certification explicite | Kimi, +86 150 1920 0506 |

Fabricants de puces Qi2 MPP dont les modules de référence sont certifiés WPC
(source Chargerlab) : ConvenientPower (CPS812X/822X/823X, entrée PD ou 9 V
continu), Generalplus (AH222-A), NuVolta (NU222), CVSMicro (CV222), WPINNO,
Aohai, ESSON Tech. Ils vendent en volume par distributeurs ; utiles pour
demander à un fabricant de module quelle puce il emploie.

**Recommandation** : Huagon en premier, seul à publier un identifiant Qi et un
MOQ de 1. Vérifier l'identifiant avant tout achat dans la base publique du
WPC, <https://www.wirelesspowerconsortium.com/products/> (recherche
« 21992 » ou « Huagon ») : le 16/09/2026 le site n'a pas répondu à une
consultation automatique, la vérification est à faire à la main. Une
certification Qi n'est pas la conformité radio européenne : demander en plus
la déclaration UE et le rapport EN 303 417 / EN 301 489, chapitre 2.

Message à envoyer, en anglais, aux deux premiers :

> We are integrating a magnetic 15 W Qi2 transmitter module into a lit phone
> stand sold in the EU. Please send: (1) the module datasheet with input
> voltage range, VIN/GND solder pads, dimensions and total thickness with
> magnets, status output; (2) your EU Declaration of Conformity naming
> 2014/53/EU and the applied standards (EN 303 417, EN 301 489-1/-3,
> EN 62368-1); (3) the corresponding RF/EMC test report; (4) the WPC Qi ID
> and certificate; (5) price for 3 samples, 100 and 500 pieces, lead time
> and supply commitment for 12 months.

## 3. Ce qui change sur la carte

Quatre ajouts sur le PCB v1, tout le reste est conservé (24 LEDs, translateur,
boutons, capteur, ESP32, connecteur USB-C sur la languette).

| Ajout | Référence | LCSC | Stock au 16/09/2026 | Prix |
|---|---|---|---|---|
| Négociation PD, demande 9 V | WCH CH224D, QFN-20 | C3975094 | 4 784 | 0,34 $ |
| Buck 9 V vers 5 V, 2 A | Aerosemi MT2492, SOT-23-6, plus self 4,7 µH et deux condensateurs | C89358 | 165 273 | 0,05 $ |
| LDO 3V3 à faible chute, remplace l'AMS1117 | AP2112K-3.3 ou équivalent 600 mA | à choisir | | ~0,10 $ |
| Deux pastilles MOD_VIN / GND près du passage de fils | | | | |

Et trois retouches :

- **F1** : le PTC actuel est spécifié 6 V et 1,1 A. Sous 9 V et 2,3 A il faut
  un PTC 16 V, 2,5 A de maintien, en boîtier 1812. Empreinte à changer.
- **R5, R6** (5,1 k sur CC1/CC2) disparaissent : les CC vont au CH224D.
- **Passage de fils** : un trou de 4 mm au centre de la carte pour les deux
  fils du module. Le centre est libre en v1, seul le marquage HALO-V1 y est.

**Le risque à tester en premier** : la ferrite et les aimants du module, un
disque métallique de 56 mm, se retrouvent à 3 mm de la zone d'antenne du
module ESP32, placé en haut du disque en v1. Le proto mesure la portée Wi-Fi
téléphone posé ; si elle chute, l'ESP32 migre au bord dans une révision, comme
prévu au chapitre 6.3 de `SCHEMA.md`.

## 4. Budget de puissance

| Poste | Puissance |
|---|---|
| Charge 15 W, rendement du module ~85 % | 17,5 W en entrée |
| Halo, 24 LEDs blanc plein | 1,8 W |
| ESP32 en émission Wi-Fi, crête | 1,2 W |
| **Total** | **~20 W, soit 2,3 A sous 9 V** |

Un chargeur 18 W ne couvre pas le pire cas. Le firmware plafonne le halo à
60 % comme aujourd'hui, et à 30 % quand le module signale une charge en cours
si sa sortie d'état est exploitable. Recommander un chargeur 20 W dans la
notice. Sur un chargeur 5 V sans PD, le CH224D reste en 5 V, le module charge
à 5 W, le halo est complet.

Le buck ne régule pas quand VBUS vaut 5 V : il sort 4,6 à 4,8 V. Les
WS2812C acceptent 3,7 à 5,3 V, le 74AHCT1G125 est spécifié à 4,5 V minimum.
D'où le remplacement de l'AMS1117, dont la chute de 1,2 V ne tiendrait pas le
3V3, par un LDO à faible chute.

## 5. Mécanique

L'aimantation remplace la languette d'appui : le téléphone se pose au centre,
l'anneau d'aimants le cale, il ne touche rien d'autre. Devant le PCB, une
coupelle de 1,2 mm tient le module contre la carte et donne la surface de
contact du téléphone ; le disque garde le jour lumineux de 5 mm sur son
pourtour et ses cannelures. Deux fils passent par le trou central. Socle et
col v1 conservés, le col redessiné en ruban cannelé qui prolonge le disque.
Fentes d'aération dans la paroi, côté mur : le module dissipe 2 à 3 W, essai
au thermocouple sur le proto, surface sous 60 °C, le PETG ramollit vers 80 °C.
L'épaisseur exacte de la coupelle attend les échantillons.

## 6. Conformité, sans laboratoire

- **Radio** : portée par le fabricant du module, sur la foi de sa déclaration
  et de son rapport, versés au dossier. Nous l'alimentons en 9 V par ses
  pastilles plutôt que par son propre port : écart mineur par rapport à sa
  configuration d'essai, à noter dans le dossier.
- **Module ESP32-C3-MINI-1** : certificat radio Espressif, comme en v1.
- **CEM de l'ensemble** : notre évaluation, comme pour l'AdhanBox V3. Un
  analyseur de spectre d'entrée de gamme à 120 € permettra une vérification
  de bon sens quand les premières ventes le financeront.
- **Dossier** : annexe Halo au dossier `conformite/` existant. Déclaration du
  module, certificat ESP32, schémas, notre déclaration UE.

## 7. Plan de travail

1. **Adel** : sélectionner deux fournisseurs de modules avec les documents du
   chapitre 2, commander trois échantillons de chaque.
2. Schéma v2 dans `gen_kicad_sch.py` : CH224D, buck, LDO, pastilles module,
   F1 16 V, suppression de R5/R6. ERC à zéro.
3. PCB v2 dans `gen_kicad_pcb.py` et `route_center.py` : trou central,
   étage 9 V près de la languette, buck près des LEDs. DRC à zéro,
   `export_fab.py` pour BOM, CPL, Gerbers et contrôle des références LCSC.
4. Mécanique dans `gen_coque_pied.py` : coupelle avant aux cotes du module
   retenu, aération, col en ruban. Contrôles de collision et de stabilité.
5. Firmware : plafond de luminosité pendant la charge si l'état est lu.
6. Prototypes : 5 cartes assemblées chez JLCPCB, modules soudés à la main.
   Essais : charge iPhone et Android, température, portée Wi-Fi téléphone posé.
7. Commande de série et annexe CE.

Point ouvert pour Adel : la puissance cible, 15 W avec négociation 9 V, ou
5 W en 5 V pur sans aucun composant ajouté. Le choix se fait à la réception
des modules, selon ce qu'ils acceptent en entrée.
