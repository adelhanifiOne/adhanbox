# Dossier technique AdhanBox — marquage CE

Dossier à **conserver 10 ans** après la dernière mise sur le marché.
Il n'est pas à transmettre aux clients : il est présenté sur demande
des autorités de surveillance du marché (DGCCRF, ANFR).

**Dernière révision : août 2026** — intégration du matériel V3 (pile de
sauvegarde CR1225, horloge RX8025T) et des exigences de cybersécurité de
la RED, applicables depuis le 1er août 2025.

## État des pièces

| # | Pièce | Contenu | État |
|---|---|---|---|
| **01** | Certificats des modules | Certificat d'examen UE de type ESP32-S3-WROOM-1 (Eurofins, ON n° 0980, 26/01/2022) | ✅ présent |
| **02** | Description du produit | Identification, usage prévu, caractéristiques, architecture, **pile de sauvegarde** | ✅ à jour V2 + V3 |
| **03** | Schémas et nomenclature | Schémas KiCad V2 et V3 (PDF) + BOM V2 et V3 | ✅ présent |
| **04** | Datasheets | Fiches des composants + attestations RoHS | ⬜ **à télécharger** (liste dans le dossier) |
| **05** | Analyse de risque | **14 dangers** analysés, révision 2 incluant la pile bouton | ✅ rédigée — ⬜ **à signer** |
| **06** | Notice utilisateur | Guide de démarrage français, avertissements, déclaration RED art. 10.8 | ✅ présent |
| **07** | Étiquetage | Planches 55 × 32 mm, **une par modèle** (V2 et V3) | ✅ prêtes à imprimer |
| **08** | Déclaration UE de conformité | **Une par modèle** : ADHBX-V2 et ADHBX-V3 | ✅ rédigées — ⬜ **à signer** |
| **09** | Vulnérabilités | Procédure de traitement + registre (RED 3.3 et CRA) | ✅ rédigée |

## Ce qu'il reste à faire

1. **Télécharger 5 datasheets** (pièce 04, liste et liens dans le dossier)
   et l'attestation RoHS de JLCPCB → environ 20 minutes.
2. **Imprimer, dater et signer**, en prenant bien la version V3 pour les
   25 cartes en cours :
   - `05_analyse_de_risque/analyse-de-risque.md`
   - `08_declaration_de_conformite/declaration-UE-de-conformite-V3.md`
   Ranger les originaux signés avec les documents d'entreprise.
3. **Imprimer les étiquettes du bon modèle** :
   `07_etiquetage/etiquette-produit-V3.pdf` pour les séries AB3-.
4. **Adhérer aux éco-organismes** : ecosystem ou Ecologic (EEE), Corepile
   ou Screlec (piles — nouvelle filière depuis la V3), Citeo (emballages).
   Reporter les trois **IDU** dans les CGV et sur `conformite.html`
   (emplacements marqués `TODO conformite` dans le code du site).
5. **Conserver la déclaration de conformité de l'adaptateur secteur**
   fourni dans la boîte : le fournir revient à le mettre sur le marché.

## Points de vigilance introduits par la V3

- **La pile bouton est le seul danger de gravité très élevée du produit**
  (pièce 05, ligne 13). La mesure qui le maîtrise est son inaccessibilité
  sans outil. Toute évolution du boîtier qui la rendrait accessible impose
  de revoir l'analyse et d'ajouter un compartiment à sécurité enfant.
- **Une déclaration ne couvre que le modèle qu'elle nomme.** La V2 ne
  couvre pas la V3.
- Le certificat Eurofins du module est **antérieur** aux exigences de
  cybersécurité : celles-ci relèvent de l'évaluation du produit fini,
  documentée au point 9 de la déclaration V3 et en pièce 09.

## Rappel de calendrier

Le marquage CE doit être en place **au moment où la première box est
expédiée**, pas au moment de la précommande.

Le signalement des vulnérabilités activement exploitées devient
obligatoire le **11 septembre 2026** (règlement UE 2024/2847) ; les
obligations complètes, dont le SBOM, au **11 décembre 2027**.

## Réserve

Ce dossier a été préparé selon la démarche standard d'autoévaluation
applicable à un produit intégrant un module radio pré-certifié. Il ne
constitue pas un avis juridique. Si les volumes augmentent sensiblement,
un essai CEM en laboratoire sur l'appareil complet (≈ 500–1 500 €) et
la relecture par un consultant CE sont recommandés.
