#!/usr/bin/env bash
# Minimal system monitor for the KDE "Command Output" plasmoid and the shell's
# SysData singleton.
#
#   (no args)   compact one-liner for the panel: cpu, ram, net
#   --detail    tooltip block: CPU, RAM, GPU + VRAM, network rates and totals
#   --qs        machine-readable pipe line, see below
#
# CPU% and net rates are deltas against a cached sample, timed by the real interval
# between runs, so they self-correct to whatever "Run every" is set to.

mode="compact"
[[ "$1" == "--detail" || "$1" == "-d" ]] && mode="detail"
# --qs: pipe line for the Quickshell SysData singleton:
#   cpu%|ram%|ram_gb_used|cpu_temp_c|down_bps|up_bps|disk%|disk_gb_used|disk_gb_total
# Uses its own state file so its 2 s cadence never collides with the panel's.
[[ "$1" == "--qs" ]] && mode="qs"

# --- Glyphs (Nerd Font — MesloLGS Nerd Font) ---
# Literal UTF-8 so they survive any shell; codepoints are named per line.
G_CPU="󰍛"   # U+F035B md-memory
G_RAM="󰱗"   # U+F0C57 md-memory-arrow-up
G_NET=""   # U+EB01  cod-globe
# Extra glyphs used only in --detail mode:
G_GPU="󰍹"   # U+F0379 md-expansion-card-variant-ish (GPU)
G_VRAM="󰍛" # U+F035B md-memory (VRAM)
G_TEMP="󰔏" # U+F050F md-thermometer
G_PWR=""   # U+F0E7  fa-bolt (power)
G_DOWN="↓"
G_UP="↑"

# Glyph-to-value spacing, expanded via printf %b so hex escapes work.
GAP=' '

# Glyphs sit at their box edge in the larger tooltip, so a single space clips.
LGAP='  '

# --- State file for deltas ---
state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state="$state_dir/kvitals_state"
# The Quickshell reader owns a separate baseline so the two cadences never collide.
[[ "$mode" == "qs" ]] && state="$state_dir/kvitals_state_qs"

# --- Network interfaces ---
# Primary = the default-route interface, the physical wire.
iface="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"

# VPN = first UP tunnel interface that isn't the primary. Proton's WireGuard uses policy
# routing, so the tunnel never becomes the default route even while carrying everything.
vpn_iface=""
for d in /sys/class/net/proton* /sys/class/net/tun* /sys/class/net/wg* /sys/class/net/tap*; do
    [[ -e "$d" ]] || continue
    name="${d##*/}"
    [[ "$name" == "$iface" ]] && continue
    # Tunnels often report 'unknown' rather than 'up'; only skip clearly-down ones.
    st="$(cat "$d/operstate" 2>/dev/null || echo unknown)"
    [[ "$st" == "down" ]] && continue
    [[ -r "$d/statistics/rx_bytes" ]] || continue
    vpn_iface="$name"
    break
done

# ---------- CPU ----------
# First line of /proc/stat: cpu  user nice system idle iowait irq softirq steal
read -r _ u n s idle iowait irq softirq steal _ < /proc/stat
idle_all=$((idle + iowait))
non_idle=$((u + n + s + irq + softirq + steal))
total=$((idle_all + non_idle))

