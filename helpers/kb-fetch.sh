#!/usr/bin/env bash
# Current KDE keyboard layout short code (us / il / …) for the TopBar pill.
# KWin exposes layouts on org.kde.KWin /Layouts (org.kde.KeyboardLayouts).
idx=$(gdbus call --session -d org.kde.KWin -o /Layouts \
        -m org.kde.KeyboardLayouts.getLayout 2>/dev/null | grep -oP 'uint32 \K\d+' | head -n1)
[ -z "$idx" ] && idx=0
gdbus call --session -d org.kde.KWin -o /Layouts \
        -m org.kde.KeyboardLayouts.getLayoutsList 2>/dev/null \
    | grep -oP "\('\K[^']+" \
    | sed -n "$((idx + 1))p"
