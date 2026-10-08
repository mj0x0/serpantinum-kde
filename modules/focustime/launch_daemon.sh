#!/usr/bin/env bash
# FocusTime collector daemon; reads the focused window from the wm-bridge. Pins state/run dirs to the same
# locations Caching.qml computes, so the popup reads what the daemon writes.
export QS_STATE_FOCUSTIME="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/focustime"
export QS_RUN_FOCUSTIME="${XDG_RUNTIME_DIR:-/tmp}/quickshell/focustime"

exec python3 "$(dirname "$0")/focus_daemon.py"