# ---------- Network counters ----------
rx=0; tx=0
if [[ -n "$iface" && -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
    rx="$(< "/sys/class/net/$iface/statistics/rx_bytes")"
    tx="$(< "/sys/class/net/$iface/statistics/tx_bytes")"
fi

# VPN counters (only if a tunnel is up)
vrx=0; vtx=0
if [[ -n "$vpn_iface" && -r "/sys/class/net/$vpn_iface/statistics/rx_bytes" ]]; then
    vrx="$(< "/sys/class/net/$vpn_iface/statistics/rx_bytes")"
    vtx="$(< "/sys/class/net/$vpn_iface/statistics/tx_bytes")"
fi

# ---------- Load previous state ----------
prev_total=0; prev_idle=0; prev_rx=0; prev_tx=0; prev_time=0; prev_iface=""
prev_vrx=0; prev_vtx=0; prev_vpn_iface=""
if [[ -r "$state" ]]; then
    # shellcheck disable=SC1090
    source "$state"
fi

# A changed interface makes the byte counters incomparable; reset to avoid a spike.
if [[ "$iface" != "$prev_iface" ]]; then
    prev_rx="$rx"
    prev_tx="$tx"
fi
# Same guard for the VPN interface (it comes and goes as the tunnel toggles).
if [[ "$vpn_iface" != "$prev_vpn_iface" ]]; then
    prev_vrx="$vrx"
    prev_vtx="$vtx"
fi

now="$(date +%s.%N)"

# ---------- CPU delta ----------
cpu_pct=0
d_total=$((total - prev_total))
d_idle=$((idle_all - prev_idle))
if (( d_total > 0 )); then
    cpu_pct=$(( (100 * (d_total - d_idle) + d_total/2) / d_total ))
fi
(( cpu_pct < 0 )) && cpu_pct=0
(( cpu_pct > 100 )) && cpu_pct=100

# ---------- RAM: (MemTotal - MemAvailable) / MemTotal ----------
mem_total=0; mem_avail=0
while read -r key val _; do
    case "$key" in
        MemTotal:)     mem_total=$val ;;
        MemAvailable:) mem_avail=$val ;;
    esac
    [[ $mem_total -gt 0 && $mem_avail -gt 0 ]] && break
done < /proc/meminfo
ram_pct=0
if (( mem_total > 0 )); then
    ram_pct=$(( (100 * (mem_total - mem_avail) + mem_total/2) / mem_total ))
fi

# ---------- CPU temperature (only needed by --qs) ----------
cpu_temp=0
if [[ "$mode" == "qs" ]]; then
    for d in /sys/class/hwmon/hwmon*; do
        case "$(cat "$d/name" 2>/dev/null)" in
            k10temp|zenpower|coretemp)
                best=""
                for lf in "$d"/temp*_label; do
                    [[ -f "$lf" ]] || continue
                    case "$(cat "$lf" 2>/dev/null)" in
                        Tctl|Tdie|Package*) best="${lf%_label}_input"; break ;;
                    esac
                done
                [[ -z "$best" ]] && best="$d/temp1_input"
                v="$(cat "$best" 2>/dev/null)"
                [[ -n "$v" ]] && cpu_temp=$(( v / 1000 ))
                break ;;
        esac
    done
fi

# ---------- Network delta -> bytes/sec ----------
elapsed="$(awk -v a="$now" -v b="$prev_time" 'BEGIN{ d=a-b; if (d<=0) d=0; printf "%.3f", d }')"
down_bps=0; up_bps=0
if awk -v e="$elapsed" 'BEGIN{ exit !(e>0.05) }'; then
    down_bps="$(awk -v c="$rx" -v p="$prev_rx" -v e="$elapsed" 'BEGIN{ v=(c-p)/e; if (v<0) v=0; printf "%d", v }')"
    up_bps="$(awk -v c="$tx" -v p="$prev_tx" -v e="$elapsed" 'BEGIN{ v=(c-p)/e; if (v<0) v=0; printf "%d", v }')"
fi

# VPN rate delta (only meaningful when a tunnel is up)
vdown_bps=0; vup_bps=0
if [[ -n "$vpn_iface" ]] && awk -v e="$elapsed" 'BEGIN{ exit !(e>0.05) }'; then
    vdown_bps="$(awk -v c="$vrx" -v p="$prev_vrx" -v e="$elapsed" 'BEGIN{ v=(c-p)/e; if (v<0) v=0; printf "%d", v }')"
    vup_bps="$(awk -v c="$vtx" -v p="$prev_vtx" -v e="$elapsed" 'BEGIN{ v=(c-p)/e; if (v<0) v=0; printf "%d", v }')"
fi

