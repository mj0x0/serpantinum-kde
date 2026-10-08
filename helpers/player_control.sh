#!/usr/bin/env bash

# KDE port: serpantinum's caching.sh isn't present — define the runtime dir
# inline (matches helpers/music_info.sh + Caching.qml).
QS_RUN_MUSIC="${XDG_RUNTIME_DIR:-/tmp}/quickshell/music"
mkdir -p "$QS_RUN_MUSIC"

# File to store the latest seek request
SEEK_FILE="$QS_RUN_MUSIC/seek_data"

# Arg mapping
command=$1
arg=$2
len_sec=$3
player_name=$4

# Same rule as music_info.sh, so a keybind drives whatever the TopBar pill shows:
# prefer the player that is actually Playing, ignore media with no real length.
# Never target playerctld - the proxy follows browser activity onto
# plasma-browser-integration, which reports CanGoNext=false and silently no-ops.
if [ -z "$player_name" ]; then
    paused_player=""
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        st=$(timeout 1 playerctl -p "$p" status 2>/dev/null || true)
        len=$(timeout 1 playerctl -p "$p" metadata mpris:length 2>/dev/null || true)
        [[ "$len" =~ ^[0-9]+$ ]] && [ "$len" -gt 0 ] || continue
        if [ "$st" = "Playing" ]; then player_name="$p"; break; fi
        [ "$st" = "Paused" ] && [ -z "$paused_player" ] && paused_player="$p"
    done < <(timeout 1 playerctl --ignore-player=playerctld -l 2>/dev/null || true)
    [ -z "$player_name" ] && player_name="$paused_player"
fi
if [ -z "$player_name" ]; then exit 0; fi

case $command in
    "seek")
        # 1. WRITE: Save the latest target data to a file immediately.
        #    This overwrites any previous pending request.
        echo "$arg $len_sec $player_name" > "$SEEK_FILE"

        # 2. CHECK: Is a worker already running?
        #    We check for a specific marker we create below.
        lock_file="$QS_RUN_MUSIC/seek.lock"
        
        # If the lock file exists, a worker is already waiting to execute.
        # We just exit and let that worker pick up our new value from step 1.
        if [ -f "$lock_file" ]; then
            exit 0
        fi

        # 3. WORKER: Create the lock and run in background
        touch "$lock_file"
        
        (
            # Wait a tiny bit to gather rapid updates (Debounce)
            sleep 0.05
            
            # Read the LATEST value from the file (Step 1)
            read -r final_arg final_len final_player < "$SEEK_FILE"
            
            # Perform the Seek Logic
            if [ -n "$final_len" ] && [ "$final_len" != "0" ]; then
                # Use AWK for math
                target_sec=$(awk -v len="$final_len" -v perc="$final_arg" 'BEGIN { printf "%.2f", (len * perc) / 100 }')
                # Execute
                playerctl -p "$final_player" position "$target_sec"
            fi
            
            # Remove lock so a new batch can start
            rm "$lock_file"
        ) & 
        
        # Exit main script immediately to free up the UI
        exit 0
        ;;
    
    "next")
        playerctl -p "$player_name" next ;;
        
    "prev"|"previous")
        playerctl -p "$player_name" previous ;;
        
    "play-pause")
        playerctl -p "$player_name" play-pause ;;
        
esac
