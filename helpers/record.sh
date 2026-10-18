#!/usr/bin/env bash
# Recorder back end for services/record: the only thing that launches or talks to
# gpu-screen-recorder. Every reply is one line of JSON.
#   start --dir DIR --output NAME [--region WxH+X+Y] --hdr yes|no --audio off|system|system+mic
#         --fps N --quality Q --codec C --hdr-codec C --container EXT --hdr-container EXT
#         --cursor yes|no --fm vfr|cfr --cr limited|full
#   status | stop | pause        every command takes --run-dir DIR

set -uo pipefail

RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell/record"
HELPER_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
SAVED_HOOK="$HELPER_DIR/record-saved.sh"

SAVE_DIR=""; OUTPUT=""; REGION=""; HDR=no; AUDIO=system; FPS=60; QUALITY=very_high
CODEC=h264; HDR_CODEC=hevc_hdr; CONTAINER=mp4; HDR_CONTAINER=mkv; CURSOR=yes; FM=vfr; CR=limited

usage() {
    echo "usage: record.sh start|status|stop|pause [--run-dir DIR] [start options]" >&2
    exit 1
}

# json s:key=text j:key=<json literal> ...  -> one line; python quotes, never the shell.
json() {
    python3 -c '
import json, sys
o = {}
for a in sys.argv[1:]:
    k, _, v = a[2:].partition("=")
    o[k] = json.loads(v) if a[0] == "j" else v
print(json.dumps(o))' "$@"
}

fail() { json j:ok=false s:error="$1"; exit 1; }

need() {
    local missing=() cmd
    for cmd in "$@"; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
    [ "${#missing[@]}" -eq 0 ] || fail "Cannot start. Please install: ${missing[*]}"
}

[ "$#" -ge 1 ] || usage
CMD="$1"; shift

while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] || usage
    case "$1" in
        --run-dir) RUN_DIR="$2" ;;
        --dir) SAVE_DIR="$2" ;;
        --output) OUTPUT="$2" ;;
        --region) REGION="$2" ;;
        --hdr) HDR="$2" ;;
        --audio) AUDIO="$2" ;;
        --fps) FPS="$2" ;;
        --quality) QUALITY="$2" ;;
        --codec) CODEC="$2" ;;
        --hdr-codec) HDR_CODEC="$2" ;;
        --container) CONTAINER="$2" ;;
        --hdr-container) HDR_CONTAINER="$2" ;;
        --cursor) CURSOR="$2" ;;
        --fm) FM="$2" ;;
        --cr) CR="$2" ;;
        *) usage ;;
    esac
    shift 2
done

SOCK="$RUN_DIR/gsr.sock"
STATE="$RUN_DIR/current.json"
LOG="$RUN_DIR/gsr.log"

running() { [ -S "$SOCK" ] && timeout 2 gsr-cli -ipc "$SOCK" status >/dev/null 2>&1; }

log_tail() {
    local off; off="$(jq -r '.logOffset // 0' "$STATE" 2>/dev/null)"
    case "$off" in ''|*[!0-9]*) off=0 ;; esac
    tail -c +"$((off + 1))" "$LOG" 2>/dev/null
}
# GSR drops a toggle sent before it has consumed the previous one; its log is the only truthful pause state.
pause_lines() { log_tail | grep -E '^gsr info: (Paused|Unpaused)$'; }
pause_state() { [ "$(pause_lines | tail -n 1)" = "gsr info: Paused" ] && echo true || echo false; }

