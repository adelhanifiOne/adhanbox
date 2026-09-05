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

## `cercles_support_led.py`

Écart entre l'arche et le petit cercle, sur les **deux faces courtes** de
`support_led`. Constaté à l'impression le 03/09/2026 : la paroi entre les deux
était trop fine et sortait mal.

**Deux pièces portent le même motif, ne pas se tromper de cible.**
`AdhanBox_Fusion` est la coque extérieure (corps racine), souvent **masquée** ;
`support_led / AdhanBox_Lid.step` est le support intérieur, **visible**. Elles
s'emboîtent : les ouvertures du support sont dessinées ~1 mm plus grandes que
celles de la coque, pour que ce soit la coque qui dessine la forme vue. Mesurer
la mauvaise des deux fait perdre beaucoup de temps — ça m'est arrivé.

**Le diagnostic** — sur `support_led`, 4 arches de 14 mm et 3 cercles Ø7. La
face longue les espace au pas de 21 mm, la face courte au pas de 19 mm.

| | face courte | face longue |
|---|---|---|
| pas du motif | 19 mm | 21 mm |
| matière arche/cercle **avant** | **0,329 mm** | 1,118 mm |
| matière arche/cercle **après** | **0,961 mm** | 1,118 mm (inchangé) |

0,33 mm, c'est moins d'un trait de buse.

**Le correctif** — la pièce vient d'un STEP importé : on ne peut pas y rétrécir
un trou, il faut **ajouter** de la matière. Le script pose une couronne
(extérieur Ø7, intérieur Ø5,5) dans chacun des 3 cercles des deux faces
courtes, extrudée en jonction sur les 1,2 mm d'épaisseur de paroi. Les faces
longues ne sont pas touchées.

**Le réglage du diamètre** — la matière restante suit le diamètre choisi :

| diamètre | matière | vs la face longue (1,118 mm) |
|---|---|---|
| Ø5,0 | 1,250 mm | au-dessus |
| Ø5,2 | ≈ 1,13 mm | à égalité |
| **Ø5,5** *(retenu)* | **0,961 mm** | en dessous de 14 % |

Si une impression montre encore un défaut, descendre `R_INT` dans le script.

**Valeurs de contrôle** (03/09/2026)

| contrôle | valeur |
|---|---|
| matière la plus fine, faces courtes | 0,961 mm |
| matière la plus fine, face longue | 1,118 mm |
| cercles, faces courtes | Ø5,5 |
| cercles, faces longues | Ø7,0 |
| fonctions ajoutées | `reduction_cercles_mur_Y0`, `reduction_cercles_mur_Y99` |

Le script est **rejouable** : au second passage il annonce « déjà présent ».

## `encoche_fils_led.py`

Le trou carré de la dalle du support LED (35 × 35 mm, lamage 39,4 mm où la
carte LED se pose) n'avait **aucun passage pour les fils** : ils étaient pincés
entre la carte et la dalle. Le script ouvre une encoche de **20 × 6 mm**,
traversante, sur le côté du carré qui regarde le **port USB-C de la coque** —
la carte principale et ses connecteurs sont dessous, les fils descendent droit.

Rien n'est codé en dur : le carré est mesuré sur la face du dessous, le côté
est choisi en lisant la coque (le perçage rond Ø13 du port USB-C), et
l'encoche est posée depuis l'arête du carré. **Rejouable** : si
`Encoche_fils_LED` existe déjà, il ne fait rien.

**Valeurs de contrôle** (05/09/2026, coordonnées locales du support)

| contrôle | valeur |
|---|---|
| carré mesuré | X 26,50 → 61,50 · Y 32,00 → 67,00 |
| côté retenu | +X (USB-C de la coque en X = 93,5 monde) |
| encoche | X 61,50 → 67,50 · Y 39,50 → 59,50 · Z 0 → 5 traversante |
| marge au bord de carte (lamage à X = 63,70) | 3,8 mm : les fils passent sous la carte |
| ouverture du dessous après coupe | X 26,50 → 67,50, 8 arêtes |

Le fond de 6 mm est un choix : assez pour trois fils en nappe, loin des plots
d'aimant (X ≈ 78,5) et des vis (X = 83). Changer `FOND` ou `LARGEUR` en tête
du script si un connecteur plus gros doit passer.

## Et surtout

**Enregistrer le document Fusion après exécution.** C'est la seule chose que
le script ne peut pas faire à ta place.
