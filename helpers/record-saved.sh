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
