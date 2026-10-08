#!/usr/bin/env bash
# Themes the desktop from the wallpaper, or from a static theme (appearance.theme).
# With no argument the wallpaper comes from the picker's state file.

set -euo pipefail

STATE="$HOME/.local/state/quickshell/wallpaper/current"
THUMBS="$HOME/.cache/quickshell/wallpaper_picker/thumbs"
CACHE="$HOME/.cache/matugen"
LOG="$CACHE/run.log"
SCHEME="serpantinum-KDE"
SCHEME_DIR="$HOME/.local/share/color-schemes"
PLUGIN="org.serpantinum.wallpaper"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# matugen runs every template hook through $SHELL; fish sources config.fish (fastfetch,
# 0.3 s) once per hook.
export SHELL=/bin/bash

# Pin the lock screen to a fixed image. Empty = mirror the desktop wallpaper.
STATIC_LOCK_BACKGROUND=""

mkdir -p "$CACHE"

# Serialise: settings clicks and wallpaper changes both fire this, and two runs
# would interleave writes to the same template outputs.
exec 9>"$CACHE/hook.lock"
flock -w 90 9 || { echo "matugen-hook: timed out waiting for lock" >&2; exit 1; }

wallpaper="${1:-}"
if [[ -z "$wallpaper" && -r "$STATE" ]]; then
    read -r wallpaper < "$STATE"
fi
if [[ -z "$wallpaper" || ! -f "$wallpaper" ]]; then
    echo "matugen-hook: no wallpaper (state: $STATE)" >&2
    exit 1
fi

case "${wallpaper,,}" in
    *.mp4|*.mkv|*.mov|*.webm) is_video=1 ;;
    *)                        is_video=0 ;;
esac

# matugen cannot decode video, so seed from the picker's cached frame.
if (( is_video )); then
    still="$THUMBS/000_${wallpaper##*/}"
    if [[ ! -s "$still" ]]; then
        still="$CACHE/frame.jpg"
        for seek in 00:00:05 00:00:01 00:00:00; do
            ffmpeg -y -ss "$seek" -i "$wallpaper" -vframes 1 -threads 1 \
                   -f image2 -q:v 2 "$still" >/dev/null 2>&1 || true
            [[ -s "$still" ]] && break
        done
    fi
    [[ -s "$still" ]] || { echo "matugen-hook: no frame from $wallpaper" >&2; exit 1; }
else
    still="$wallpaper"
fi

# matugen decodes the still on every call; a 512 px copy is 10x faster and picks the
# same seed. Every call below must use the same file.
seed="$CACHE/seed.jpg"
magick "$still" -resize '512x512>' -quality 90 "$seed.tmp" >/dev/null 2>&1 \
    && mv -f "$seed.tmp" "$seed" || seed="$still"

# --- lock screen ------------------------------------------------------------
# The greeter runs our plugin too; the org.kde.image still stays as its fallback if
# the plugin fails to load.
if [[ -n "$STATIC_LOCK_BACKGROUND" && -f "$STATIC_LOCK_BACKGROUND" ]]; then
    lock_img="$STATIC_LOCK_BACKGROUND"
    rm -f "$CACHE/lockscreen".*
else
    # The cached frame is a JPEG that keeps the video's name.
    if (( is_video )); then lock_ext="jpg"; else lock_ext="${still##*.}"; fi
    lock_img="$CACHE/lockscreen.$lock_ext"
    rm -f "$CACHE/lockscreen".*
    cp -f "$still" "$lock_img"
fi

for key in Image PreviewImage; do
    kwriteconfig6 --file kscreenlockerrc \
        --group Greeter --group Wallpaper --group org.kde.image --group General \
        --key "$key" "$lock_img"
done

# Videos play in the greeter from the original file; stills use the cached copy.
if [[ -z "$STATIC_LOCK_BACKGROUND" ]] && (( is_video )); then
    greeter_img="$wallpaper"
else
    greeter_img="$lock_img"
fi

