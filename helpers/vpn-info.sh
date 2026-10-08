#!/usr/bin/env bash
# VPN status as JSON from local sources only: allowed-ips, `ip route get`, per-link DNS.
# A leak IS a route or resolver bypassing the tunnel, so nothing needs to leave the box.
set -uo pipefail

j() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1" 2>/dev/null || printf '""'; }

IFACE=""
for d in /sys/class/net/proton* /sys/class/net/wg* /sys/class/net/tun* /sys/class/net/tap*; do
    [ -e "$d" ] || continue
    [ "$(cat "$d/operstate" 2>/dev/null || echo down)" = "down" ] && continue
    IFACE="${d##*/}"; break
done

if [ -z "$IFACE" ]; then
    printf '{"up":false}\n'; exit 0
fi

CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
       | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')
DETAIL=$(nmcli -t connection show "$CONN" 2>/dev/null)

ENDPOINT=$(printf '%s' "$DETAIL" | grep -oE 'endpoint=[^ ]+' | head -1 | cut -d= -f2)
ALLOWED=$(printf '%s' "$DETAIL"  | grep -oE 'allowed-ips=[^ ]+' | head -1 | cut -d= -f2)
ADDR=$(printf '%s' "$DETAIL"     | awk -F: '/^ipv4.addresses:/ {print $2; exit}')
TS=$(printf '%s' "$DETAIL"       | awk -F: '/^connection.timestamp:/ {print $2; exit}')
TYPE=$(printf '%s' "$DETAIL"     | awk -F: '/^connection.type:/ {print $2; exit}')

# Proton names connections "ProtonVPN <CC>#<n>" — pull country + server out.
COUNTRY=$(printf '%s' "$CONN" | grep -oE '[A-Z]{2}#' | tr -d '#' | head -1)
SERVER=$(printf '%s'  "$CONN" | grep -oE '#[0-9]+'  | tr -d '#' | head -1)

KILL=false
# pvpn-killswitch-ipv6 is ProtonVPN's IPv6 leak protection and is up whenever the tunnel
# is, kill switch or not; the switch itself is pvpn-killswitch / pvpn-routed-killswitch.
nmcli -t -f NAME connection show --active 2>/dev/null \
    | grep -qiE '^pvpn-(routed-)?killswitch$' && KILL=true

ROUTE_DEV=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
[ "$ROUTE_DEV" = "$IFACE" ] && ROUTED=true || ROUTED=false
[ "$ALLOWED" = "0.0.0.0/0" ] && FULL=true || FULL=false

DNS=$(resolvectl dns "$IFACE" 2>/dev/null | sed 's/.*: //' | tr '\n' ' ' | awk '{$1=$1;print}')

# Absent/empty means no forwarded port - normal on most servers, not an error.
PORT=$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/Proton/VPN/forwarded_port" 2>/dev/null | tr -dc '0-9')

# Tunnel MTU: a wrong value is the classic cause of most sites work but some hang.
MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null)

RX=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
TX=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

cat <<JSON
{"up":true,
 "iface":$(j "$IFACE"),
 "conn":$(j "$CONN"),
 "country":$(j "$COUNTRY"),
 "server":$(j "$SERVER"),
 "type":$(j "$TYPE"),
 "endpoint":$(j "$ENDPOINT"),
 "addr":$(j "$ADDR"),
 "dns":$(j "$DNS"),
 "port":$(j "$PORT"),
 "mtu":$(j "$MTU"),
 "killswitch":$KILL,
 "fullTunnel":$FULL,
 "routed":$ROUTED,
 "since":${TS:-0},
 "rx":$RX,"tx":$TX}
JSON