# ---------- Save new state ----------
# Only the panel and qs runs own the state file; the hover run is irregular and would
# corrupt the next compact delta.
if [[ "$mode" == "compact" || "$mode" == "qs" ]]; then
    {
        echo "prev_total=$total"
        echo "prev_idle=$idle_all"
        echo "prev_rx=$rx"
        echo "prev_tx=$tx"
        echo "prev_time=$now"
        echo "prev_iface=\"$iface\""
        echo "prev_vrx=$vrx"
        echo "prev_vtx=$vtx"
        echo "prev_vpn_iface=\"$vpn_iface\""
    } > "$state"
fi

# ---------- Human-readable bytes/sec ----------
human() {
    awk -v b="$1" 'BEGIN{
        split("B K M G T", u, " ");
        i=1;
        while (b>=1024 && i<5){ b/=1024; i++ }
        if (i==1) printf "%d%s", b, u[i];
        else if (b>=100) printf "%.0f%s", b, u[i];
        else if (b>=10)  printf "%.1f%s", b, u[i];
        else             printf "%.1f%s", b, u[i];
    }'
}
down_h="$(human "$down_bps")"
up_h="$(human "$up_bps")"

# ================= QS MODE (Quickshell SysData) =================
# Pipe line consumed by SysData.qml: cpu%|ram%|ram_gb_used|cpu_temp|down|up|disk%|disk_gb_used|disk_gb_total
if [[ "$mode" == "qs" ]]; then
    ram_gb_used="$(awk -v used="$((mem_total - mem_avail))" 'BEGIN{ printf "%.1f", used/1048576 }')"

    # ---------- Disk: every real filesystem, deduped by device; df is cached 60 s ----------
    disk_file="$state_dir/kvitals_disk"
    disk_time_file="$state_dir/kvitals_disk_time"
    now_s="${now%.*}"
    last_disk_time=0
    [[ -f "$disk_time_file" ]] && last_disk_time="$(cat "$disk_time_file" 2>/dev/null || echo 0)"

    if [[ -f "$disk_file" ]] && (( now_s - last_disk_time < 60 )); then
        read -r disk_pct disk_used_gb disk_total_gb < "$disk_file"
    else
        read -r disk_pct disk_used_gb disk_total_gb <<< "$(df -Plk -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x iso9660 2>/dev/null | awk '
        NR > 1 && $1 !~ /^\/dev\/loop/ && $1 != "udev" && $1 != "none" {
            if (!seen[$1]++) {
                total += $2
                used += $3
            }
        }
        END {
            if (total > 0) {
                pct = int((used / total) * 100 + 0.5)
                printf "%d %.1f %.1f\n", pct, used / 1048576, total / 1048576
            } else {
                print "0 0.0 0.0"
            }
        }')"
        disk_pct=${disk_pct:-0}
        disk_used_gb=${disk_used_gb:-0.0}
        disk_total_gb=${disk_total_gb:-0.0}
        echo "$disk_pct $disk_used_gb $disk_total_gb" > "$disk_file"
        echo "$now_s" > "$disk_time_file"
    fi

    printf '%d|%d|%s|%d|%d|%d|%d|%s|%s\n' \
        "$cpu_pct" "$ram_pct" "$ram_gb_used" "$cpu_temp" "$down_bps" "$up_bps" \
        "$disk_pct" "$disk_used_gb" "$disk_total_gb"
    exit 0
fi

# ================= COMPACT MODE (panel) =================
if [[ "$mode" == "compact" ]]; then
    gap="$(printf '%b' "$GAP")"
    printf '%s%s%d%%  %s%s%d%%  %s%s%s%s %s%s' \
        "$G_CPU"  "$gap" "$cpu_pct" \
        "$G_RAM"  "$gap" "$ram_pct" \
        "$G_NET"  "$gap" "$G_DOWN" "$down_h" "$G_UP" "$up_h"
    exit 0
fi

# ================= DETAIL MODE (hover tooltip) =================
# The tooltip shows the widget's ANSI->HTML output literally, so colour markup
# arrives as raw <font> tags. Plain text only.

lgap="$(printf '%b' "$LGAP")"

