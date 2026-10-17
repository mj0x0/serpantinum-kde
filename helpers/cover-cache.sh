#!/usr/bin/env bash
# cover-cache.sh <artUrl> <title> <artist>: fetch one cover into the session cache and print its path.
# Same files and md5(url + newline) keys as music_info.sh: the lock screens and the music popup read them.
QS_RUN_MUSIC="${XDG_RUNTIME_DIR:-/tmp}/quickshell/music"
TMP_DIR="$QS_RUN_MUSIC/covers"
mkdir -p "$TMP_DIR"
PLACEHOLDER="$TMP_DIR/placeholder_blank.png"
[ -f "$PLACEHOLDER" ] || convert -size 500x500 xc:"#313244" "$PLACEHOLDER"

rawUrl="$1"; title="$2"; artist="$3"
if [ -n "$rawUrl" ]; then
    trackHash=$(echo "$rawUrl" | md5sum | cut -d" " -f1)
else
    trackHash=$(echo "${title:-unknown}-${artist:-unknown}" | md5sum | cut -d" " -f1)
fi

finalArt="$TMP_DIR/${trackHash}_art.jpg"
blurPath="$TMP_DIR/${trackHash}_blur.png"
colorPath="$TMP_DIR/${trackHash}_grad.txt"
textPath="$TMP_DIR/${trackHash}_text.txt"
lockFile="$TMP_DIR/${trackHash}.lock"

if [ -s "$finalArt" ]; then printf '%s' "$finalArt"; exit 0; fi
if [ -f "$lockFile" ] || [ -z "$rawUrl" ]; then printf '%s' "$PLACEHOLDER"; exit 0; fi
touch "$lockFile"
trap 'rm -f "$lockFile"' EXIT

tempArt="$TMP_DIR/${trackHash}_temp_art.jpg"
tempBlur="$TMP_DIR/${trackHash}_temp_blur.png"
if [[ "$rawUrl" == http* ]]; then
    curl -s -L --max-time 10 -o "$tempArt" "$rawUrl"
else
    cleanPath="${rawUrl#file://}"
    [ -f "$cleanPath" ] && cp "$cleanPath" "$tempArt" || cp "$PLACEHOLDER" "$tempArt"
fi
[ -s "$tempArt" ] || cp "$PLACEHOLDER" "$tempArt"

isPlaceholder=$(convert "$tempArt" -format "%[hex:u.p{0,0}]" info: 2>/dev/null | cut -c1-6)
if [[ "$isPlaceholder" == "313244" ]] || [[ -z "$isPlaceholder" ]]; then
    cp "$tempArt" "$tempBlur"
else
    convert "$tempArt" -blur 0x20 -brightness-contrast -30x-10 "$tempBlur" 2>/dev/null
    colors=$(convert "$tempArt" -resize 50x50 -alpha off +dither -quantize RGB -colors 3 -depth 8 -format "%c" histogram:info: 2>/dev/null |
        grep -E -o '#[0-9A-Fa-f]{6}' | head -n 3 | tr '\n' ' ')
    read -r -a color_array <<< "$colors"
    c1=${color_array[0]:-#cba6f7}; c2=${color_array[1]:-$c1}; c3=${color_array[2]:-$c1}
    echo "linear-gradient(45deg, $c1, $c2, $c3, $c1)" > "$colorPath"
    opp_raw=$(convert xc:"$c1" -alpha off -negate -depth 8 -format "%[hex:u]" info: 2>/dev/null | grep -E -o '[0-9A-Fa-f]{6}' | head -n 1)
    if [ -n "$opp_raw" ]; then echo "#$opp_raw" > "$textPath"; else echo "#cdd6f4" > "$textPath"; fi
fi
mv "$tempBlur" "$blurPath"
mv "$tempArt" "$finalArt"
(cd "$TMP_DIR" && ls -1t | tail -n +21 | xargs -r rm 2>/dev/null)
printf '%s' "$finalArt"
