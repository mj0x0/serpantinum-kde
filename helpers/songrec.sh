#!/usr/bin/env bash
# Recognize the song playing on the default output; notify with YouTube / copy actions.
set -u
icon=re.fossplant.songrec
clip=$(mktemp --suffix=.wav)
trap 'rm -f "$clip"' EXIT

notify-send -a SongRec -i "$icon" -u low "SongRec" "Listening…"
# songrec's own capture never sends a request here; record the output monitor (as cava does) instead.
timeout 12 parecord -d "$(pactl get-default-sink).monitor" --file-format=wav "$clip"
json=$(timeout 30 songrec recognize --json "$clip" 2>/dev/null)
title=$(jq -r '.track.title // empty' <<<"$json" 2>/dev/null)
artist=$(jq -r '.track.subtitle // empty' <<<"$json" 2>/dev/null)

if [ -z "$title" ]; then
    notify-send -a SongRec -i "$icon" "SongRec" "No song recognized"
    exit 0
fi

song="$artist - $title"
action=$(notify-send -a SongRec -i "$icon" -A youtube="Open in YouTube" -A copy="Copy Song Name/Artist" "$title" "$artist")
case "$action" in
    youtube) xdg-open "https://www.youtube.com/results?search_query=$(jq -rn --arg q "$song" '$q|@uri')" ;;
    copy)    wl-copy "$song" ;;
esac
