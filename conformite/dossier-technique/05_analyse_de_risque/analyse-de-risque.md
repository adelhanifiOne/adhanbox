# Analyse de risque — pièce 05 du dossier technique

**Produit :** AdhanBox (ADHBX-V2 / ADHBX-V3)
**Méthode :** identification des dangers, évaluation (gravité × probabilité),
mesures de réduction, risque résiduel. Référentiel : EN IEC 62368-1
(classes d'énergie) et principes généraux du règlement 2023/988 (GPSR).
**Date :** juillet 2026 — **Rédacteur :** Adel Hanifi

## Contexte réduisant fortement les risques

Le produit fonctionne exclusivement en **5 V continu (TBTS)**, fourni par
un adaptateur USB externe marqué CE. **Aucune tension dangereuse n'est
présente à l'intérieur du produit.** Cela écarte d'emblée la majorité des
risques électriques traités par EN IEC 62368-1.

## Tableau d'analyse

| # | Danger | Situation | Gravité | Probabilité | Mesures de réduction | Risque résiduel |
|---|---|---|---|---|---|---|
| 1 | **Électrique** — choc | Contact avec les parties internes | Faible | Très faible | Alimentation 5 V TBTS uniquement ; aucun potentiel dangereux accessible ; boîtier PETG isolant | **Négligeable** |
| 2 | **Électrique** — court-circuit / adaptateur non conforme | Utilisateur branche un chargeur de mauvaise qualité | Moyenne | Faible | Notice : « utilisez un adaptateur USB certifié CE » ; connecteur USB-C standard ; régulateur avec condensateurs de découplage | **Faible** |
| 3 | **Thermique** — échauffement | Fonctionnement prolongé, appareil couvert | Faible | Faible | Puissance totale < 10 W ; ouvertures décoratives assurant la ventilation naturelle ; avertissement notice « ne pas couvrir » ; PETG stable jusqu'à ~70 °C, températures mesurées très en deçà | **Faible** |
| 4 | **Incendie** | Défaut interne | Élevée | Très faible | Courant limité par l'adaptateur (≤ 2 A à 5 V = 10 W max) ; composants dimensionnés avec marge ; pas de batterie lithium dans le produit | **Faible** |
| 5 | **Audition** | Volume sonore excessif près de l'oreille | Moyenne | Faible | Appareil de table, écoute à distance ; puissance 2 × 3 W ; réglage du volume dans l'application ; usage non nomade (pas d'écouteurs) | **Faible** |
| 6 | **Mécanique** — petites pièces | Carte microSD avalée par un enfant | Élevée | Faible | Logement interne, non accessible sans ouvrir le boîtier ; avertissement notice « tenir hors de portée des enfants » ; produit non destiné aux enfants | **Faible** |
| 7 | **Mécanique** — bords, chute | Manipulation | Faible | Faible | Arêtes adoucies à l'impression ; masse faible (~250 g) ; pas de verre | **Négligeable** |
| 8 | **Exposition aux champs RF** | Proximité prolongée | Faible | Très faible | Module conforme **EN 50665:2017** (certificat Eurofins) ; puissance ≤ 19,9 dBm EIRP ; usage à distance (appareil posé, non porté) | **Négligeable** |
| 9 | **Perturbations électromagnétiques** | Gêne d'autres appareils | Faible | Faible | Module conforme **EN 301 489-1 / -17** et **EN 300 328** ; plan de masse et découplage soignés sur le PCB | **Faible** |
| 10 | **Liquides** | Renversement d'un verre | Moyenne | Faible | IP20 assumé ; avertissement notice « usage intérieur sec, ne pas exposer aux liquides » ; ouvertures en face supérieure limitées au décor | **Faible** |
| 11 | **Sécurité des données** | Accès non autorisé à l'appareil | Faible | Faible | Jeton d'API par appareil, mot de passe OTA aléatoire par appareil, **mises à jour signées (ECDSA)** refusant tout firmware non authentifié ; aucune donnée personnelle stockée sur serveur | **Faible** |
| 12 | **Fin de vie** | Rebut en ordures ménagères | Faible | Moyenne | Symbole poubelle barrée sur le produit ; adhésion à un éco-organisme DEEE ; information de tri sur l'emballage | **Faible** |

## Conclusion

Aucun risque résiduel inacceptable n'a été identifié. Les mesures de
réduction retenues sont : l'alimentation exclusive en très basse tension
de sécurité, l'usage d'un module radio certifié avec antenne d'origine,
la ventilation naturelle du boîtier, les mises à jour signées, et les
avertissements portés dans la notice utilisateur (pièce 06).

**Le produit est jugé sûr pour l'usage prévu et raisonnablement
prévisible.**

Signature du fabricant : ______________________  Date : ____ / ____ / 2026