# The key is 'WallpaperPlugin'; 'WallpaperPluginId' is silently ignored.
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin "$PLUGIN"
kwriteconfig6 --file kscreenlockerrc \
    --group Greeter --group Wallpaper --group "$PLUGIN" --group General \
    --key Image "file://$greeter_img"

# Absent from appletsrc means the plugin default is in use.
fillmode="$(awk -v p="$PLUGIN" '
    /^\[/       { ing = (index($0, p) > 0) }
    ing && /^FillMode=/ { sub(/^FillMode=/, ""); print; exit }
' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)"
if [[ -n "$fillmode" ]]; then
    kwriteconfig6 --file kscreenlockerrc \
        --group Greeter --group Wallpaper --group "$PLUGIN" --group General \
        --key FillMode "$fillmode"
fi

# --- login screen -----------------------------------------------------------
# /etc/plasmalogin.conf points at this fixed path; the plasmalogin user can read ~/.local/share.
LOGIN_IMG="$HOME/.local/share/quickshell/login-wallpaper.jpg"
mkdir -p "${LOGIN_IMG%/*}"
case "${lock_img,,}" in
    *.jpg|*.jpeg) cp -f "$lock_img" "$LOGIN_IMG.tmp" ;;
    *)            magick "$lock_img" -quality 92 "jpg:$LOGIN_IMG.tmp" ;;
esac && chmod 644 "$LOGIN_IMG.tmp" && mv -f "$LOGIN_IMG.tmp" "$LOGIN_IMG" \
    || echo "matugen-hook: login wallpaper not updated" >&2

