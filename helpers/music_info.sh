#!/usr/bin/env bash

# --- Caching ---
QS_RUN_MUSIC="${XDG_RUNTIME_DIR:-/tmp}/quickshell/music"
QS_STATE_MUSIC="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/music"
mkdir -p "$QS_RUN_MUSIC" "$QS_STATE_MUSIC"

TMP_DIR="$QS_RUN_MUSIC/covers"
STATE_FILE="$QS_STATE_MUSIC/last_state.json"

mkdir -p "$TMP_DIR"
PLACEHOLDER="$TMP_DIR/placeholder_blank.png"

PT_TIMEOUT=1.5

# --- 1. ENSURE PLACEHOLDER EXISTS ---
if [ ! -f "$PLACEHOLDER" ]; then
    convert -size 500x500 xc:"#313244" "$PLACEHOLDER"
fi

# --- Dynamic player selection --- never hard-code names: first Playing player with
# length > 0, else the first Paused one.
selected_player=""
selected_status=""
paused_player=""
paused_status=""

while IFS= read -r p; do
    [ -z "$p" ] && continue

    st=$(timeout "$PT_TIMEOUT" playerctl -p "$p" status 2>/dev/null || true)
    len=$(timeout "$PT_TIMEOUT" playerctl -p "$p" metadata mpris:length 2>/dev/null || true)

    # Ignore YouTube hover / any media without a real length.
    if [[ "$len" =~ ^[0-9]+$ ]] && [ "$len" -gt 0 ]; then
        valid=1
    else
        valid=0
    fi

    if [ "$st" = "Playing" ] && [ "$valid" -eq 1 ]; then
        selected_player="$p"
        selected_status="Playing"
        break
    fi

    if [ "$st" = "Paused" ] && [ "$valid" -eq 1 ] && [ -z "$paused_player" ]; then
        paused_player="$p"
        paused_status="Paused"
    fi
done < <(timeout "$PT_TIMEOUT" playerctl -l 2>/dev/null || true)

# Prefer Playing, but fall back to Paused.
if [ -z "$selected_player" ] && [ -n "$paused_player" ]; then
    selected_player="$paused_player"
    selected_status="$paused_status"
fi

# --- 3. STOPPED FALLBACK ---
if [ -z "$selected_player" ]; then
    if [ -f "$STATE_FILE" ]; then
        last_pos_sec=$(jq -r '.pos_sec' "$STATE_FILE")
        last_len_sec=$(jq -r '.len_sec' "$STATE_FILE")
    else
        last_pos_sec=0
        last_len_sec=0
    fi

    if [ -z "$last_pos_sec" ] || [ "$last_pos_sec" = "null" ]; then last_pos_sec=0; fi
    if [ -z "$last_len_sec" ] || [ "$last_len_sec" = "null" ] || [ "$last_len_sec" -eq 0 ]; then last_len_sec=1; fi

    last_percent=$((last_pos_sec * 100 / last_len_sec))
    last_pos_str=$(printf "%02d:%02d" $((last_pos_sec / 60)) $((last_pos_sec % 60)))
    last_len_str=$(printf "%02d:%02d" $((last_len_sec / 60)) $((last_len_sec % 60)))
    last_time_str="${last_pos_str} / ${last_len_str}"

    jq -n -c \
        --arg placeholder "$PLACEHOLDER" \
        --arg pos_str "$last_pos_str" \
        --arg len_str "$last_len_str" \
        --arg time_str "$last_time_str" \
        --arg percent "$last_percent" \
        '{
            title: "Not Playing",
            artist: "",
            status: "Stopped",
            percent: $percent,
            lengthStr: $len_str,
            positionStr: $pos_str,
            timeStr: $time_str,
            source: "Offline",
            playerName: "",
            blur: $placeholder,
            grad: "linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)",
            textColor: "#cdd6f4",
            deviceIcon: "󰓃",
            deviceName: "Speaker",
            artUrl: $placeholder
        }'
    exit 0
fi

# --- 4. METADATA / ART ---
pc() {
    timeout "$PT_TIMEOUT" playerctl -p "$selected_player" "$@"
}

STATUS="$selected_status"

rawUrl=$(pc metadata mpris:artUrl 2>/dev/null || true)
title=$(pc metadata xesam:title 2>/dev/null || true)
artist=$(pc metadata xesam:artist 2>/dev/null || true)
album=$(pc metadata xesam:album 2>/dev/null || true)
len_micro=$(pc metadata mpris:length 2>/dev/null || true)

# Safety check in case metadata changed after selection.
if ! [[ "$len_micro" =~ ^[0-9]+$ ]] || [ "$len_micro" -eq 0 ]; then
    exec "$0"
fi

if [ -n "$rawUrl" ]; then
    trackHash=$(echo "$rawUrl" | md5sum | cut -d" " -f1)
else
    idStr="${title:-unknown}-${artist:-unknown}"
    trackHash=$(echo "$idStr" | md5sum | cut -d" " -f1)
fi

finalArt="$TMP_DIR/${trackHash}_art.jpg"
blurPath="$TMP_DIR/${trackHash}_blur.png"
colorPath="$TMP_DIR/${trackHash}_grad.txt"
textPath="$TMP_DIR/${trackHash}_text.txt"
lockFile="$TMP_DIR/${trackHash}.lock"

displayArt="$PLACEHOLDER"
displayBlur="$PLACEHOLDER"
displayGrad="linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)"
displayText="#cdd6f4"

if [ -f "$finalArt" ] && [ -s "$finalArt" ]; then
    displayArt="$finalArt"
    [ -f "$blurPath" ] && displayBlur="$blurPath"
    [ -f "$colorPath" ] && displayGrad=$(cat "$colorPath")
    [ -f "$textPath" ] && displayText=$(cat "$textPath")
