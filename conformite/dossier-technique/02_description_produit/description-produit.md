# Description du produit — pièce 02 du dossier technique

## Identification

| | |
|---|---|
| **Dénomination commerciale** | AdhanBox |
| **Références modèles** | ADHBX-V2 (matériel v2) · ADHBX-V3 (matériel v3) |
| **Fabricant** | Adel Hanifi — AdhanBox, 14 rue du Corps Franc Pommiès, 65500 Vic-en-Bigorre, France |
| **Contact** | contact@adhanbox.fr — adhanbox.fr |
| **Numérotation de série** | AB2-0001 et suivants (V2) · AB3-0001 et suivants (V3) |
| **Année de première mise sur le marché** | 2026 |

## Fonction et usage prévu

Appareil décoratif et sonore à usage **domestique, en intérieur uniquement**.
Posé sur un meuble, il :

- diffuse l'appel à la prière (adhan) aux horaires de la mosquée choisie
  par l'utilisateur, ou calculés pour sa position ;
- diffuse des récitations audio (Coran, invocations) stockées sur une
  carte mémoire interne ;
- produit une lumière d'ambiance colorée à travers des ouvertures
  décoratives.

Il est piloté depuis une application mobile (iOS/Android) via le réseau
Wi-Fi local, et configuré au premier démarrage par Bluetooth Low Energy.

**Utilisateurs visés :** grand public adulte. Ce n'est pas un jouet et
il n'est pas destiné aux enfants sans surveillance.

## Caractéristiques techniques

| Caractéristique | Valeur |
|---|---|
| Alimentation | 5 V ⎓ via connecteur USB-C (TRÈS BASSE TENSION DE SÉCURITÉ) |
| Courant maximal | ≤ 2 A |
| Adaptateur secteur | **non fourni** / fourni séparément, marqué CE, conforme EN IEC 62368-1 |
| Microcontrôleur / module radio | Espressif **ESP32-S3-WROOM-1** (module pré-certifié, antenne PCB intégrée, non modifiée) |
| Bandes de fréquences | Wi-Fi 2412–2472 MHz · Bluetooth LE 2402–2480 MHz |
| Puissance rayonnée max. | Wi-Fi 19,9 dBm EIRP · BLE 10 dBm EIRP (valeurs du module) |
| Amplificateur audio | MAX98357A (I2S, classe D) |
| Haut-parleurs | 2 × 3 W, **8 Ω chacun** (montés en parallèle sur l'amplificateur mono → 4 Ω vus par le MAX98357A, son minimum admissible). L'emploi de haut-parleurs de 4 Ω est **proscrit** : il ramènerait la charge à 2 Ω. |
| Horloge temps réel | DS3231 (V2) · Epson RX8025T à DTCXO intégré (V3), I²C, sortie d'alarme matérielle |
| Stockage | carte microSD (récitations audio) |
| Pile de sauvegarde de l'horloge | **Pile bouton lithium CR1225, 3 V, non rechargeable** (V3 uniquement). Logée dans un support Keystone 3000 soudé en face arrière de la carte, à l'intérieur du boîtier fermé par vis. Elle n'alimente que l'horloge temps réel en l'absence de secteur ; autonomie estimée ≈ 7 ans à 0,75 µA. Fournie montée dans l'appareil. |
| Éclairage | 25 LED adressables WS2812B, 5 V, basse puissance |
| Boîtier | PETG imprimé en 3D, non conducteur |
| Dimensions / masse | ~85 × 85 × 85 mm · ~250 g |
| Conditions d'utilisation | intérieur sec, 0 °C à 40 °C |
| Indice de protection | IP20 (aucune protection contre l'eau) |

## Architecture

L'alimentation 5 V arrive par l'USB-C, est régulée en 3,3 V (AMS1117)
pour le module radio et les périphériques. Aucune partie du produit
n'est reliée au réseau électrique 230 V : la séparation avec le secteur
est assurée par l'adaptateur USB externe, lui-même certifié.

## Pile de sauvegarde (modèle ADHBX-V3)

La V3 embarque une **pile bouton lithium CR1225 (3 V, ≈ 48 mAh, non
rechargeable)** dont l'unique fonction est de conserver l'heure de
l'horloge temps réel lorsque l'appareil est débranché.

- **Accessibilité :** la pile est logée en face arrière de la carte, à
  l'intérieur du boîtier. Elle **n'est pas accessible sans démonter le
  boîtier à l'aide d'un tournevis cruciforme**. Aucun outil propriétaire
  n'est nécessaire ; aucune chaleur ni solvant.
- **Remplaçabilité :** le support Keystone 3000 permet le retrait et le
  remplacement par l'utilisateur final au moyen d'un outil courant,
  conformément à l'article 11 du règlement (UE) 2023/1542, applicable au
  18 février 2027.
- **Sécurité enfant :** l'inaccessibilité sans outil constitue la mesure
  de réduction du risque d'ingestion (voir pièce 05, danger n° 13).
- **Filière de fin de vie :** pile portable, à déposer dans un bac de
  collecte de piles après retrait. Une consigne figure dans la notice.
- **Approvisionnement :** cellules de marque portant le marquage CE et le
  symbole de collecte séparée exigés par le règlement (UE) 2023/1542
  depuis le 18 août 2025. Le fabricant de la cellule est le producteur au
  sens du marquage ; AdhanBox est producteur au sens de la REP française
  pour les piles mises sur le marché avec l'appareil.

## Élément essentiel pour la conformité radio

Le produit intègre le module **ESP32-S3-WROOM-1**, qui fait l'objet d'un
**certificat d'examen UE de type** délivré par l'organisme notifié
**Eurofins Electrical and Electronic Testing NA (n° 0980)**, daté du
26 janvier 2022, au titre de l'annexe III module B de la directive
2014/53/UE (pièce 01 du présent dossier).

L'antenne PCB intégrée au module (gain 3,26 dBi) **n'est ni modifiée ni
remplacée**, et les conditions d'intégration recommandées par Espressif
sont respectées. La conformité radio du produit s'appuie donc sur celle
du module.
