#!/usr/bin/env bash
# Screenshot back end for modules/screenshot (from serpantinum's screenshot.sh, see NOTICE).
# spectacle captures, magick crops, swappy annotates. The overlay freezes the screen once
# and hands that PNG back here with --freeze, so the saved file is the pixels it showed.
#   --geometry "X,Y WxH"  region in capture pixels   --freeze FILE  crop this instead of capturing
#   --full  whole current monitor   --edit  annotate first   --scan-qr  print QR codes and exit

set -uo pipefail

EDIT=false
FULL=false
SCAN_QR=false
GEOMETRY=""
FREEZE=""

usage() {
    echo "usage: screenshot.sh [--full] [--geometry \"X,Y WxH\"] [--freeze FILE] [--edit] [--scan-qr]" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --edit) EDIT=true; shift ;;
        --full) FULL=true; shift ;;
        --scan-qr) SCAN_QR=true; shift ;;
        --geometry) [ "$#" -ge 2 ] || usage; GEOMETRY="$2"; shift 2 ;;
        --freeze) [ "$#" -ge 2 ] || usage; FREEZE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

# --full is the whole monitor, whatever else was asked for.
if [ "$FULL" = true ]; then
    GEOMETRY=""
    FREEZE=""
fi

HELPER_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
QR_PARSER="$HELPER_DIR/screenshot-qr.py"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell/screenshot"
# xdg-user-dir answers $HOME when PICTURES is unset, which is not where screenshots go.
PICTURES="$(xdg-user-dir PICTURES 2>/dev/null)"
[ -n "$PICTURES" ] && [ "$PICTURES" != "$HOME" ] || PICTURES="$HOME/Pictures"
SAVE_DIR="$PICTURES/Screenshots"

# The overlay hands us its freeze and forgets it, so the capture path owns that file.
# A QR scan is the exception: the overlay stays up and keeps showing it.
drop_freeze() {
    [ "$SCAN_QR" = true ] && return 0
    [ -n "$FREEZE" ] && rm -f "$FREEZE"
    return 0
}

# The overlay has already closed by the time we run, so stderr reaches nobody.
fail() {
    local why="${1:-The capture did not finish.}"
    echo "screenshot: $why" >&2
    drop_freeze
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -a "Screenshot" "Screenshot failed" "$why"
    fi
    exit 1
}

need() {
    local missing=() cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    [ "${#missing[@]}" -eq 0 ] && return
    fail "Cannot start. Please install: ${missing[*]}"
}

DEPS=()
[ -z "$FREEZE" ] && DEPS+=(spectacle)
[ -n "$GEOMETRY" ] && DEPS+=(magick)
[ "$SCAN_QR" = true ] && DEPS+=(zbarimg python3)
[ "$EDIT" = true ] && DEPS+=(swappy)
[ "${#DEPS[@]}" -gt 0 ] && need "${DEPS[@]}"

mkdir -p "$RUN_DIR" || fail "Cannot create $RUN_DIR"
CAPTURE=""
REGION="$RUN_DIR/region_$$.png"
QR_RAW="$RUN_DIR/qr_$$.txt"
trap 'rm -f "$REGION" "$CAPTURE" "$QR_RAW"' EXIT

SRC="$FREEZE"
if [ -z "$SRC" ]; then
    CAPTURE="$RUN_DIR/capture_$$.png"
    # spectacle exits 0 without writing the file when another instance is already live.
    spectacle -b -n -m -o "$CAPTURE" || fail "spectacle could not capture the screen."
    SRC="$CAPTURE"
fi
[ -s "$SRC" ] || fail "The capture is missing or empty."

if [ -n "$GEOMETRY" ]; then
    # "X,Y WxH" -> magick's "WxH+X+Y"; magick exits 0 on a zero or off-image crop.
    POS="${GEOMETRY%% *}"; SIZE="${GEOMETRY##* }"
    GX="${POS%%,*}"; GY="${POS##*,}"; GW="${SIZE%%x*}"; GH="${SIZE##*x}"
    for N in "$GX" "$GY" "$GW" "$GH"; do
        case "$N" in ''|*[!0-9]*) fail "Bad selection \"$GEOMETRY\"." ;; esac
    done
    { [ "$GW" -gt 0 ] && [ "$GH" -gt 0 ]; } || fail "The selection has no area."
    GOT="$(magick "$SRC" -crop "${GW}x${GH}+${GX}+${GY}" +repage -write "$REGION" -format '%wx%h' info:)" \
        || fail "Could not crop the selection."
    # A crop that misses the image altogether is still exit 0, with a 1x1 placeholder.
    [ "$GOT" = 1x1 ] && [ "${GW}x${GH}" != 1x1 ] && fail "The selection is outside the capture."
else
    cp -- "$SRC" "$REGION" || fail "Could not copy the capture."
fi

if [ "$SCAN_QR" = true ]; then
    # Two passes: --xml carries the geometry, --raw the undamaged bytes. See the parser.
    zbarimg --raw -q "$REGION" > "$QR_RAW" 2>/dev/null
    zbarimg --xml -q "$REGION" 2>/dev/null | python3 -I "$QR_PARSER" "$QR_RAW"
    exit 0
fi

drop_freeze

mkdir -p "$SAVE_DIR" || fail "Cannot create $SAVE_DIR"
STAMP="$(date +'%Y-%m-%d-%H%M%S')"
FINAL="$SAVE_DIR/Screenshot_$STAMP.png"

if [ "$EDIT" = true ]; then
    # swappy writes -o on exit even when the user closed without saving, hence the -s test.
    swappy -f "$REGION" -o "$FINAL"
    if [ ! -s "$FINAL" ]; then   # closed without saving, nothing to report
        rm -f "$FINAL"
        exit 0
    fi
else
    cp -- "$REGION" "$FINAL" || fail "Cannot write $FINAL"
    [ -s "$FINAL" ] || fail "Nothing was saved to $FINAL"
fi

command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < "$FINAL"
# The notification card opens the folder itself; notify-send -A would block us until the
# user clears the notification centre.
notify-send -a "Screenshot" -i "$FINAL" -h "string:image-path:$FINAL" \
    "Screenshot saved" "File: Screenshot_$STAMP.png
Folder: $SAVE_DIR"
exit 0
