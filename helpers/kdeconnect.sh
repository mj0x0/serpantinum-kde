#!/usr/bin/env bash
# KDE Connect bridge for the phone ring, read from the local daemon via qdbus6 (~5ms,
# VPN-immune). Device auto-discovered each call; any failure degrades to offline.

BUS="org.kde.kdeconnect"
DAEMON="/modules/kdeconnect"
Q="qdbus6"
TO="timeout 3"

first_device() {
    # daemon.devices(onlyReachable, onlyPaired) → newline-separated ids
    $TO $Q "$BUS" "$DAEMON" org.kde.kdeconnect.daemon.devices true true 2>/dev/null | head -1
}

prop() { # <path> <fully-qualified-property>  (qdbus6 needs no separate interface arg)
    $TO $Q "$BUS" "$1" "$2" 2>/dev/null
}

emit_once() {
    local id; id="$(first_device)"
    if [ -z "$id" ]; then
        printf '{"state":"offline"}\n'
        return
    fi
    local dp="$DAEMON/devices/$id"
    local name charge charging st ss
    name="$(prop "$dp" org.kde.kdeconnect.device.name)"
    charge="$(prop "$dp/battery" org.kde.kdeconnect.device.battery.charge)"
    charging="$(prop "$dp/battery" org.kde.kdeconnect.device.battery.isCharging)"
    st="$(prop "$dp/connectivity_report" org.kde.kdeconnect.device.connectivity_report.cellularNetworkType)"
    ss="$(prop "$dp/connectivity_report" org.kde.kdeconnect.device.connectivity_report.cellularNetworkStrength)"

    [[ "$charge" =~ ^-?[0-9]+$ ]] || charge=-1
    [[ "$ss" =~ ^-?[0-9]+$ ]] || ss=-1
    [ "$charging" = "true" ] && charging=true || charging=false
    [ -z "$name" ] && name="Phone"
    # JSON-escape the name (backslash then quote)
    name="${name//\\/\\\\}"; name="${name//\"/\\\"}"

    printf '{"state":"online","id":"%s","name":"%s","charge":%s,"charging":%s,"sigType":"%s","sigStrength":%s}\n' \
        "$id" "$name" "$charge" "$charging" "$st" "$ss"
}

act() { # <device-id> <subpath> <interface.method>
    [ -n "$1" ] || return 0
    $TO $Q "$BUS" "$DAEMON/devices/$1/$2" "$3" >/dev/null 2>&1
}

case "${1:---once}" in
    --once)          emit_once ;;
    --watch)         exec gdbus monitor --session --dest "$BUS" ;;
    ring)            act "$2" findmyphone org.kde.kdeconnect.device.findmyphone.ring ;;
    send-clipboard)  act "$2" clipboard   org.kde.kdeconnect.device.clipboard.sendClipboard ;;
    browse)          act "$2" sftp        org.kde.kdeconnect.device.sftp.startBrowsing ;;
    ping)            act "$2" ping        org.kde.kdeconnect.device.ping.sendPing ;;
    *)               emit_once ;;
esac
