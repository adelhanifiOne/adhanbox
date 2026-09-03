# Scripts Fusion 360

Ce dossier existe parce qu'un travail Fusion a été perdu le 24/08/2026 en
fermant le document sans enregistrer. Tout ce qui est conçu par script y est
versionné : le modèle Fusion peut disparaître, la conception se rejoue.

## `fermeture_aimantee.py`

Fermeture aimantée entre `support_led` (AdhanBox_Lid.step) et `diffusion_lum`
(Lid_Vierge.step) : le couvercle se pose par aimants, sans vis.

**Exécution** — Fusion → *Utilitaires* → *Scripts et modules complémentaires*
→ *Mes scripts* → ajouter ce fichier → *Exécuter*. Le document
`AdhanBox_Fusion` doit être ouvert, avec les deux pièces à l'état vierge
(seule la « Fonction de base1 »). Le script est **rejouable** : il mesure le
modèle au lieu de coder les cotes en dur, donc il fonctionne même si les
occurrences ont été déplacées.

**Ce qu'il produit**

| pièce | ajout |
|---|---|
| support_led | 4 plots Ø10, du dessus de dalle jusqu'à 0,30 mm sous la jupe |
| support_led | 4 logements Ø6,2 × 2,2 dans les plots |
| diffusion_lum | 4 goussets à 45° dans les angles |
| diffusion_lum | 4 logements Ø6,2 × 2,2 dans les goussets |

Aimants : **Ø6 × 2 mm**, 8 par boîtier, **200 pour une série de 25**. Toutes
les paires dans le même sens — la bride 95 × 106 ne se pose que dans un sens.

**Valeurs de contrôle attendues** (mesurées après exécution, 24/08/2026)

| contrôle | valeur |
|---|---|
| aimants | (13, 13) (82, 13) (13, 93) (82, 93) |
| plots | Z 50,00 → 58,70 |
| logements support | Z 56,50 → 58,70 |
| logements diffuseur | Z 59,00 → 61,20 |
| entrefer | 0,30 mm |
| ancrage des goussets dans la paroi | 0,91 mm |
| coin de gousset / centre de congé | 4,80 mm (limite 4,80) |
| dépassement hors peau | 0 point |
| surplomb à l'impression (45°, couches 0,2) | 0 point non soutenu |
| appariement plot ↔ logement | 0,002 mm |

L'intersection booléenne support/diffuseur renvoie ≈ 1,31 mm³ : c'est un film
de **3 µm** sur tout le rebord, la face de contact plaque/rebord. Ce n'est pas
une collision — elle disparaît dès 0,02 mm de jeu, et elle est identique
goussets supprimés.

## Impression

Le diffuseur s'imprime **bride en bas**. Les goussets sont conçus pour cette
orientation : ils naissent en pointe sur la paroi et grossissent à 45° vers le
bas, donc **aucun support n'est nécessaire**. Vérifié par balayage : 0 point
non soutenu.

## `cercles_faces_courtes.py`

Écart entre l'arche et le petit cercle, sur les **deux faces courtes** du
boîtier. Constaté à l'impression le 03/09/2026 : la paroi entre les deux était
trop fine et sortait mal.

**Le diagnostic** — les 4 arches (12 mm) et les 3 cercles (Ø5) sont dessinés
identiques sur les quatre faces. Mais la face courte fait 95,2 mm contre
106 mm : le motif y est serré au pas de **19 mm au lieu de 21**.

| | face courte | face longue |
|---|---|---|
| largeur | 95,2 mm | 106 mm |
| pas du motif | 19 mm | 21 mm |
| écart arche/cercle **avant** | **2,03 mm** | 2,94 mm |
| écart arche/cercle **après** | **3,01 mm** | 2,94 mm (inchangé) |

**Pourquoi on n'écarte pas le motif** — les angles portent un congé **R8 sur
toute la hauteur** (centres 8,8 / 87,8 / 87,98 / 8,98). La partie *plate* de la
face courte ne fait donc que **79 mm**. Le motif espacé comme sur les faces
longues en occuperait 75 : il ne resterait que 2 mm jusqu'au congé.

**Le correctif** — les 3 cercles des faces courtes passent de **Ø5 à Ø3**. Les
arches, motif signature, ne bougent pas ; les cercles des faces longues non
plus. La face courte cesse d'être le point faible.

`Esquisse4` pilote les deux faces courtes (plan XZ), `Esquisse6` les deux faces
longues (plan YZ). Les deux esquisses sont **libres** — ni cote ni contrainte —
donc le rayon se règle directement par l'API.

**Valeurs de contrôle** (mesurées par `measureMinimumDistance`, 03/09/2026)

| contrôle | valeur |
|---|---|
| paroi la plus fine, face courte | 3,013 mm |
| paroi la plus fine, face longue | 2,940 mm |
| diamètre des cercles, faces courtes | 3,0 mm |
| diamètre des cercles, faces longues | 5,0 mm |

Le script est **rejouable** : au second passage il annonce « 0 cercle ramené »
et se contente de remesurer.

## Et surtout

**Enregistrer le document Fusion après exécution.** C'est la seule chose que
le script ne peut pas faire à ta place.
