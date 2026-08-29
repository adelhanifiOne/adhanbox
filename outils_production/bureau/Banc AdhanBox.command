#!/bin/bash
# Banc de production AdhanBox V3 — raccourci de bureau.
# Double-clic : ouvre le banc dans le navigateur.
# Pour l'arreter : Ctrl+C ici, ou ferme simplement cette fenetre.

PROJET="$HOME/Projects/adhanbox"
PORT=8765

cd "$PROJET" || {
  echo "Le dossier du projet est introuvable :"
  echo "  $PROJET"
  echo
  echo "Appuie sur une touche pour fermer."
  read -r -n 1
  exit 1
}

clear 2>/dev/null
echo "┌───────────────────────────────────────────────┐"
echo "│   Banc de production — AdhanBox V3             │"
echo "└───────────────────────────────────────────────┘"
echo

# Deuxieme double-clic alors que le premier tourne encore : c'est le cas le
# plus frequent. On le regle ici plutot que de renvoyer l'operateur au
# terminal, qu'il n'a de toute facon pas sous la main depuis le bureau.
ANCIEN=$(lsof -nP -tiTCP:$PORT -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$ANCIEN" ]; then
  echo "  Un banc est deja ouvert (processus $ANCIEN)."
  echo "  Le relancer chargera la derniere version de l'outil."
  echo
  printf "  Fermer l'ancien et relancer ? [O/n] "
  read -r REP
  case "$REP" in
    [nN]*)
      echo
      echo "  Rien n'a ete touche. L'onglet deja ouvert reste utilisable."
      echo "  Tu peux fermer cette fenetre."
      exit 0
      ;;
    *)
      kill "$ANCIEN" 2>/dev/null
      sleep 1
      kill -9 "$ANCIEN" 2>/dev/null
      echo "  Ancien banc ferme."
      echo
      ;;
  esac
fi

echo "  Le banc s'ouvre dans ton navigateur."
echo "  Laisse cette fenetre ouverte tant que tu testes."
echo "  Pour arreter : Ctrl+C, ou ferme cette fenetre."
echo

python3 outils_production/banc_gui.py

echo
echo "  Banc arrete. Tu peux fermer cette fenetre."
