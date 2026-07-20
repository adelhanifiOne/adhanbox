# Dossier technique AdhanBox — marquage CE

Dossier à **conserver 10 ans** après la dernière mise sur le marché.
Il n'est pas à transmettre aux clients : il est présenté sur demande
des autorités de surveillance du marché (DGCCRF, ANFR).

## État des pièces

| # | Pièce | Contenu | État |
|---|---|---|---|
| **01** | Certificats des modules | Certificat d'examen UE de type ESP32-S3-WROOM-1 (Eurofins, ON n° 0980, 26/01/2022) | ✅ **présent** |
| **02** | Description du produit | Identification, usage prévu, caractéristiques, architecture | ✅ **rédigé** |
| **03** | Schémas et nomenclature | Schémas KiCad V2 et V3 (PDF) + BOM V2 et V3 | ✅ **présent** |
| **04** | Datasheets | Fiches des composants + attestations RoHS | ⬜ **à télécharger** (liste dans le dossier) |
| **05** | Analyse de risque | 12 dangers analysés, mesures, risque résiduel | ✅ **rédigé — à signer** |
| **06** | Notice utilisateur | Guide de démarrage français, avec avertissements | ✅ **présent** |
| **07** | Étiquetage | Planche d'étiquettes 55 × 32 mm (CE + DEEE + traçabilité) | ✅ **prêt à imprimer** |
| **08** | Déclaration UE de conformité | Alignée sur les normes du certificat module | ✅ **rédigée — à signer** |

## Ce qu'il te reste à faire

1. **Télécharger 5 datasheets** (pièce 04, liste et liens dans le dossier)
   et l'attestation RoHS de JLCPCB → environ 20 minutes.
2. **Imprimer, dater et signer** :
   - `05_analyse_de_risque/analyse-de-risque.md`
   - `08_declaration_de_conformite/declaration-UE-de-conformite.md`
   Ranger les originaux signés avec tes documents d'entreprise.
3. **Imprimer les étiquettes** (`07_etiquetage/etiquette-produit.html`)
   sur papier autocollant et en coller une sous chaque boîtier vendu.
4. **Adhérer à un éco-organisme DEEE** (ecosystem.eco ou ecologic-france.com,
   barème petit producteur) → tu recevras un **identifiant unique (IDU)**
   à faire figurer dans tes CGV. Faire de même pour les emballages (Citeo).
5. **Pour la V3** : dupliquer la déclaration en remplaçant ADHBX-V2 par
   ADHBX-V3 (le module radio est identique, le reste du dossier vaut
   pour les deux).

## Rappel de calendrier

Le marquage CE doit être en place **au moment où la première box est
expédiée**, pas au moment de la précommande. Livraison prévue à
l'automne 2026 → tout ceci doit être bouclé avant la première expédition.

## Réserve

Ce dossier a été préparé selon la démarche standard d'autoévaluation
applicable à un produit intégrant un module radio pré-certifié. Il ne
constitue pas un avis juridique. Si les volumes augmentent sensiblement,
un essai CEM en laboratoire sur l'appareil complet (≈ 500–1 500 €) et
la relecture par un consultant CE sont recommandés.
