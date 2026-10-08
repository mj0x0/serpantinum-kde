#!/usr/bin/env bash
# cliphist capture watchers (text + images), idempotent, started from ~/.config/autostart.
# wl-clip-persist re-owns the selection, or apps that quit after copying leave it empty.
pgrep -x wl-clip-persist >/dev/null 2>&1 \
    || setsid -f wl-clip-persist --clipboard regular

pgrep -f "wl-paste --watch cliphist store" >/dev/null 2>&1 \
    || setsid -f wl-paste --watch cliphist store
pgrep -f "wl-paste --type image --watch cliphist store" >/dev/null 2>&1 \
    || setsid -f wl-paste --type image --watch cliphist store
