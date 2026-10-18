#!/usr/bin/env bash

# KDE's GTK sync service rewrites gtk.css on every colour-scheme change, dropping
# this import; libadwaita reads it for the exact accent instead of its 9-colour snap.
gtk_css="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
if [[ -f "$gtk_css" ]] && ! grep -qF "@import 'matugen.css';" "$gtk_css"; then
    printf "\n@import 'matugen.css';\n" >> "$gtk_css"
fi

current=$(gsettings get org.gnome.desktop.interface color-scheme)

if [[ "$current" == "'prefer-dark'" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme prefer-light
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
else
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface color-scheme prefer-light
fi
