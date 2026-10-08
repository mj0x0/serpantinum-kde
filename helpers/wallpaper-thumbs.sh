#!/usr/bin/env bash
# Build the picker's thumbnail cache (from serpantinum's qs_manager.sh, see NOTICE).
# Videos get upstream's `000_` prefix. We do NOT delete .webp sources as upstream does.

set -uo pipefail

SRC_DIR="${1:-${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallpaper_picker"
THUMB_DIR="$CACHE/thumbs"
RUN="${XDG_RUNTIME_DIR:-/tmp}/quickshell/wallpaper_picker"
PREP_LOCK="$RUN/wallpaper_prep.lock"
MANIFEST="$THUMB_DIR/.manifest"
SOURCE_FILE="$THUMB_DIR/.source_dir"
SIZE_FILE="$THUMB_DIR/.thumb_height"
THUMB_H=720

export MAGICK_THREAD_LIMIT=1
mkdir -p "$THUMB_DIR" "$RUN"

# One prep at a time; a stale lock from a dead process is ignored.
if [ -f "$PREP_LOCK" ] && kill -0 "$(cat "$PREP_LOCK" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PREP_LOCK"
trap 'rm -f "$PREP_LOCK" "${SRC_LIST:-}"' EXIT

build_manifest() {
    find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.*' \
        -printf "%f\n" | sort > "$MANIFEST"
}

# Pointing the picker at a different folder invalidates every thumbnail.
if [ -f "$SOURCE_FILE" ]; then
    read -r CACHED_SRC < "$SOURCE_FILE"
    if [ "$CACHED_SRC" != "$SRC_DIR" ]; then
        find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.*' -delete
        echo "$SRC_DIR" > "$SOURCE_FILE"
        : > "$MANIFEST"
    fi
else
    echo "$SRC_DIR" > "$SOURCE_FILE"
    : > "$MANIFEST"
fi

# A taller cache only invalidates image thumbs; video frames are stored at source size.
if [ "$(cat "$SIZE_FILE" 2>/dev/null)" != "$THUMB_H" ]; then
    find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.*' ! -name '000_*' -delete
    echo "$THUMB_H" > "$SIZE_FILE"
    [ -f "$MANIFEST" ] && sed -i '/^000_/!d' "$MANIFEST"
fi

[ -f "$MANIFEST" ] || build_manifest

SRC_LIST=$(mktemp)
find "$SRC_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \
       -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mkv" \
       -o -iname "*.mov" -o -iname "*.webm" \) \
    -printf "%f\n" | sort > "$SRC_LIST"

# Drop thumbnails whose source is gone.
comm -23 <(sed 's/^000_//' "$MANIFEST" | sort) "$SRC_LIST" | while read -r orphan; do
    [ -n "$orphan" ] || continue
    rm -f "$THUMB_DIR/$orphan" "$THUMB_DIR/000_$orphan"
    sed -i "/^${orphan}$/d;/^000_${orphan}$/d" "$MANIFEST" 2>/dev/null
done

made=0
while IFS= read -r filename; do
    [ -n "$filename" ] || continue
    img="$SRC_DIR/$filename"
    [ -f "$img" ] || continue
    ext="${filename##*.}"

    if [[ "${ext,,}" =~ ^(mp4|mkv|mov|webm)$ ]]; then
        thumb="$THUMB_DIR/000_$filename"
        [ -f "$THUMB_DIR/$filename" ] && rm -f "$THUMB_DIR/$filename"
        if [ ! -f "$thumb" ]; then
            # 5s in, then fall back — some clips are black or short at that mark.
            for seek in 00:00:05 00:00:01 00:00:00; do
                ffmpeg -y -ss "$seek" -i "$img" -vframes 1 -threads 1 \
                       -f image2 -q:v 2 "$thumb" >/dev/null 2>&1
                [ -s "$thumb" ] && break
            done
            # Stamp with the SOURCE mtime so the picker can sort by date added, not date built.
            [ -s "$thumb" ] && { touch -r "$img" "$thumb"; echo "000_$filename" >> "$MANIFEST"; made=$((made+1)); }
        fi
    else
        thumb="$THUMB_DIR/$filename"
        if [ ! -f "$thumb" ]; then
            if magick "$img" -resize "x$THUMB_H" -quality 80 "$thumb" 2>/dev/null; then
                touch -r "$img" "$thumb"          # see note above
                echo "$filename" >> "$MANIFEST"
                made=$((made+1))
            fi
        fi
    fi
done < <(comm -23 "$SRC_LIST" <(sed 's/^000_//' "$MANIFEST" | sort))

# Re-stamp anything whose thumbnail predates this change (or whose source was
# touched since). Cheap: a stat and, rarely, a touch.
restamped=0
for thumb in "$THUMB_DIR"/*; do
    [ -f "$thumb" ] || continue
    tname="$(basename "$thumb")"
    case "$tname" in .*) continue ;; esac
    src="$SRC_DIR/${tname#000_}"
    [ -f "$src" ] || continue
    if [ "$(stat -c %Y "$thumb")" != "$(stat -c %Y "$src")" ]; then
        touch -r "$src" "$thumb"
        restamped=$((restamped+1))
    fi
done

echo "thumbs: $(find "$THUMB_DIR" -maxdepth 1 -type f ! -name '.*' | wc -l) total, $made new, $restamped restamped, from $SRC_DIR"
