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

## Et surtout

**Enregistrer le document Fusion après exécution.** C'est la seule chose que
le script ne peut pas faire à ta place.