# --- matugen ----------------------------------------------------------------
if [[ -f "$LOG" && "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]]; then
    tail -n 500 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
fi

get() {   # get <dotted key> <default>, from the shell's settings.json
    python3 - "$1" "$2" <<'PY' 2>/dev/null || echo "$2"
import json, os, sys
cur = json.load(open(os.path.expanduser("~/.config/quickshell/settings.json")))
for p in sys.argv[1].split("."):
    cur = cur[p]
print(cur)
PY
}

theme="$(get appearance.theme matugen)"
echo "===== $(date -Iseconds) $wallpaper (still: $still, theme: $theme) =====" >> "$LOG"

config="$CACHE/config.toml"
if ! python3 "$HERE/render-config.py" "$config" 2>>"$LOG"; then
    echo "matugen-hook: render-config.py failed, see $LOG" | tee -a "$LOG" >&2
    exit 1
fi

rc=0
import="$CACHE/theme-import.json"
stamp="$CACHE/theme.stamp"

# --- static theme -----------------------------------------------------------
# theme-import.py's render data is used verbatim, so an unchanged theme re-renders nothing.
if [[ "$theme" != matugen ]]; then
    if mode="$(python3 "$HERE/theme-import.py" "$theme" "$import" 2>>"$LOG")"; then
        if [[ -n "${1:-}" && -f "$stamp" ]] && cmp -s "$import" "$stamp" && cmp -s "$config" "$stamp.toml"; then
            echo "static theme unchanged, templates kept" >> "$LOG"
            echo "----- exit: 0 -----" >> "$LOG"
            exit 0
        fi
        echo "static theme: $theme ($mode)" >> "$LOG"
        matugen json "$import" -c "$config" \
            --import-json-string "{\"image\":\"$wallpaper\"}" --continue-on-error \
            >> "$LOG" 2>&1 9>&- || rc=$?
        cp -f "$import" "$stamp"
        cp -f "$config" "$stamp.toml"
    else
        echo "matugen-hook: theme '$theme' unusable, falling back to matugen" | tee -a "$LOG" >&2
        theme=matugen
    fi
fi

# --- wallpaper theme --------------------------------------------------------
if [[ "$theme" == matugen ]]; then
    rm -f "$stamp" "$stamp.toml"
    scheme="$(get appearance.schemeType tonal-spot)"
    prefer="$(get appearance.prefer "dominant 1")"
    mode="$(get appearance.mode dark)"
    contrast="$(get appearance.contrast 0)"

    # "dominant N" selects by area (1-based in the UI, 0-based in matugen); anything else
    # is a --prefer rule. One is required: with no TTY matugen picks no seed, yet exits 0.
    case "$prefer" in
        "dominant "[0-9]*) seed_args=(--source-color-index "$(( ${prefer##* } - 1 ))") ;;
        *)                 seed_args=(--prefer "$prefer") ;;
    esac

    # 9>&- : post_hooks outlive us (spicetify starts Spotify) and would hold the lock.
    matugen image "$seed" -c "$config" --type "scheme-$scheme" "${seed_args[@]}" \
        --mode "$mode" --contrast "$contrast" \
        --import-json-string "{\"image\":\"$wallpaper\",\"theme\":{\"name\":\"matugen\",\"static\":false},\"named\":{}}" \
        --continue-on-error >> "$LOG" 2>&1 9>&- || rc=$?
    # Settings' theme grid shows matugen's own colours on its tile even under a static theme.
    cp -f "$HOME/.local/state/quickshell/generated/colors.json" \
          "$HOME/.local/state/quickshell/generated/colors-matugen.json" 2>/dev/null || true

    # matugen's own candidate order for the Settings swatches; its Rust extractor
    # disagrees with the Python one.
    mapfile -t seed_list < <(matugen image "$seed" -c "$config" --show-source-colors --dry-run 2>/dev/null \
                             | grep -E '^#[0-9a-fA-F]{6}$' | head -n 4 || true)
    if (( ${#seed_list[@]} )); then
        python3 -c 'import json, os, sys
p = os.path.expanduser("~/.local/state/quickshell/generated/seeds.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
tmp = p + ".tmp"
json.dump({"seeds": sys.argv[1:]}, open(tmp, "w"))
os.replace(tmp, p)' "${seed_list[@]}" 2>/dev/null || true
    fi
fi

if grep -qiE "^Error:|Failed to get source color" <(tail -n 40 "$LOG"); then
    echo "matugen-hook: matugen reported an error, see $LOG" >&2
    rc=1
fi

# --- apply the KDE colour scheme --------------------------------------------
if [[ $rc -eq 0 && -s "$SCHEME_DIR/$SCHEME.colors" ]]; then
    # Rename a scheme, optionally recolouring both Header groups' background.
    variant() {
        awk -v name="$2" -v bg="${3:-}" '
            /^\[/ { hdr = ($0 == "[Colors:Header]" || $0 == "[Colors:Header][Inactive]") }
            hdr && bg != "" && /^BackgroundNormal=/ { print "BackgroundNormal=" bg; next }
            /^ColorScheme=/ { print "ColorScheme=" name; next }
            /^Name=/        { print "Name=" name; next }
            { print }
        ' "$1"
    }

    # [ColorEffects:Disabled] Color is surface_container_lowest, our darkest.
    darkest="$(awk '/^\[ColorEffects:Disabled\]/{f=1} f&&/^Color=/{sub(/^Color=/,"");print;exit}' \
                "$SCHEME_DIR/$SCHEME.colors")"
    variant "$SCHEME_DIR/$SCHEME.colors" "$SCHEME-darker-titlebar" "$darkest" \
        > "$SCHEME_DIR/$SCHEME-darker-titlebar.colors"

    # Reapply whichever variant is selected, not always the base one.
    active="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)"
    [[ "$active" == "$SCHEME-darker-titlebar" ]] || active="$SCHEME"

    # plasma-apply-colorscheme ignores an already-set scheme, so bounce off a copy.
    variant "$SCHEME_DIR/$active.colors" "$SCHEME-alt" > "$SCHEME_DIR/$SCHEME-alt.colors"
    plasma-apply-colorscheme "$SCHEME-alt" >/dev/null 2>&1 9>&- || true
    plasma-apply-colorscheme "$active"     >>"$LOG" 2>&1 9>&- || true
fi

echo "----- exit: $rc -----" >> "$LOG"
exit "$rc"
