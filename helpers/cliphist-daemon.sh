#!/usr/bin/env bash
# cliphist capture watchers (text + images), idempotent, started from ~/.config/autostart.
# wl-clip-persist re-owns the selection, or apps that quit after copying leave it empty.
# File offers are skipped: a re-owned GTK4 file list no longer pastes (Strata Ctrl+V).
pgrep -x wl-clip-persist >/dev/null 2>&1 \
    || setsid -f wl-clip-persist --clipboard regular \
        --all-mime-type-regex '^(?!text/uri-list|application/vnd\.portal\.).*'

pgrep -fx "wl-paste --watch cliphist store" >/dev/null 2>&1 \
    || setsid -f wl-paste --watch cliphist store
pgrep -fx "wl-paste --type image --watch cliphist store" >/dev/null 2>&1 \
    || setsid -f wl-paste --type image --watch cliphist store
