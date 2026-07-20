# Feuille de route CE — AdhanBox

> Objectif : vendre légalement en France/UE un appareil électronique
> avec Wi-Fi + Bluetooth. Voie « artisan » : autoévaluation appuyée sur
> des modules radio déjà certifiés. Ce document n'est pas un avis
> juridique — c'est le plan de travail standard du secteur.

## 1. Ce qui s'applique à l'AdhanBox

| Texte | Pourquoi ça te concerne |
|---|---|
| **Directive RED 2014/53/UE** | La box émet en radio (Wi-Fi + BLE). La RED couvre à la fois la partie radio, la CEM et la sécurité électrique des équipements radio. C'est LE texte central. |
| **RoHS 2011/65/UE** | Limitation des substances dangereuses. Couvert en pratique par des composants/PCB « RoHS compliant » (JLCPCB l'est). |
| **DEEE (WEEE)** | Équipement électronique → symbole poubelle barrée + adhésion à un éco-organisme + identifiant unique (IDU). |
| **RGPD** | Déjà traité (privacy.html, pas de données stockées côté serveur). |
| **Règlement sécurité générale des produits (GPSR 2023/988)** | Exige traçabilité : nom + adresse du fabricant sur le produit/emballage, notice en français, point de contact. |

**Bonne nouvelle n°1 :** ton alimentation est un simple câble USB-C 5 V.
Pas de bloc secteur fourni = pas de haute tension dans ton produit.
Si tu fournis un adaptateur, achète-le **déjà marqué CE** chez un
fournisseur sérieux (ne jamais fabriquer/importer l'alim toi-même).

**Bonne nouvelle n°2 :** le module **ESP32-S3-WROOM-1 (Espressif) est
pré-certifié** (rapports RED/CE disponibles publiquement chez Espressif).
Utiliser un module certifié sans modifier son antenne te permet de
t'appuyer sur ses rapports de test radio dans ton dossier. Tu restes
responsable du produit final, mais tu n'as pas à refaire les essais
radio du module.

## 2. Le dossier technique (à constituer, conserver 10 ans)

Un classeur (numérique) nommé `dossier-technique-adhanbox/` :

1. **Description du produit** — photos, fonction, référence modèle
   (ex. « ADHBX-V2 »), versions matérielles.
2. **Schémas + BOM** — tu les as déjà (KiCad V2/V3, BOM JLCPCB).
3. **Datasheets et certificats des modules** :
   - ESP32-S3-WROOM-1 : datasheet + certificat RED Espressif
     (téléchargeable sur espressif.com → Certification).
   - MAX98357A, RX8025T : datasheets.
4. **Normes appliquées** (autoévaluation) :
   - EN 300 328 (radio 2,4 GHz) — couverte par le module ;
   - EN 301 489-1/-17 (CEM radio) ;
   - EN IEC 62368-1 (sécurité des équipements audio/vidéo & TIC) ;
   - EN IEC 63000 (documentation RoHS).
5. **Analyse de risque** — 1 à 2 pages : échauffement, petites pièces,
   usage en intérieur, alimentation 5 V limitée.
6. **Notice en français** — le guide de démarrage (store_assets/guide/)
   compte, ajoute les avertissements (usage intérieur, ne pas couvrir,
   nettoyer débranché, ne pas ouvrir).
7. **Étiquette produit** (voir §3).
8. **Déclaration UE de conformité signée** (modèle dans ce dossier).

## 3. Le marquage sur le produit / l'emballage

Sous la box (gravé, imprimé ou étiquette résistante) :

```
AdhanBox — modèle ADHBX-V2
Adel Hanifi — [adresse] — adhanbox.fr
5 V ⎓ 2 A (USB-C) — Usage intérieur
CE   [poubelle barrée]
Fabriqué en France
```

- **CE** : minimum 5 mm de haut, proportions officielles.
- **Poubelle barrée** (DEEE) : obligatoire sur le produit.
- **Triman + info-tri** : sur l'emballage (généré par l'éco-organisme).
- Numéro de série : recommandé (traçabilité GPSR) — un simple
  compteur « AB2-0001 » suffit.

## 4. Démarches administratives (une fois, ~1-2 h)

1. **Éco-organisme DEEE** : adhère à **ecosystem** (ecosystem.eco) ou
   **Ecologic** — barème « petit producteur », quelques dizaines
   d'euros/an aux volumes AdhanBox.
2. **IDU ADEME** : l'éco-organisme t'inscrit au registre SYDEREP →
   tu reçois un **Identifiant Unique** (format FR2026xxxxx) à faire
   figurer dans tes CGV (déjà une section « environnement » ? sinon
   je l'ajoute).
3. **Emballages ménagers** : même principe (Citeo/Léko), contribution
   symbolique à ton volume, IDU emballages également.

## 5. Ordre de marche conseillé

- [ ] Semaine 1 : télécharger les certificats Espressif, créer le
      dossier technique, rédiger l'analyse de risque (je peux la
      rédiger), compléter la notice avec les avertissements.
- [ ] Semaine 1 : remplir + signer la Déclaration UE (modèle fourni).
- [ ] Semaine 2 : étiquette produit (je peux te la dessiner aux
      dimensions), adhésion ecosystem + IDU.
- [ ] Optionnel mais recommandé quand la trésorerie le permet : un
      passage en labo CEM pour l'appareil complet (~500-1500 €) —
      ça blinde le dossier, surtout si les volumes montent.

## 6. Ce qu'il ne faut PAS faire

- Vendre avec un logo CE sans dossier derrière (c'est ça qui est
  sanctionnable, pas l'artisanat).
- Fournir un chargeur secteur non-CE acheté en marketplace.
- Modifier l'antenne du module WROOM (tu perdrais le bénéfice de sa
  certification).
