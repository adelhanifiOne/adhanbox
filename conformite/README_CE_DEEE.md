# Dossier conformité AdhanBox — CE (RED) + DEEE

État au 2026-07-13. Objectif : pouvoir vendre légalement en France/UE.
La V3 (module ESP32-S3-WROOM-1 pré-certifié) est la base retenue pour la prod.

## 1. Marquage CE — directive RED 2014/53/UE

L'AdhanBox émet en radio (Wi-Fi 2,4 GHz + BLE) → directive RED applicable.
Voie choisie : **auto-déclaration en s'appuyant sur le module pré-certifié**.

### Ce qui joue pour nous
- Le module **ESP32-S3-WROOM-1** (Espressif) est certifié CE/RED par Espressif
  (rapports RF/EMC disponibles sur espressif.com, section Certificates).
  L'antenne, le blindage et la partie radio ne sont PAS modifiés par notre design.
- Alimentation 5 V via USB-C (pas de secteur intégré) → pas de directive basse
  tension (LVD s'applique à partir de 50 V AC / 75 V DC).
- Pas de batterie.

### Ce qu'il reste à NOTRE charge
- [ ] **Dossier technique** (ce dossier) : schémas (AdhanBoxPCBV3_schema.pdf),
      BOM, photos produit, notice, rapports du module Espressif (à télécharger
      et archiver ici), description du produit final.
- [ ] **Évaluation EMC du produit fini** : le module est certifié seul, pas
      notre carte complète. Pour un premier lot artisanal, l'usage courant des
      petits fabricants est l'auto-évaluation documentée (design conforme aux
      guidelines Espressif : plan de masse, keep-out antenne — fait sur la V3).
      Pour passer à l'échelle (>quelques centaines/an), prévoir un passage en
      labo EMC (~1 500-3 000 € : EN 55032/55035, EN 301 489, EN 300 328).
- [ ] **Déclaration UE de conformité** signée : brouillon dans
      `DECLARATION_UE_CONFORMITE.md` — à compléter (adresse, n° de modèle) et
      à joindre en PDF à chaque dossier produit. Doit être tenue à disposition
      10 ans.
- [ ] **Marquage sur le produit** : logo CE (min 5 mm) + nom/adresse fabricant
      + référence modèle (ex. ADB-V3) + n° de série → à intégrer :
      - gravé/imprimé sous le boîtier (le fond est imprimé 3D : intégrer le
        marquage dans le modèle Fusion, relief 0,4 mm), et
      - sur la notice + l'emballage.
- [ ] **Notice** : doit inclure les infos de sécurité (alimentation 5 V,
      usage intérieur), la bande de fréquence utilisée (2,4 GHz, P < 100 mW)
      et la déclaration de conformité simplifiée : « Le soussigné, Adel
      Hanifi, déclare que l'équipement AdhanBox est conforme à la directive
      2014/53/UE. Le texte complet de la déclaration est disponible à
      l'adresse : [URL] ».

## 2. DEEE (déchets d'équipements électriques et électroniques)

Vendre un produit électronique en France = obligations « metteur sur le marché » :

- [ ] **Adhérer à un éco-organisme** agréé DEEE ménager : **Ecosystem**
      (ecosystem.eco) ou Ecologic. Adhésion en ligne, éco-participation
      de l'ordre de quelques dizaines de centimes par appareil de cette taille.
- [ ] Obtenir l'**IDU** (identifiant unique) au registre SYDEREP de l'ADEME —
      fourni via l'éco-organisme. L'IDU doit figurer dans les CGV et documents
      commerciaux.
- [ ] **Symbole poubelle barrée** sur le produit (avec le marquage CE, sous le
      boîtier) + notice.
- [ ] Déclarer chaque année les quantités mises sur le marché.

## 3. Autres points

- [ ] **RoHS** (2011/65/UE) : composants sourcés LCSC/JLCPCB = RoHS par défaut,
      collecter les attestations dans la BOM. Marquage CE couvre RoHS.
- [ ] **Emballage** : depuis 2023, adhésion éco-organisme emballages (Citeo)
      requise aussi pour les petits metteurs sur le marché (tarif plancher
      ~80 €/an aux petits volumes). À faire en même temps qu'Ecosystem.
- [ ] **Médiateur de la consommation** : adhésion obligatoire avant les
      premières ventes (ex. CNPM Médiation, ~50-100 €/an). Reporter les
      coordonnées dans cgv.html §12.
- [ ] Télécharger et archiver ici : certificats CE + rapports de test du module
      ESP32-S3-WROOM-1 (espressif.com → Support → Certificates), datasheet
      RX8025T, MAX98357A.

## Ordre d'attaque conseillé

1. Ecosystem + Citeo + médiateur (3 inscriptions en ligne, ~1 h, faisable dès
   maintenant sans attendre les protos).
2. Marquage CE + poubelle barrée intégrés au modèle 3D du fond du boîtier.
3. Dossier technique rempli au fil de la validation des protos V3.
4. Déclaration UE signée le jour où la config de prod est figée.
