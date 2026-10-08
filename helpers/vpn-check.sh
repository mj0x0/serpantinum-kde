#!/usr/bin/env bash
# Prints the first active VPN/tunnel interface, or nothing. WireGuard reports operstate
# `unknown` rather than `up`, and Proton's policy routing keeps it off the default route.
for d in /sys/class/net/proton* /sys/class/net/tun* /sys/class/net/wg* /sys/class/net/tap*; do
    [ -e "$d" ] || continue
    st="$(cat "$d/operstate" 2>/dev/null || echo down)"
    [ "$st" = "down" ] && continue
    echo "${d##*/}"
    exit 0
done
