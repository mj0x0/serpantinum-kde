#!/usr/bin/env bash
# RSSI for connected Bluetooth devices as JSON - the one value Quickshell's native
# module does not expose. BlueZ only publishes it in range, so missing means no reading.
set -uo pipefail

BUSCTL=$(command -v busctl) || exit 0
out="{}"
first=1
printf '{'
for p in $("$BUSCTL" --system tree org.bluez 2>/dev/null \
          | grep -oE '/org/bluez/hci[0-9]+/dev_[A-F0-9_]+' | sort -u); do
    conn=$(timeout 2 "$BUSCTL" --system get-property org.bluez "$p" \
           org.bluez.Device1 Connected 2>/dev/null | awk '{print $2}')
    [ "$conn" = "true" ] || continue
    rssi=$(timeout 2 "$BUSCTL" --system get-property org.bluez "$p" \
           org.bluez.Device1 RSSI 2>/dev/null | awk '{print $2}')
    [ -n "${rssi:-}" ] || continue
    # /org/bluez/hciN/dev_AA_BB_.. -> AA:BB:..
    mac=$(printf '%s' "${p##*/dev_}" | tr '_' ':')
    [ $first -eq 1 ] || printf ','
    printf '"%s":%s' "$mac" "$rssi"
    first=0
done
printf '}\n'