else
    if [ ! -f "$lockFile" ] && [ -n "$rawUrl" ]; then
        touch "$lockFile"

        (
            tempArt="$TMP_DIR/${trackHash}_temp_art.jpg"
            tempBlur="$TMP_DIR/${trackHash}_temp_blur.png"

            if [[ "$rawUrl" == http* ]]; then
                curl -s -L --max-time 10 -o "$tempArt" "$rawUrl"
            else
                cleanPath=$(echo "$rawUrl" | sed 's/file:\/\///g')
                if [ -f "$cleanPath" ]; then
                    cp "$cleanPath" "$tempArt"
                else
                    cp "$PLACEHOLDER" "$tempArt"
                fi
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

                c1=${color_array[0]:-#cba6f7}
                c2=${color_array[1]:-$c1}
                c3=${color_array[2]:-$c1}

                echo "linear-gradient(45deg, $c1, $c2, $c3, $c1)" > "$colorPath"

                opp_raw=$(convert xc:"$c1" -alpha off -negate -depth 8 -format "%[hex:u]" info: 2>/dev/null |
                    grep -E -o '[0-9A-Fa-f]{6}' | head -n 1)
                if [ -n "$opp_raw" ]; then
                    echo "#$opp_raw" > "$textPath"
                else
                    echo "#cdd6f4" > "$textPath"
                fi
            fi

            mv "$tempBlur" "$blurPath"
            mv "$tempArt" "$finalArt"

            rm -f "$lockFile"
            (cd "$TMP_DIR" && ls -1t | tail -n +21 | xargs -r rm 2>/dev/null)
        ) </dev/null >/dev/null 2>&1 &
    fi
fi

# --- 5. TIMING ---
len_sec=$((len_micro / 1000000))
len_str=$(printf "%02d:%02d" $((len_sec / 60)) $((len_sec % 60)))

if [ "$STATUS" = "Playing" ]; then
    pos_micro=$(pc position --format '{{ position }}' 2>/dev/null || true)

    # Fallback if the player doesn't support `position`.
    if ! [[ "$pos_micro" =~ ^[0-9]+$ ]]; then
        pos_micro=$(pc metadata --format '{{position}}' 2>/dev/null || true)
    fi

    if ! [[ "$pos_micro" =~ ^[0-9]+$ ]]; then
        pos_micro=0
    fi

    pos_sec=$((pos_micro / 1000000))
    # Lyrics need the fraction; every other field keeps whole seconds.
    pos_exact="$pos_sec.$(printf '%03d' $(( (pos_micro % 1000000) / 1000 )))"

    jq -n -c \
        --argjson pos_sec "$pos_sec" \
        --argjson len_sec "$len_sec" \
        '{pos_sec: $pos_sec, len_sec: $len_sec}' \
        > "$STATE_FILE"
else
    pos_sec=0
    if [ -f "$STATE_FILE" ]; then
        saved_pos=$(jq -r '.pos_sec' "$STATE_FILE")
        saved_len=$(jq -r '.len_sec' "$STATE_FILE")
        if [ "$saved_len" = "$len_sec" ] && [ -n "$saved_pos" ] && [ "$saved_pos" != "null" ]; then
            pos_sec=$saved_pos
        fi
    fi
    pos_exact=$pos_sec
fi

percent=$((pos_sec * 100 / len_sec))
pos_str=$(printf "%02d:%02d" $((pos_sec / 60)) $((pos_sec % 60)))
time_str="${pos_str} / ${len_str}"

# --- 6. DEVICE INFO ---
player_raw="$selected_player"
player_nice="${player_raw^}"

dev_icon="󰓃"
dev_name="Speaker"
node_name=$(timeout 0.5 wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node\.name/ {print $2}')
node_desc=$(timeout 0.5 wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node\.description/ {print $2}')

if [[ "$node_name" == *"bluez"* ]]; then
    dev_icon="󰂯"
    [ -n "$node_desc" ] && dev_name="$node_desc" || dev_name="Bluetooth"
elif [[ "$node_name" == *"usb"* ]]; then
    dev_icon="󰓃"
    dev_name="USB Audio"
elif [[ "$node_name" == *"pci"* ]]; then
    dev_icon="󰓃"
    dev_name="System"
elif [ -n "$node_desc" ]; then
    dev_name="$node_desc"
fi

# --- 7. JSON OUTPUT ---
jq -n -c \
    --arg title "$title" \
    --arg artist "$artist" \
    --arg album "$album" \
    --arg status "$STATUS" \
    --arg len "$len_sec" \
    --arg pos "$pos_exact" \
    --arg len_str "$len_str" \
    --arg pos_str "$pos_str" \
    --arg time_str "$time_str" \
    --arg percent "$percent" \
    --arg source "$player_nice" \
    --arg pname "$player_raw" \
    --arg blur "$displayBlur" \
    --arg grad "$displayGrad" \
    --arg txtColor "$displayText" \
    --arg devIcon "$dev_icon" \
    --arg devName "$dev_name" \
    --arg finalArt "$displayArt" \
    '{
        title: $title,
        artist: $artist,
        album: $album,
        status: $status,
        length: $len,
        position: $pos,
        lengthStr: $len_str,
        positionStr: $pos_str,
        timeStr: $time_str,
        percent: $percent,
        source: $source,
        playerName: $pname,
        blur: $blur,
        grad: $grad,
        textColor: $txtColor,
        deviceIcon: $devIcon,
        deviceName: $devName,
        artUrl: $finalArt
    }'