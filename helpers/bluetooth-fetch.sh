#!/usr/bin/env bash
# Bluetooth state + toggle. Avoids `bluetoothctl show`, which blocks until timeout with
# no adapter; rfkill plus a short busctl probe answer the same thing without hanging.

BT_ICON_ON="󰂯"
BT_ICON_OFF="󰂲"
BT_ICON_CONN="󰂱"

has_adapter() {
    # An adapter shows up as an rfkill device of type bluetooth.
    timeout 2 rfkill -J 2>/dev/null | grep -q '"type": *"bluetooth"'
}

adapter_path() {
    timeout 2 busctl --system tree org.bluez 2>/dev/null \
        | grep -oE '/org/bluez/hci[0-9]+' | head -1
}

powered() {
    local p; p=$(adapter_path)
    [ -z "$p" ] && { echo "no"; return; }
    if timeout 2 busctl --system get-property org.bluez "$p" org.bluez.Adapter1 Powered 2>/dev/null | grep -q 'true'; then
        echo "yes"
    else
        echo "no"
    fi
}

connected_device() {
    # First connected device's alias, if any.
    timeout 2 busctl --system call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.ListNames >/dev/null 2>&1 || { echo ""; return; }
    timeout 3 bluetoothctl devices Connected 2>/dev/null \
        | head -1 | cut -d' ' -f3- 
}

get_status() {
    if ! has_adapter; then
        echo "unavailable||$BT_ICON_OFF"
        return
    fi
    if [ "$(powered)" = "yes" ]; then
        local dev; dev=$(connected_device)
        if [ -n "$dev" ]; then
            echo "on|$dev|$BT_ICON_CONN"
        else
            echo "on||$BT_ICON_ON"
        fi
    else
        echo "off||$BT_ICON_OFF"
    fi
}

toggle_bt() {
    has_adapter || { notify-send -u low "Bluetooth" "No adapter found"; exit 0; }
    if [ "$(powered)" = "yes" ]; then
        timeout 3 rfkill block bluetooth 2>/dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        timeout 3 rfkill unblock bluetooth 2>/dev/null
        timeout 3 bluetoothctl power on >/dev/null 2>&1
        notify-send -u low -i bluetooth "Bluetooth" "Enabled"
    fi
}

case "$1" in
    --toggle) toggle_bt ;;
    *)
        IFS='|' read -r status dev icon <<< "$(get_status)"
        jq -n -c --arg status "$status" --arg connected "$dev" --arg icon "$icon" \
            '{status: $status, connected: $connected, icon: $icon}'
        ;;
esac
