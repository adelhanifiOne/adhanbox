# Pièce 04 — Datasheets et attestations matières

Archivage documentaire. Ces fichiers ne sont pas transmis aux clients : ils
justifient, devant une autorité de surveillance, que les composants retenus
correspondent à ce qui est déclaré dans la déclaration UE de conformité.

**Dernière mise à jour : août 2026.**

## Documents classés

| Fichier | Rôle dans le produit | Réf. BOM | Source |
|---|---|---|---|
| `ESP32-S3-WROOM-1.pdf` | Module Wi-Fi/BLE — cœur du produit | C2913203 | Espressif, v1.8, 53 p. |
| `MAX98357A.pdf` | Amplificateur audio I²S classe D | C910544 | Maxim/ADI, 38 p. |
| `RX8025T_manuel-application.pdf` | Horloge temps réel — **manuel technique** ETM25E-01 | — | Epson, 33 p. |
| `RX8025T-UC_reference-produit.pdf` | Fiche de la **variante exacte** (-UC) | C53691 | LCSC/Epson, 1 p. |
| `AMS1117-3.3.pdf` | Régulateur 3,3 V | C6186 | Advanced Monolithic, 8 p. |
| `DM3AT-SF-PEJM5.pdf` | Connecteur microSD | C114218 | Hirose, 13 p. |
| `USB-C-16P-HRO.pdf` | Connecteur USB-C 16 broches | C165948 | Korean Hroparts, 1 p. |
| `BAT54C.pdf` | Double Schottky — **aiguillage 3V3/pile** | C2135 | JSCJ, 2 p. |
| `TL3342_tact-switch.pdf` | Boutons RESET et BOOT | C318884 | XKB, 1 p. |
| `Keystone-3000_support-pile.pdf` | Support de pile bouton 12 mm | — | Keystone, plan coté |
| `Keystone_attestation-RoHS.pdf` | Conformité RoHS 3 du support | — | Keystone, 09/2024 |
| `Keystone_attestation-REACH.pdf` | Déclaration REACH du support | — | Keystone, 16 p. |
| `CR-pile-lithium_FDS-Murata.pdf` | **Fiche de données de sécurité** des piles CR | — | Murata, 5 p. |

Le BAT54C mérite une attention particulière : c'est lui qui **empêche tout
courant de charge vers la pile bouton**, ce sur quoi s'appuie le danger n° 4
de l'analyse de risque (pièce 05). Sa datasheet est donc une pièce
justificative, pas un simple document d'archive.

La FDS Murata couvre la chimie, la teneur en lithium et le classement
transport des cellules CR — utile pour l'expédition et pour étayer les
dangers 13 et 14 de la pièce 05.

## Composants sans datasheet individuelle, et pourquoi

Les **passifs** (résistances 10 k / 100 k / 5,1 k, condensateurs 100 nF /
1 µF / 10 µF / 100 µF) ne font pas l'objet d'un archivage pièce par pièce.
C'est l'usage pour un produit assemblé à partir de composants du catalogue
d'un assembleur : leur conformité RoHS est portée par l'attestation globale
de JLCPCB, au titre de la norme EN IEC 63000.

Les **LED WS2812B** ne figurent pas dans la BOM de la carte : elles sont sur
un ruban externe raccordé par J5. Si un jour le ruban est intégré, il faudra
ajouter sa datasheet et son attestation RoHS.

## Ce qui manque encore — et qui ne peut venir que de toi

Ces trois documents dépendent de ton compte ou de tes achats, je ne peux pas
les récupérer à ta place :

1. **Attestation RoHS de JLCPCB** pour les cartes assemblées.
   Téléchargeable depuis la page de ta commande, ou sur simple demande au
   support. C'est la pièce maîtresse du volet RoHS : elle couvre tous les
   composants posés en machine.

2. **Fiche technique du filament PETG** utilisé pour le boîtier, avec sa
   déclaration RoHS/REACH. Les fabricants sérieux la fournissent en
   téléchargement.

3. **Datasheet de la cellule CR1225 réellement achetée.** La FDS Murata
   classée ici vaut comme référence de chimie, mais le dossier doit contenir
   la fiche de la pile que tu mets réellement dans la boîte, avec son
   marquage CE et son symbole de collecte séparée (exigés par le règlement
   UE 2023/1542 depuis le 18/08/2025). À classer au moment de la commande.

À quoi s'ajoute, hors pièce 04 : la **déclaration de conformité de
l'adaptateur secteur USB** fourni dans la boîte. Le fournir revient à le
mettre sur le marché ; sa DoC doit être conservée avec le dossier.

## Point de vigilance : CR1225 ou CR1220 ?

La BOM V3 et toute la documentation (notice, étiquette, analyse de risque)
disent **CR1225**. Le support Keystone 3000 accepte bien les cellules de
12,5 × 2,5 mm, donc c'est cohérent.

Mais une liste d'achat établie plus tôt mentionnait une **CR1220**
(12,5 × 2,0 mm). Les deux entrent dans le support, mais elles n'ont pas la
même capacité — donc pas la même autonomie que les ~7 ans annoncés — et
surtout la notice indique au client d'acheter une CR1225 en remplacement.
**Vérifier ce qui est réellement commandé et aligner les documents**, ou
corriger la notice, l'étiquette et l'analyse de risque en conséquence.
