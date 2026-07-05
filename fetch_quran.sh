#!/bin/bash
# Telecharge + nettoie (ESP-safe, sans perte) le Coran complet de 4 recitateurs
# vers sd_preload/quran/<slug>/NNN.mp3. Reprend ou il s'est arrete (skip existants).
set -u
cd "$(dirname "$0")"
OUT="sd_preload/quran"
LOG="/tmp/fetch_quran.log"
: > "$LOG"

# slug | base URL (murattal Hafs, mp3quran)
RECS=(
"afs|https://server8.mp3quran.net/afs"
"ghamdi|https://server7.mp3quran.net/s_gmd"
"dosari|https://server11.mp3quran.net/yasser"
"maher|https://server12.mp3quran.net/maher"
)

echo "$(date '+%H:%M:%S') DEBUT" | tee -a "$LOG"
for entry in "${RECS[@]}"; do
  slug="${entry%%|*}"; base="${entry#*|}"
  mkdir -p "$OUT/$slug"
  ok=0; skip=0; fail=0
  for i in $(seq 1 114); do
    n=$(printf "%03d" "$i")
    dst="$OUT/$slug/$n.mp3"
    # skip si deja present et valide (header MP3 ffXX, pas ID3)
    if [ -f "$dst" ] && [ "$(head -c1 "$dst" | xxd -p)" = "ff" ]; then skip=$((skip+1)); continue; fi
    # download + strip pochette/ID3 sans re-encoder (qualite source preservee)
    if ffmpeg -y -loglevel error -i "$base/$n.mp3" -map 0:a:0 -c:a copy -id3v2_version 0 -map_metadata -1 "$dst" 2>>"$LOG"; then
      hdr=$(head -c1 "$dst" | xxd -p)
      if [ "$hdr" = "ff" ]; then ok=$((ok+1)); else
        # fallback : re-encode propre si le copy a laisse un mauvais header
        ffmpeg -y -loglevel error -i "$base/$n.mp3" -map 0:a:0 -c:a libmp3lame -b:a 128k -ar 44100 -id3v2_version 0 -map_metadata -1 "$dst" 2>>"$LOG" && ok=$((ok+1)) || { fail=$((fail+1)); rm -f "$dst"; }
      fi
    else fail=$((fail+1)); rm -f "$dst"; fi
    [ $(( (ok+skip+fail) % 20 )) -eq 0 ] && echo "$(date '+%H:%M:%S') $slug: $((ok+skip+fail))/114 (ok=$ok skip=$skip fail=$fail)" | tee -a "$LOG"
  done
  echo "$(date '+%H:%M:%S') $slug TERMINE: ok=$ok skip=$skip fail=$fail" | tee -a "$LOG"
done
echo "$(date '+%H:%M:%S') FIN. Total: $(find "$OUT" -name '*.mp3' | wc -l | tr -d ' ') fichiers, $(du -sh "$OUT" | awk '{print $1}')" | tee -a "$LOG"