# ---------- RAM in GB (meminfo is kB) ----------
ram_line="$(awk -v used="$((mem_total - mem_avail))" -v tot="$mem_total" -v pct="$ram_pct" \
    'BEGIN{ printf "%.1f / %.1f GB  (%d%%)", used/1048576, tot/1048576, pct }')"

# ---------- CPU load averages ----------
read -r la1 la5 la15 _ < /proc/loadavg
ncpu="$(nproc 2>/dev/null || echo "?")"

# ---------- GPU via nvidia-smi ----------
gpu_block=""
if command -v nvidia-smi >/dev/null 2>&1; then
    # One query: util%, mem used MiB, mem total MiB, temp C, power W
    gpu_csv="$(nvidia-smi \
        --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
        --format=csv,noheader,nounits 2>/dev/null | head -1)"
    if [[ -n "$gpu_csv" ]]; then
        IFS=',' read -r g_util g_used g_tot g_temp g_pwr <<< "$gpu_csv"
        g_util="${g_util// /}"; g_used="${g_used// /}"; g_tot="${g_tot// /}"
        g_temp="${g_temp// /}"; g_pwr="${g_pwr// /}"
        vram="$(awk -v u="$g_used" -v t="$g_tot" \
            'BEGIN{ if (t>0) printf "%.1f / %.1f GB  (%d%%)", u/1024, t/1024, (100*u/t)+0.5; else printf "n/a" }')"
        g_pwr_r="$(awk -v p="$g_pwr" 'BEGIN{ printf "%d", p+0.5 }')"
        gpu_block="$(printf '%s%sGPU   %s%%   %s %s°C   %s %sW\n%s%sVRAM  %s' \
            "$G_GPU" "$lgap" "$g_util" "$G_TEMP" "$g_temp" "$G_PWR" "$g_pwr_r" \
            "$G_VRAM" "$lgap" "$vram")"
    else
        gpu_block="$(printf '%s%sGPU   [asleep or unavailable]' "$G_GPU" "$lgap")"
    fi
else
    gpu_block="$(printf '%s%sGPU   [nvidia-smi not found]' "$G_GPU" "$lgap")"
fi

# ---------- Network: rates + counters since boot ----------
rx_total_h="$(human "${rx:-0}")"
tx_total_h="$(human "${tx:-0}")"
# VPN rates + totals (only used when a tunnel is up)
vdown_h="$(human "${vdown_bps:-0}")"
vup_h="$(human "${vup_bps:-0}")"
vrx_total_h="$(human "${vrx:-0}")"
vtx_total_h="$(human "${vtx:-0}")"

# ---------- Assemble tooltip ----------
{
    printf '%s%sCPU   %d%%   (load %s / %s / %s over %s cores)\n' \
        "$G_CPU" "$lgap" "$cpu_pct" "$la1" "$la5" "$la15" "$ncpu"
    printf '%s%sRAM   %s\n' "$G_RAM" "$lgap" "$ram_line"
    printf '\n%s\n\n' "$gpu_block"
    if [[ -n "$iface" ]]; then
        # Under a VPN the wire also carries unrouted traffic, so it runs a bit higher.
        printf '%s%sNET   %s  (wire)\n' "$G_NET" "$lgap" "$iface"
        printf '        ↓ %s/s   ↑ %s/s   (rate)\n' "$down_h" "$up_h"
        printf '        ↓ %s     ↑ %s     (since boot)\n' "$rx_total_h" "$tx_total_h"
            # The tunnel carries the decrypted side: the actual app traffic.
        if [[ -n "$vpn_iface" ]]; then
            printf '%s%sVPN   %s  (tunnel)\n' "$G_NET" "$lgap" "$vpn_iface"
            printf '        ↓ %s/s   ↑ %s/s   (rate)\n' "$vdown_h" "$vup_h"
            printf '        ↓ %s     ↑ %s     (since boot)\n' "$vrx_total_h" "$vtx_total_h"
        fi
    else
        printf '%s%sNET   [no default route]\n' "$G_NET" "$lgap"
    fi
}
exit 0
