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
| Haut-parleurs | 2 × 3 W, 4 Ω |
| Horloge temps réel | RX8025T (TCXO) — V3 |
| Stockage | carte microSD (récitations audio) |
| Éclairage | LED adressables 5 V, basse puissance |
| Boîtier | PETG imprimé en 3D, non conducteur |
| Dimensions / masse | ~85 × 85 × 85 mm · ~250 g |
| Conditions d'utilisation | intérieur sec, 0 °C à 40 °C |
| Indice de protection | IP20 (aucune protection contre l'eau) |

## Architecture

L'alimentation 5 V arrive par l'USB-C, est régulée en 3,3 V (AMS1117)
pour le module radio et les périphériques. Aucune partie du produit
n'est reliée au réseau électrique 230 V : la séparation avec le secteur
est assurée par l'adaptateur USB externe, lui-même certifié.

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
