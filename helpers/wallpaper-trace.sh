#!/usr/bin/env bash
# Trace one wallpaper change end to end: picker -> plasmashell -> KMY -> matugen.
# Read-only. Ctrl-C to stop.
set -uo pipefail

STATE=~/.local/state/quickshell/wallpaper/current
SHOT=/tmp/kde-material-you-colors-desktop-screenshot-$USER.png
FED=/tmp/matugen-hook-wallpaper-$USER.png
GEN=~/.local/state/quickshell/generated/colors.json
REPO="$(cd -- "$(dirname -- "$0")/.." && pwd)"

dom() {  # dominant colour of an image, or a dash
    [ -s "$1" ] || { echo "-"; return; }
    magick "$1" -resize 60x -colors 3 -unique-colors txt: 2>/dev/null \
      | tail -1 | grep -oE '#[0-9A-Fa-f]{6}' | head -1 || echo "-"
}

prev=""
echo "watching. change the wallpaper now."
echo

while true; do
    now=$(cat "$STATE" 2>/dev/null)
    if [ "$now" != "$prev" ] && [ -n "$now" ]; then
        echo "=== $(date +%H:%M:%S)  picker wrote:"
        echo "    $now"
        prev="$now"

        # give KMY (1s poll) + the hook time to run
        for i in 1 2 3 4 5 6 7 8 9 10 12 15 20 25 30; do
            sleep 1
            plasma=$(cd "$REPO" && python3 helpers/set-wallpaper.py --current 2>/dev/null | awk -F'\t' '{print $2" "$NF}')
            gen=$(python3 -c "
import json,os
try: print(json.load(open(os.path.expanduser('$GEN')))['md3']['primary'])
except Exception: print('-')" 2>/dev/null)
            printf "    +%-3ss plasma=%-70s shot=%-8s fed=%-8s matugen=%s\n" \
                   "$i" "$plasma" "$(dom "$SHOT")" "$(dom "$FED")" "$gen"
        done
        echo
    fi
    sleep 1
done
