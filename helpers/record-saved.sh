#!/usr/bin/env bash
# gpu-screen-recorder -sc hook: record-saved.sh FILE TYPE. Thumbnail, drop current.json, notify.
set -uo pipefail

FILE="${1:-}"
[ -n "$FILE" ] || exit 0
RUN_DIR="${RECORD_RUN_DIR:-${XDG_RUNTIME_DIR:-/tmp}/quickshell/record}"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/record"
NAME="$(basename -- "$FILE")"
DIR="$(dirname -- "$FILE")"

rm -f "$RUN_DIR/current.json"

# A PQ file without peak metadata makes players assume 10000 nits and crush the picture;
# stamp the measured peak (keyframes only, so a long clip costs a second) into the mkv header.
stamp_hdr() {
    case "$FILE" in *.mkv|*.MKV) ;; *) return 0 ;; esac
    for c in mkvpropedit ffprobe ffmpeg python3; do command -v "$c" >/dev/null 2>&1 || return 0; done
    [ "$(ffprobe -v error -select_streams v:0 -show_entries stream=color_transfer -of default=nw=1:nk=1 "$FILE")" = smpte2084 ] || return 0
    local range peaks
    range="$(ffprobe -v error -select_streams v:0 -show_entries stream=color_range -of default=nw=1:nk=1 "$FILE")"
    peaks="$(ffmpeg -v error -skip_frame nokey -i "$FILE" \
                -vf 'format=yuv420p10le,signalstats,metadata=print:file=/dev/stdout' \
                -fps_mode passthrough -f null /dev/null 2>/dev/null \
             | python3 -c '
import sys, math
full = sys.argv[1] == "pc"
def nits(code):
    e = code / 1023.0 if full else max(0.0, (code - 64) / 876.0)
    m1, m2 = 2610 / 16384, 2523 / 4096 * 128
    c1, c2, c3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32
    e = min(max(e, 0.0), 1.0) ** (1 / m2)
    return 10000 * max(0.0, (e - c1) / (c2 - c3 * e)) ** (1 / m1)
mx, av = [], []
for line in sys.stdin:
    k, _, v = line.strip().partition("=")
    if k.endswith("YMAX"): mx.append(float(v))
    elif k.endswith("YAVG"): av.append(float(v))
if mx and av:
    print(math.ceil(max(map(nits, mx))), math.ceil(max(map(nits, av))))
' "$range")" || return 0
    [ -n "$peaks" ] || return 0
    set -- $peaks
    mkvpropedit "$FILE" --edit track:v1 \
        --set max-content-light="$1" --set max-frame-light="$2" \
        --set max-luminance="$1" --set min-luminance=0.0001 \
        --set chromaticity-coordinates-red-x=0.708 --set chromaticity-coordinates-red-y=0.292 \
        --set chromaticity-coordinates-green-x=0.170 --set chromaticity-coordinates-green-y=0.797 \
        --set chromaticity-coordinates-blue-x=0.131 --set chromaticity-coordinates-blue-y=0.046 \
        --set white-coordinates-x=0.3127 --set white-coordinates-y=0.3290 >/dev/null 2>&1
}
stamp_hdr

ICON="video-x-generic"
if command -v ffmpeg >/dev/null 2>&1 && mkdir -p "$THUMB_DIR" 2>/dev/null; then
    THUMB="$THUMB_DIR/${NAME%.*}.png"
    ffmpeg -y -v error -ss 1 -i "$FILE" -frames:v 1 -vf scale=480:-1 "$THUMB" >/dev/null 2>&1 \
        && [ -s "$THUMB" ] && ICON="$THUMB"
fi

notify-send -a "Screen Recorder" -i "$ICON" -h "string:image-path:$ICON" \
    "Recording saved" "File: $NAME
Folder: $DIR"
exit 0