case "$CMD" in
start)
    need gpu-screen-recorder gsr-cli python3
    mkdir -p "$RUN_DIR" || fail "Cannot create $RUN_DIR"
    running && fail "already recording"
    [ -n "$SAVE_DIR" ] || fail "--dir is required"
    [ -n "$OUTPUT$REGION" ] || fail "--output or --region is required"
    case "$FPS" in ''|*[!0-9]*|0) fail "Bad fps \"$FPS\"" ;; esac
    case "$HDR" in yes|no) ;; *) fail "--hdr must be yes or no" ;; esac
    case "$CURSOR" in yes|no) ;; *) fail "--cursor must be yes or no" ;; esac
    case "$AUDIO" in off|system|system+mic) ;; *) fail "Bad audio mode \"$AUDIO\"" ;; esac
    case "$SAVE_DIR" in "~"|"~/"*) SAVE_DIR="$HOME${SAVE_DIR#\~}" ;; esac
    mkdir -p "$SAVE_DIR" || fail "Cannot create $SAVE_DIR"

    if [ "$HDR" = yes ]; then EXT="$HDR_CONTAINER"; else EXT="$CONTAINER"; fi
    FILE="$SAVE_DIR/Screencast_$(date +%Y%m%d_%H%M%S).$EXT"

    ARGS=()
    if [ -n "$REGION" ]; then ARGS+=(-w "$REGION"); else ARGS+=(-w "$OUTPUT"); fi
    ARGS+=(-f "$FPS" -q "$QUALITY" -cursor "$CURSOR" -fm "$FM")
    if [ "$HDR" = yes ]; then ARGS+=(-k "$HDR_CODEC" -cr full); else ARGS+=(-k "$CODEC" -cr "$CR"); fi
    case "$AUDIO" in
        system) ARGS+=(-a default_output) ;;
        system+mic) ARGS+=(-a "default_output|default_input") ;;
    esac
    # GSR refuses to start when -sc names a missing or non-executable script.
    [ -x "$SAVED_HOOK" ] && ARGS+=(-sc "$SAVED_HOOK")
    ARGS+=(-ipc "$SOCK" -o "$FILE")

    rm -f "$SOCK"
    touch "$LOG"
    LOG_BEFORE="$(stat -c %s "$LOG")"
    STARTED_AT="$(date +%s%3N)"
    # Detached on purpose: a recording outlives the overlay and a shell restart.
    RECORD_RUN_DIR="$RUN_DIR" setsid -f gpu-screen-recorder "${ARGS[@]}" </dev/null >>"$LOG" 2>&1

    i=0
    until running; do
        i=$((i + 1))
        if [ "$i" -ge 100 ]; then
            ERR="$(tail -c +"$((LOG_BEFORE + 1))" "$LOG" | tail -n 5)"
            fail "${ERR:-gpu-screen-recorder did not start}"
        fi
        sleep 0.1
    done
    [ "$HDR" = yes ] && HDR_JSON=true || HDR_JSON=false
    json s:file="$FILE" j:startedAt="$STARTED_AT" j:hdr="$HDR_JSON" s:audio="$AUDIO" \
         s:output="$OUTPUT" s:region="$REGION" j:logOffset="$LOG_BEFORE" > "$STATE"
    json j:ok=true s:file="$FILE" j:startedAt="$STARTED_AT" j:hdr="$HDR_JSON" s:audio="$AUDIO" \
         s:output="$OUTPUT" s:region="$REGION"
    ;;

status)
    command -v gsr-cli >/dev/null 2>&1 || { json j:running=false s:error="gsr-cli is not installed"; exit 0; }
    if ! running; then
        # Only an abnormal exit leaves current.json: stop and the -sc hook both remove it.
        [ -e "$STATE" ] && sleep 0.2
        [ -e "$STATE" ] || { json j:running=false; exit 0; }
        ERR="$(log_tail | grep '^gsr error' | tail -n 5)"
        [ -n "$ERR" ] || ERR="$(log_tail | tail -n 5)"
        rm -f "$STATE"
        json j:running=false s:error="${ERR:-gpu-screen-recorder exited}"
        exit 0
    fi
    python3 -c '
import json, os, sys, time
state, sock, paused = sys.argv[1:4]
try:
    o = json.load(open(state))
    assert isinstance(o, dict)
except Exception:
    o = {}
try:
    o.setdefault("startedAt", int(os.stat(sock).st_mtime * 1000))
except OSError:
    o.setdefault("startedAt", int(time.time() * 1000))
o["paused"] = paused == "true"
print(json.dumps({"running": True, **o}))' "$STATE" "$SOCK" "$(pause_state)"
    ;;

stop)
    need gsr-cli python3
    running || fail "not recording"
    OUT="$(timeout 60 gsr-cli -ipc "$SOCK" stop 2>>"$LOG")"; rc=$?
    if [ "$rc" -eq 124 ]; then
        pkill -INT -f -- "-ipc $SOCK"
        fail "The recorder is not responding; sent SIGINT"
    fi
    [ "$rc" -eq 0 ] || fail "gsr-cli stop failed"
    SAVED="$(printf '%s\n' "$OUT" | grep -v '^$' | tail -n 1)"
    [ -n "$SAVED" ] || SAVED="$(jq -r '.file // empty' "$STATE" 2>/dev/null)"
    rm -f "$STATE"
    [ -n "$SAVED" ] || fail "The recorder did not report a saved file"
    json j:ok=true s:file="$SAVED"
    ;;

pause)
    need gsr-cli python3
    running || fail "not recording"
    BEFORE="$(pause_lines | wc -l)"
    timeout 5 gsr-cli -ipc "$SOCK" toggle-pause >>"$LOG" 2>&1 || fail "toggle-pause failed"
    i=0
    while [ "$(pause_lines | wc -l)" -le "$BEFORE" ] && [ "$i" -lt 20 ]; do
        i=$((i + 1))
        sleep 0.05
    done
    json j:ok=true j:paused="$(pause_state)"
    ;;

*) usage ;;
esac
