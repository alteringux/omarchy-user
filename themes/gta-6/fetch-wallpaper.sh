#!/bin/bash
# Fetch a fresh Grand Theft Auto IV wallpaper from Wallhaven and stage it in the
# gta-6 theme's user-backgrounds pool.
#
# Wallhaven bans AI-generated content site-wide (https://wallhaven.cc/rules), so
# everything pulled here is human-made / official Rockstar promo art. This script
# only downloads -- it generates nothing.
#
# Driven by the gta-6-wallpaper systemd user timer (every 6h). It ADDS to the
# rotation only; it does not change the live wallpaper. Move through the pool
# with `omarchy theme bg next` or the background switcher.
set -euo pipefail

DEST="$HOME/.config/omarchy/backgrounds/gta-6"
LOG="$HOME/.local/state/omarchy/gta-6-wallpaper.log"
KEEP=15
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36"
API="https://wallhaven.cc/api/v1/search"
QUERIES=("gta iv" "gta 6" "grand theft auto iv" "gta 4 liberty city")

mkdir -p "$DEST" "$(dirname "$LOG")"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

urlenc() {
  local s=$1 o="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9.~_-]) o+=$c ;;
      *) printf -v o '%s%%%02X' "$o" "'$c" ;;
    esac
  done
  printf '%s' "$o"
}

# --- pull one random search page, retrying transient network / 5xx errors ------
search_json=""
for attempt in 1 2 3 4; do
  q=${QUERIES[RANDOM % ${#QUERIES[@]}]}
  url="$API?q=$(urlenc "$q")&categories=100&purity=100&atleast=1920x1080&ratios=16x9&sorting=random"
  if body=$(curl -sS -A "$UA" --max-time 30 "$url" -w $'\n%{http_code}'); then
    code=${body##*$'\n'}
    json=${body%$'\n'*}
    if [[ $code == 200 ]] && jq -e '.data | length > 0' >/dev/null 2>&1 <<<"$json"; then
      search_json=$json
      break
    fi
    log "search attempt $attempt failed (q='$q' http=$code)"
  else
    log "search attempt $attempt failed (q='$q' curl error)"
  fi
  sleep $((attempt * 3))
done

if [[ -z $search_json ]]; then
  log "ERROR: no usable search response after retries; will retry next cycle"
  exit 0
fi

# --- IDs already in the pool -------------------------------------------------
have=""
if compgen -G "$DEST/wh-*.*" >/dev/null; then
  have=$(cd "$DEST" && ls wh-*.* | sed -E 's/^wh-(.*)\.[a-z]+$/\1/' | sort -u)
fi

# --- candidate results we don't already have -------------------------------
mapfile -t cands < <(jq -r --arg have "$have" '
  ($have | split("\n") | map(select(length > 0))) as $seen
  | .data[]
  | select(.file_type == "image/jpeg" or .file_type == "image/png")
  | select(([.id] - $seen) | length > 0)
  | "\(.id)\t\(.path)\t\(.file_type)"
' <<<"$search_json")

if ((${#cands[@]} == 0)); then
  log "no new candidates this cycle (pool already has all of this page's hits)"
  exit 0
fi

line=${cands[RANDOM % ${#cands[@]}]}
IFS=$'\t' read -r id path ftype <<<"$line"
ext=jpg
[[ $ftype == image/png ]] && ext=png
out="$DEST/wh-$id.$ext"

# --- download + validate --------------------------------------------------
tmp=$(mktemp "$DEST/.dl-XXXXXX")
trap 'rm -f "$tmp"' EXIT
if ! curl -sS -A "$UA" --max-time 120 -o "$tmp" "$path"; then
  log "ERROR: download failed for $id ($path)"
  exit 0
fi
if ! identify "$tmp" >/dev/null 2>&1 || (($(stat -c%s "$tmp") < 20000)); then
  log "ERROR: $id downloaded but is not a valid image (size $(stat -c%s "$tmp" 2>/dev/null || echo 0))"
  exit 0
fi
mv "$tmp" "$out"
trap - EXIT
log "added wh-$id.$ext ($(identify -format '%wx%h' "$out" 2>/dev/null)) from Wallhaven; pool=$(compgen -G "$DEST/wh-*.*" | wc -l)"

# --- cap the pool to the newest $KEEP ------------------------------------
mapfile -t old < <(ls -1t "$DEST"/wh-*.* 2>/dev/null | tail -n +$((KEEP + 1)) || true)
for f in "${old[@]:-}"; do
  [[ -n $f ]] || continue
  rm -f "$f" && log "pruned $(basename "$f")"
done

# --- refresh switcher thumbnails if gta-6 is the active theme ----------
if [[ "$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)" == "gta-6" ]]; then
  omarchy theme bg cache >/dev/null 2>&1 || true
fi
