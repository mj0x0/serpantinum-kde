#!/usr/bin/env bash
# serpantinum-KDE installer. The only script here: core install, optional extras,
# and the two in-tree binaries it has to compile.
set -euo pipefail

RICE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Quickshell finds a config as <xdg config>/quickshell/<name>/shell.qml, so the installed
# shell is `qs -c serpantinum-kde` from anywhere. The checkout is only the source.
SHELL_NAME="serpantinum-kde"
SHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/$SHELL_NAME"
APPS="$HOME/.local/share/applications"
KGA="${XDG_DATA_HOME:-$HOME/.local/share}/kglobalaccel"
AUTOSTART="$HOME/.config/autostart"
STAMP="$(date +%Y%m%d-%H%M%S)"
ASSUME_YES=0

if [ -t 1 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; O=$'\033[0m'
else
    B=""; DIM=""; GRN=""; YLW=""; RED=""; O=""
fi
say()  { printf '%s\n' "$*"; }
head1() { printf '\n%s%s%s\n' "$B" "$*" "$O"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$O" "$*"; }
skip() { printf '  %s·%s %s\n' "$DIM" "$O" "$*"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$O" "$*"; }
die()  { printf '%serror:%s %s\n' "$RED" "$O" "$*" >&2; exit 1; }
tilde() { case "$1" in "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;; *) printf '%s\n' "$1" ;; esac; }

ask() {   # ask <prompt> <default y|n>
    [ "$ASSUME_YES" = 1 ] && return 0
    local reply def="$2"
    read -r -p "  $1 [$( [ "$def" = y ] && echo 'Y/n' || echo 'y/N' )] " reply || true
    reply="${reply:-$def}"
    [ "${reply,,}" = y ]
}

backup() {   # move an existing path aside, once per run
    [ -e "$1" ] || return 0
    mv "$1" "$1.bak.$STAMP"
    skip "kept your old $(basename "$1") as $(basename "$1").bak.$STAMP"
}

# ── dependencies ─────────────────────────────────────────────────────────────
# bin:package:what breaks without it. This is the list; nothing else duplicates it.
REQUIRED=(
    "qs:quickshell:the shell itself"   # version checked separately, see quickshell_ok
    "python3:python:every helper backend"
    "kreadconfig6:kconfig:KDE config reads and writes"
    "kpackagetool6:kpackage:installing the Plasma wallpaper plugin"
    "spectacle:spectacle:screenshot captures and the freeze when kwinshot is not built"
    "magick:imagemagick:cropping screenshots, wallpaper thumbnails and Wallhaven"
    "timeout:coreutils:helper timeouts"
    "setpriv:util-linux:reaping helper children"
    "inotifywait:inotify-tools:live settings reload"
    "ip:iproute2:network panel addresses"
    "gdbus:glib2:KDE Connect and power monitors"
    "qdbus6:qt6-tools:the KDE Connect bridge"
    "jq:jq:screencast detection, equaliser"
    "pw-dump:pipewire:audio device state"
    "wpctl:wireplumber:default sink lookup"
    "pactl:libpulse:audio routing"
    "notify-send:libnotify:helper notifications"
    "xdg-open:xdg-utils:opening files from the shell"
)
OPTIONAL=(
    "playerctl:playerctl:media controls"
    "cava:cava:the music visualiser"
    "easyeffects:easyeffects:the equaliser"
    "songrec:songrec:song recognition"
    "qalc:libqalculate:the launcher calculator"
    "cliphist:cliphist:the clipboard panel"
    "wl-paste:wl-clipboard:the clipboard panel, copying a screenshot"
    "wl-clip-persist:wl-clip-persist:clipboard surviving the app that copied"
    "fd:fd:the launcher's file search"
    "dbus-monitor:dbus:waiting on MPRIS instead of polling"
    "swappy:swappy:annotating a screenshot before saving"
    "zbarimg:zbar:the QR scanner in the screenshot overlay"
    # One tesseract-data-<lang> per language; eng is the minimum, heb for Hebrew.
    "tesseract:tesseract-data-eng:text recognition in the screenshot overlay"
    "xdg-user-dir:xdg-user-dirs:the Screenshots folder, ~/Pictures otherwise"
    "ffmpeg:ffmpeg:video wallpaper frames, recording thumbnails"
    "gpu-screen-recorder:gpu-screen-recorder:screen recording from the screenshot overlay"
    "mkvpropedit:mkvtoolnix-cli:HDR peak metadata on recordings, or players crush them"
    "curl:curl:weather and album art"
    "bluetoothctl:bluez-utils:the Bluetooth panel"
    "nmcli:networkmanager:VPN status"
    "kscreen-doctor:libkscreen:the monitor list in the wallpaper picker"
    "matugen:matugen:all theming"
)

MISSING_REQ=()   # package names, for install_deps
MISSING_OPT=()

QS_MIN=0.3.1

# True only for real Quickshell at QS_MIN or newer.
quickshell_ok() {
    local line ver
    line="$(qs --version 2>/dev/null | head -1)"
    case "$line" in
        "Quickshell "*) ;;
        "") warn "\`qs --version\` printed nothing"; return 1 ;;
        *)  warn "\`qs\` here is ${line%% *}, not Quickshell — it installs the same binary names"
            return 1 ;;
    esac
    ver="${line#Quickshell }"; ver="${ver%% *}"
    if [ "$(printf '%s\n%s\n' "$QS_MIN" "$ver" | sort -V | head -1)" != "$QS_MIN" ]; then
        warn "Quickshell $ver is older than $QS_MIN"
        return 1
    fi
    return 0
}

check_deps() {   # check_deps [--offer] — --offer installs what is missing
    local offer=0
    [ "${1:-}" = --offer ] && offer=1
    head1 "Dependencies"
    MISSING_REQ=(); MISSING_OPT=()
    local why_req=() why_opt=() entry bin pkg why
    for entry in "${REQUIRED[@]}"; do
        IFS=: read -r bin pkg why <<< "$entry"
        command -v "$bin" >/dev/null 2>&1 && continue
        MISSING_REQ+=("$pkg"); why_req+=("$pkg ($bin) — $why")
    done
    for entry in "${OPTIONAL[@]}"; do
        IFS=: read -r bin pkg why <<< "$entry"
        command -v "$bin" >/dev/null 2>&1 && continue
        MISSING_OPT+=("$pkg"); why_opt+=("$pkg ($bin) — $why")
    done

    # `qs` on PATH proves nothing: noctalia-qs ships /usr/bin/qs AND /usr/bin/quickshell,
    # so the binary check above passes on a fork whose Networking and Polkit modules we cannot use.
    if command -v qs >/dev/null 2>&1 && ! quickshell_ok; then
        MISSING_REQ+=(quickshell); why_req+=("quickshell $QS_MIN or newer — Networking and Polkit need it")
    fi

    python3 -c 'import gi' 2>/dev/null   || { MISSING_REQ+=(python-gobject); why_req+=("python-gobject — keep awake, hidden SSIDs"); }
    python3 -c 'import dbus' 2>/dev/null || { MISSING_REQ+=(python-dbus);    why_req+=("python-dbus — the power watcher"); }
    python3 -c 'import PIL' 2>/dev/null  || { MISSING_OPT+=(python-pillow);  why_opt+=("python-pillow — Focus Time game icons"); }
    local qmldir
    qmldir="$(qmake6 -query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/qt6/qml)"
    [ -d "$qmldir/QtMultimedia" ] || { MISSING_REQ+=(qt6-multimedia); why_req+=("qt6-multimedia — the wallpaper plugin imports it; without it the desktop draws nothing"); }
    local families
    families="$(fc-list : family 2>/dev/null || true)"
    case "$families" in
        *"Iosevka Nerd Font"*) : ;;
        *) MISSING_REQ+=(ttf-iosevka-nerd); why_req+=("ttf-iosevka-nerd — EVERY icon in the shell") ;;
    esac

    if [ ${#MISSING_REQ[@]} -eq 0 ]; then
        ok "everything required is present"
    else
        warn "missing, and the shell needs these:"
        printf '      %s\n' "${why_req[@]}"
    fi
    if [ ${#MISSING_OPT[@]} -gt 0 ]; then
        skip "missing, each costs one feature and nothing else:"
        printf '      %s\n' "${why_opt[@]}"
        command -v tesseract >/dev/null 2>&1 \
            || skip "tesseract needs one tesseract-data-<lang> pack per language (eng is the minimum, heb for Hebrew)"
    fi
    [ "$offer" = 1 ] || return 0

    [ ${#MISSING_REQ[@]} -eq 0 ] || { install_pkgs "required" "${MISSING_REQ[@]}"; }
    [ ${#MISSING_OPT[@]} -eq 0 ] || { ask "Install the optional ones too?" y && install_pkgs "optional" "${MISSING_OPT[@]}"; }

    # Re-check: nothing below works without the required set.
    local still=() entry2 bin2 pkg2
    for entry2 in "${REQUIRED[@]}"; do
        IFS=: read -r bin2 pkg2 _ <<< "$entry2"
        command -v "$bin2" >/dev/null 2>&1 || still+=("$pkg2")
    done
    [ ${#still[@]} -eq 0 ] || ask "Still missing: ${still[*]}. Carry on anyway?" n || exit 1
    return 0
}

install_pkgs() {   # install_pkgs <label> <pkg>...
    local label="$1"; shift
    local pkgs=("$@") repo=() aur=() helper="" p h

    if ! command -v pacman >/dev/null 2>&1; then
        warn "not an Arch system — install the $label packages with your own package manager:"
        printf '      %s\n' "${pkgs[@]}"
        return 0
    fi

    # Anything the sync databases do not carry is AUR-only, and pacman cannot fetch it.
    for p in "${pkgs[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then repo+=("$p"); else aur+=("$p"); fi
    done

    if [ ${#repo[@]} -gt 0 ]; then
        say "      sudo pacman -S --needed ${repo[*]}"
        if ask "Run that?" y; then
            sudo pacman -S --needed "${repo[@]}" || warn "pacman did not finish cleanly"
        fi
    fi

    if [ ${#aur[@]} -gt 0 ]; then
        for h in paru yay pikaur; do command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }; done
        if [ -n "$helper" ]; then
            say "      $helper -S --needed ${aur[*]}"
            if ask "Run that? (AUR)" y; then
                "$helper" -S --needed "${aur[@]}" || warn "$helper did not finish cleanly"
            fi
        else
            warn "AUR-only, and no helper (paru, yay, pikaur) is installed:"
            printf '      %s\n' "${aur[@]}"
        fi
    fi
}

# ── the two in-tree binaries ─────────────────────────────────────────────────
build_binaries() {
    head1 "Building the helpers"
    local kh="$SHELL_DIR/helpers/kholidays"
    if command -v g++ >/dev/null 2>&1 && pkg-config --exists Qt6Core 2>/dev/null && [ -d /usr/include/KF6/KHolidays ]; then
        ( cd "$kh"
          # shellcheck disable=SC2046
          g++ -std=c++17 -O2 -fPIC khdump.cpp -o khdump \
              $(pkg-config --cflags --libs Qt6Core) \
              -I/usr/include/KF6 -I/usr/include/KF6/KHolidays -lKF6Holidays )
        ok "khdump"
    else
        warn "khdump skipped — needs gcc, qt6-base and kholidays; the Calendar drops holidays"
    fi

    # Never fatal: without it the screenshot overlay keeps freezing via Spectacle.
    local ks="$SHELL_DIR/helpers/kwinshot"
    if command -v g++ >/dev/null 2>&1 && pkg-config --exists Qt6DBus Qt6Gui 2>/dev/null; then
        # set -e does not reach inside an if-condition, so cd failing has to say so itself.
        if ( cd "$ks" || exit 1
             # shellcheck disable=SC2046
             g++ -std=c++17 -O2 -fPIC kwinshot.cpp -o kwinshot \
                 $(pkg-config --cflags --libs Qt6DBus Qt6Gui) ); then
            ok "kwinshot"
            # `qs -p <checkout>` runs the checkout's own copy, and KWin grants per
            # executable, so that binary has to exist too and gets its own grant.
            if [ "$RICE" != "$SHELL_DIR" ]; then
                cp -f "$ks/kwinshot" "$RICE/helpers/kwinshot/kwinshot" \
                    || warn "no copy in $RICE — a \`qs -p\` shell stays on Spectacle"
            fi
            install_kwinshot_grant
        else
            warn "kwinshot did not build — the overlay's freeze stays on Spectacle"
            drop_kwinshot_grants
        fi
    else
        warn "kwinshot skipped — needs gcc and qt6-base; the overlay's freeze stays on Spectacle"
        drop_kwinshot_grants
    fi
}

KWINSHOT_GRANT="org.serpantinum.kwinshot.desktop"
KWINSHOT_GRANT_DEV="org.serpantinum.kwinshot-dev.desktop"

write_kwinshot_grant() {   # write_kwinshot_grant <basename> <absolute exe>
    local tmpl="$RICE/extra/$KWINSHOT_GRANT" body
    [ -r "$tmpl" ] || { warn "$tmpl is missing — no ScreenShot2 grant"; return 1; }
    body="$(cat "$tmpl")"
    mkdir -p "$APPS"
    printf '%s\n' "${body//@KWINSHOT@/$2}" > "$APPS/$1"
    chmod 644 "$APPS/$1"
}

# KWin matches the grant by executable and takes the first service naming it, so there is
# one file per binary: the installed helper, and the checkout's for a `qs -p` shell.
install_kwinshot_grant() {
    write_kwinshot_grant "$KWINSHOT_GRANT" "$SHELL_DIR/helpers/kwinshot/kwinshot" || return 0
    local covers="$SHELL_NAME"
    # Tracks the checkout's copy instead of being written blind: a grant naming a binary
    # that is not there is inert and says nothing about why.
    if [ "$RICE" != "$SHELL_DIR" ] && [ -x "$RICE/helpers/kwinshot/kwinshot" ]; then
        write_kwinshot_grant "$KWINSHOT_GRANT_DEV" "$RICE/helpers/kwinshot/kwinshot"
        covers="$covers + this checkout"
    else
        rm -f "$APPS/$KWINSHOT_GRANT_DEV"
    fi
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
    ok "ScreenShot2 grant -> $APPS ($covers; delete the files and run kbuildsycoca6 to revoke)"
}

# A grant must not outlive the binary it names, or it is inert and unexplained.
drop_kwinshot_grants() {
    [ -e "$APPS/$KWINSHOT_GRANT" ] || [ -e "$APPS/$KWINSHOT_GRANT_DEV" ] || return 0
    rm -f "$APPS/$KWINSHOT_GRANT" "$APPS/$KWINSHOT_GRANT_DEV"
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
    skip "revoked the stale ScreenShot2 grant"
}

# ── core ─────────────────────────────────────────────────────────────────────
copy_shell() {
    # Nothing here is user-editable — settings live in ~/.config/quickshell/settings.json
    # and state in ~/.local/state — so the tree is replaced whole. One backup, overwritten.
    if [ -d "$SHELL_DIR" ]; then
        rm -rf "$SHELL_DIR.bak"
        mv "$SHELL_DIR" "$SHELL_DIR.bak"
    fi
    mkdir -p "$SHELL_DIR"
    # Runtime only: extra/ and plasma/ are installer input, not part of the shell.
    cp -a "$RICE/shell.qml" "$RICE/modules" "$RICE/services" "$RICE/helpers" "$RICE/kwin" \
          "$RICE/LICENSE" "$RICE/NOTICE" "$SHELL_DIR/"
    find "$SHELL_DIR" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
}

# Replace the installed shell with this checkout and everything derived from it.
# Leaves autostart, settings and the extras alone.
update_shell() {
    head1 "Update"
    [ -d "$SHELL_DIR" ] || { warn "nothing installed at $SHELL_DIR — run ./install.sh first"; return 1; }
    copy_shell
    ok "shell -> $SHELL_DIR  (previous kept as $(basename "$SHELL_DIR").bak)"
    install_wallpaper
    build_binaries
    install_matugen
    install_shortcuts
    head1 "Restart it"
    say "  qs -c $SHELL_NAME kill; qs -n -d -c $SHELL_NAME"
    say "  $DIM""Popup QML is loaded by URL, so a running shell will not pick this up on its own.""$O"
}

install_core() {
    head1 "Shell"

    # A default config at quickshell/shell.qml makes Quickshell ignore every named one.
    local default_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml"
    [ -e "$default_cfg" ] && warn "$default_cfg exists — Quickshell ignores named configs while it does"

    copy_shell
    ok "shell -> $SHELL_DIR  (run it with: qs -c $SHELL_NAME)"

    # The grant is per executable: KWin only binds its screencast protocol for a client
    # whose installed desktop file lists the interface, and caches the verdict per connection.
    rm -f "$APPS/org.quickshell.mj0x0.desktop"   # pre-rename installs
    install -Dm644 "$RICE/extra/org.quickshell.serpantinum.desktop" \
                   "$APPS/org.quickshell.serpantinum.desktop"
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
    ok "screencast grant -> $APPS (restart Quickshell before the dock previews work)"

    # Without this every colour resolves to "transparent" and the shell renders invisible.
    local colors="$HOME/.local/state/quickshell/generated/colors.json"
    if [ -s "$colors" ]; then
        skip "colours already generated, left alone"
    else
        install -Dm644 "$RICE/extra/default-colors.json" "$colors"
        ok "seed palette -> $colors (replaced by your first theme generation)"
    fi

    mkdir -p "$AUTOSTART"
    write_autostart quickshell-panel "Quickshell Panel" \
        "/usr/bin/quickshell -n -c $SHELL_NAME"
    write_autostart focustime-daemon "FocusTime Daemon" \
        "$SHELL_DIR/modules/focustime/launch_daemon.sh"
    write_autostart cliphist-store "cliphist clipboard capture" \
        "$SHELL_DIR/helpers/cliphist-daemon.sh"
    ok "autostart entries -> $AUTOSTART"
}

write_autostart() {   # write_autostart <basename> <name> <exec>
    cat > "$AUTOSTART/$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Terminal=false
NoDisplay=true
X-KDE-autostart-after=plasma-workspace
X-GNOME-Autostart-enabled=true
EOF
}

# One application with an action per command, all unbound. That desktop file is the whole
# component, so this never goes near kglobalshortcutsrc and cannot clobber a bound key.
install_shortcuts() {
    head1 "Shortcuts"
    local scheme="$RICE/extra/kde/shortcuts.conf"
    local file="$KGA/org.serpantinum.shell.desktop"
    local twin="$APPS/org.serpantinum.shell.desktop"
    [ -r "$scheme" ] || { warn "$scheme is missing — no global shortcuts"; return 0; }
    mkdir -p "$KGA" "$APPS" 2>/dev/null || { warn "cannot create $KGA — skipping global shortcuts"; return 0; }

    local icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
    if mkdir -p "$icons" 2>/dev/null && cp "$RICE/extra/kde/serpantinum.svg" "$icons/" 2>/dev/null; then
        chmod 644 "$icons/serpantinum.svg"
    else
        warn "could not install the icon — the entry falls back to a generic one"
    fi

    local rc="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalshortcutsrc" dest="" f
    if [ -f "$rc" ]; then
        dest="$HOME/.local/state/serpantinum-shortcuts-backup-$STAMP"
        # Copied, never backup()'d: moving kglobalshortcutsrc aside strips the live session.
        if mkdir -p "$dest/applications" 2>/dev/null && cp -a "$rc" "$dest/" 2>/dev/null; then
            for f in "$APPS"/net.local.*.desktop "$APPS"/serpantinum-kde.*.desktop; do
                [ -e "$f" ] || continue
                cp -a "$f" "$dest/applications/" 2>/dev/null || true
            done
            rmdir "$dest/applications" 2>/dev/null || true
            skip "kept a copy of your shortcuts in $(tilde "$dest")"
        else
            dest=""
            warn "could not back up your shortcuts — nothing of yours will be removed"
        fi
    fi

    local raw
    raw="$(python3 - "$scheme" "$SHELL_NAME" "$SHELL_DIR" "$RICE" "$APPS" "$KGA" <<'PY'
import configparser, os, shlex, sys

scheme, shell_name, shell_dir, rice, apps, kga = sys.argv[1:7]

def subst(s):
    return s.replace("@SHELL_NAME@", shell_name).replace("@SHELL_DIR@", shell_dir)

cp = configparser.RawConfigParser(strict=False)
cp.optionxform = str
cp.read(scheme, encoding="utf-8")
actions = [(slug, cp[slug].get("Name", slug), subst(cp[slug].get("Exec", "")),
            cp[slug].get("Suggested", "")) for slug in sorted(cp.sections())]

# NoDisplay, X-KDE-Shortcuts and X-KDE-GlobalShortcutType are all absent on purpose: each
# one either misfiles the group out of Applications or ships an action already bound.
out = ["[Desktop Entry]",
       "Type=Application",
       "Name=Serpantinum",
       "Icon=serpantinum",
       "Exec=" + subst("qs -c @SHELL_NAME@ ipc call settings toggle"),
       "StartupNotify=false",
       "Actions=" + "".join(slug + ";" for slug, _, _, _ in actions)]
for slug, name, exe, _ in actions:
    out += ["", "[Desktop Action %s]" % slug, "Name=" + name, "Exec=" + exe]
body = "\n".join(out) + "\n"
for d, text, mode in ((kga, "#!/usr/bin/env xdg-open\n" + body, 0o755),
                      (apps, body, 0o644)):
    path = os.path.join(d, "org.serpantinum.shell.desktop")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.chmod(path, mode)

for _, name, _, key in sorted(actions, key=lambda a: a[1]):
    if key:
        print("key\t%s\t%s" % (name, key))

# What an Exec line does, with the shell it was aimed at discarded, so a hand-made entry
# and our action compare equal. Both sides go through this one.
def norm(line):
    try:
        argv = shlex.split(line)
    except ValueError:
        return ""
    if not argv:
        return ""
    cmd = os.path.basename(argv[0])
    if cmd in ("qs", "quickshell"):
        if "call" not in argv:
            return ""
        i = argv.index("call")
        if i < 1 or argv[i - 1] != "ipc" or len(argv) < i + 3:
            return ""
        if "-p" in argv[1:i]:
            j = argv.index("-p") + 1
            if j >= i:
                return ""
            p = os.path.realpath(os.path.expanduser(argv[j]))
            if not (p.startswith(shell_dir + os.sep) or p.startswith(rice + os.sep)):
                return ""
        return "%s %s" % (argv[i + 1], argv[i + 2])
    if cmd == "player_control.sh" and len(argv) > 1:
        return "player_control.sh " + argv[1]
    if cmd == "screenshot.sh":
        return "screenshot.sh " + " ".join(sorted(a for a in argv[1:] if a.startswith("-")))
    return ""

by_exec = {}
for _, name, exe, _ in actions:
    key = norm(exe)
    if key:
        by_exec.setdefault(key, name)

def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return [line.rstrip("\n") for line in fh]
    except OSError:
        return []

rows, srows, matched = [], [], []
for fname in (sorted(os.listdir(apps)) if os.path.isdir(apps) else []):
    if not fname.endswith(".desktop"):
        continue
    if fname == "org.serpantinum.shell.desktop":   # our own copy, not a hand-made entry
        continue
    lines = read_lines(os.path.join(apps, fname))
    # that name plus that flag is the old installer's output and nothing else
    stale = fname.startswith("serpantinum-kde.") and \
        "X-KDE-GlobalAccel-CommandShortcut=true" in lines
    if stale:
        print("stale\t%s" % os.path.join(apps, fname))
    exe = next((l.split("=", 1)[1].strip() for l in lines if l.startswith("Exec=")), "")
    label = by_exec.get(norm(exe))
    if label:
        matched.append((label, fname, stale))

rc = configparser.RawConfigParser(strict=False)
rc.optionxform = str
try:
    rc.read(os.path.join(os.environ.get("XDG_CONFIG_HOME")
                         or os.path.expanduser("~/.config"), "kglobalshortcutsrc"),
            encoding="utf-8")
except configparser.Error:
    sys.exit(0)

bound = 0
for label, fname, stale in sorted(matched):
    key = rc.get("services][" + fname, "_launch", fallback="").split(",")[0].strip()
    if not key or key == "none":
        key = "(unbound)"
    elif not stale:
        bound += 1
    tag = "smap" if stale else "map"
    (srows if stale else rows).append("%s\t%s\t%s\t%s" % (tag, fname, key, label))
if rows:
    print("bound\t%d" % bound)
if rows or srows:
    print("\n".join(rows + srows))
PY
)" || { warn "could not build the shortcut actions"; return 0; }

    local keys=() maps=() smaps=() stale=() bound=0 tag a b c
    while IFS=$'\t' read -r tag a b c; do
        case "$tag" in
            key)   keys+=("$(printf '      %-34s %s' "$a" "$b")") ;;
            map)   maps+=("$(printf '      %-34s %-21s -> %s' "$a" "$b" "$c")") ;;
            smap)  smaps+=("$(printf '      %-34s %-21s -> %s' "$a" "$b" "$c")") ;;
            bound) bound="$a" ;;
            stale) stale+=("$a") ;;
        esac
    done <<< "$raw"

    [ -f "$file" ] || { warn "$file was not written — no global shortcuts"; return 0; }
    [ -f "$twin" ] || warn "$twin is missing — KDE will file the group under System Services"
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
    local n
    n="$(grep -c '^\[Desktop Action ' "$file" || true)"
    if [ "$n" -lt 2 ] || ! grep -q '^Type=Application$' "$file" \
       || grep -qE '^(NoDisplay|X-KDE-Shortcuts|X-KDE-GlobalAccel-CommandShortcut|X-KDE-GlobalShortcutType)=' "$file"; then
        warn "$file looks wrong — KDE would file it under the wrong section"
    fi
    ok "$n actions -> $(tilde "$file"), none of them bound"
    say "      $DIM""System Settings -> Shortcuts, under Applications, in one group called Serpantinum.""$O"
    say "      $DIM""kglobalacceld scans that directory once at login — log out and back in before it appears.""$O"

    if [ "${#stale[@]}" -gt 0 ]; then
        local ent="entries"
        if [ "${#stale[@]}" -eq 1 ]; then ent="entry"; fi
        skip "${#stale[@]} single-command $ent from an older install are still in $(tilde "$APPS")"
        if [ "${#smaps[@]}" -gt 0 ]; then
            say "      $DIM""The keys they hold, and the action that replaces each:""$O"
            printf '%s\n' "${smaps[@]}"
        fi
        say "      $DIM""Nothing was removed — delete them in System Settings when you are ready.""$O"
    fi

    if [ "${#keys[@]}" -gt 0 ]; then
        say ""
        say "  $DIM""The keys the rice was built around:""$O"
        printf '%s\n' "${keys[@]}"
        say "      $DIM""Super alone is KDE's application menu — clear that before binding the launcher to it.""$O"
    fi

    if [ "${#maps[@]}" -gt 0 ]; then
        say ""
        say "  $DIM""Your own shortcuts, and the new action each one matches:""$O"
        printf '%s\n' "${maps[@]}"
        local kept="$bound keys left exactly where they are"
        if [ "$bound" -eq 1 ]; then kept="1 key left exactly where it is"; fi
        skip "$kept — your own entries were not touched"
        say "      $DIM""Bind the Serpantinum actions in System Settings, then delete the old entries there.""$O"
    fi
}

install_matugen() {
    head1 "matugen"
    command -v matugen >/dev/null 2>&1 || warn "matugen is not installed; this only stages the files"
    local dest="$HOME/.config/matugen"
    mkdir -p "$dest"
    cp -r "$RICE/extra/matugen/." "$dest/"
    chmod +x "$dest/matugen-plasma-hook.sh" "$dest/render-config.py" "$dest/post-hook-scripts/"*.sh 2>/dev/null || true
    ok "app catalog, templates, themes and the Plasma hook -> $dest"
    [ -f "$dest/config.toml" ] \
        && skip "config.toml is no longer read: pick apps in Settings -> Appearance -> Application themes; custom tables go in $dest/user.toml"

    # The pywalfox template writes colors.json, but `pywalfox update` pushes it to a
    # LIVE extension through a native messaging host that only `pywalfox install` creates.
    if command -v pywalfox >/dev/null 2>&1; then
        pywalfox install >/dev/null 2>&1 && ok "pywalfox native messaging host installed" \
            || warn "pywalfox install failed; Firefox will not update live"
    fi
    say "      $DIM""Pick the apps to theme in Settings -> Appearance -> Application themes.""$O"
    say "      $DIM""Generate the theme with: $dest/matugen-plasma-hook.sh <wallpaper>""$O"
}

# ── extras ───────────────────────────────────────────────────────────────────
extra_lockscreen() {
    head1 "Plasma lock screen"
    local stock=/usr/share/plasma/shells/org.kde.plasma.desktop
    local dest="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/shells/serpantinum-kde.shell"
    local ours="$RICE/plasma/serpantinum-kde.shell"
    [ -d "$stock" ] || { warn "stock package not found at $stock"; return 0; }

    local look=dashboard reply
    if [ "$ASSUME_YES" != 1 ]; then
        say "  1  Dashboard    clock, then a three-column card on the first keypress (default)"
        say "  2  Classic      the earlier lock screen, kept as a rollback"
        read -r -p "  Which look? [1/2] " reply || true
        case "$reply" in 2|c|C|classic) look=classic ;; esac
    fi

    # Rebuilt from stock every time: every file we did not write must match the INSTALLED Plasma.
    backup "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$stock" "$dest"
    cp "$ours/metadata.json" "$dest/"
    if [ "$look" = classic ]; then
        cp -a "$ours/contents/lockscreen/rpoly" "$dest/contents/lockscreen/"
        cp "$RICE/plasma/lockscreen-v1/"*.qml "$dest/contents/lockscreen/"
        ok "Classic package -> $dest"
    else
        cp -a "$ours/contents/lockscreen/." "$dest/contents/lockscreen/"
        ok "Dashboard package -> $dest"
    fi

    if ask "Select it in plasmashellrc now?" y; then
        kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage serpantinum-kde.shell
        ok "plasmashellrc [Shell] ShellPackage=serpantinum-kde.shell"
        say "      $DIM""Preview: kscreenlocker_greet --testing   ·   real: loginctl lock-session""$O"
        say "      $DIM""Undo:    kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage org.kde.plasma.desktop""$O"
    fi
    say "      $DIM""Re-run this after a plasma-desktop update to rebase on the new stock files, or to switch looks.""$O"
}

# ── wallpaper plugin ─────────────────────────────────────────────────────────
# Core, not an extra: helpers/set-wallpaper.py sets d.wallpaperPlugin to this id, so
# without the package nothing the picker does ever reaches the desktop.
install_wallpaper() {
    head1 "Plasma wallpaper plugin"
    local src="$RICE/plasma/org.serpantinum.wallpaper"
    local id=org.serpantinum.wallpaper out
    command -v kpackagetool6 >/dev/null 2>&1 \
        || die "kpackagetool6 is missing (package: kpackage) — the wallpaper plugin is required"

    # No Version in metadata.json, so --upgrade refuses: remove first, ignore "not installed".
    kpackagetool6 --type Plasma/Wallpaper --remove "$id" >/dev/null 2>&1 || true
    out="$(kpackagetool6 --type Plasma/Wallpaper --install "$src" 2>&1)" \
        || die "installing $id failed — the wallpaper picker would have nothing to draw on: ${out##*$'\n'}"
    ok "$id installed"
}

IMG_EXTS_JS="['.png','.jpg','.jpeg','.webp','.avif','.bmp','.gif','.tif','.tiff','.mp4','.mkv','.mov','.webm']"

# Point every desktop at the plugin, carrying over the image it already shows.
select_wallpaper_plugin() {
    local state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper/current"
    local keep="" script
    [ -s "$state" ] && keep="$(head -1 "$state")"

    if ! command -v qdbus6 >/dev/null 2>&1 || ! qdbus6 org.kde.plasmashell >/dev/null 2>&1; then
        warn "plasmashell is not answering — pick it by hand in Configure Desktop and Wallpaper"
        return 0
    fi
    ask "Use it on every screen now?" y || {
        skip "left alone — Wallpaper type: Serpantinum, whenever you want it"
        return 0
    }

    script="$(KEEP="$keep" python3 -c 'import json, os, sys
keep = os.environ.get("KEEP", "")
print("var keep = %s;" % json.dumps("file://" + os.path.abspath(keep) if keep else ""))')"
    script="$script
var exts = $IMG_EXTS_JS;
function drawable(u) {
    u = String(u || '').toLowerCase();
    for (var k = 0; k < exts.length; k++)
        if (u.slice(-exts[k].length) === exts[k]) return true;
    return false;
}
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
    var d = ds[i];
    if (d.screen === -1) continue;
    var img = keep;
    if (!img) {
        d.currentConfigGroup = ['Wallpaper', d.wallpaperPlugin, 'General'];
        img = String(d.readConfig('Image') || '');
        if (!drawable(img)) img = '';
    }
    d.wallpaperPlugin = 'org.serpantinum.wallpaper';
    d.currentConfigGroup = ['Wallpaper', 'org.serpantinum.wallpaper', 'General'];
    if (img) d.writeConfig('Image', img);
}"
    if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1; then
        ok "every screen is on Serpantinum now"
    else
        warn "plasmashell refused the switch — pick it in Configure Desktop and Wallpaper"
    fi
    say "      $DIM""A black desktop means plasmashell has not seen the new package: log out and back in.""$O"
}

extra_spicetify() {
    head1 "Spicetify theme"
    command -v spicetify >/dev/null 2>&1 || { warn "spicetify is not installed"; return 0; }
    local dest="$HOME/.config/spicetify/Themes/Text"
    mkdir -p "$dest"
    backup "$dest/user.css"
    cp "$RICE/extra/spicetify/Themes/Text/user.css" "$dest/user.css"
    [ -f "$dest/color.ini" ] || cp "$RICE/extra/spicetify/Themes/Text/color.ini" "$dest/color.ini"
    ok "Text theme -> $dest"
    if ask "Select it and apply?" y; then
        spicetify config current_theme Text color_scheme "" inject_css 1 replace_colors 1 >/dev/null
        spicetify apply >/dev/null 2>&1 || warn "spicetify apply failed; run it yourself once Spotify is closed"
        ok "applied"
    fi
    say "      $DIM""color.ini is rewritten by matugen on every wallpaper change.""$O"
}

extra_obsidian() {
    head1 "Obsidian dashboard"
    local vault="${1:-}"
    [ -n "$vault" ] || read -r -p "  Vault path: " vault
    vault="${vault/#\~/$HOME}"
    [ -d "$vault/.obsidian" ] || { warn "$vault is not an Obsidian vault"; return 0; }

    backup "$vault/Dashboard.md"
    cp "$RICE/extra/obsidian/Dashboard.md" "$vault/Dashboard.md"
    mkdir -p "$vault/.obsidian/snippets"
    cp "$RICE/extra/obsidian/snippets/"*.css "$vault/.obsidian/snippets/"
    ok "Dashboard.md and its snippets -> $vault"

    local writer="$SHELL_DIR/helpers/settings-write.py"
    local settings="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings.json"
    if [ ! -f "$writer" ]; then
        skip "shell not installed — tick Obsidian in Settings -> Appearance -> Application themes and set the vault to $vault"
    elif python3 - "$settings" "$vault" <<'PY' | python3 "$writer"; then
import json, os, sys

path, vault = sys.argv[1], os.path.abspath(sys.argv[2])
home = os.path.expanduser("~")
if vault == home or vault.startswith(home + os.sep):
    vault = "~" + vault[len(home):]
try:
    with open(path, encoding="utf-8") as fh:
        s = json.load(fh)
except FileNotFoundError:
    s = {}
except (OSError, ValueError) as e:
    sys.exit(f"settings.json unreadable: {e}")
if not isinstance(s, dict):
    s = {}
a = s.get("appearance")
if not isinstance(a, dict):
    a = s["appearance"] = {}
apps = a.get("apps") if isinstance(a.get("apps"), list) else []
if "obsidian" not in apps:
    apps.append("obsidian")
a["apps"] = apps
paths = a.get("appPaths") if isinstance(a.get("appPaths"), dict) else {}
paths["obsidian"] = vault
a["appPaths"] = paths
json.dump(s, sys.stdout)
PY
        ok "Obsidian ticked in Application themes, matugen.css renders into this vault"
    else
        warn "could not update settings.json — tick Obsidian in Settings -> Appearance -> Application themes"
    fi

    say "      $DIM""Needs the Dataview plugin with JS queries enabled.""$O"
    say "      $DIM""Enable dashboard.css, dashboard-fullwidth.css and matugen.css in Appearance -> CSS snippets.""$O"
    say "      $DIM""The weather card asks for its own OpenWeather key, in the card.""$O"
}

# ── menu ─────────────────────────────────────────────────────────────────────
run_extras_menu() {
    local choice
    while :; do
        head1 "Extras"
        say "  1  Plasma lock screen        our greeter, rebuilt on the installed plasma-desktop"
        say "  2  Spicetify theme           the matugen-coloured Text theme"
        say "  3  Obsidian dashboard        Dashboard.md and its CSS snippets"
        say "  q  done"
        read -r -p $'\n  Pick one: ' choice || break
        case "$choice" in
            1) extra_lockscreen ;;
            2) extra_spicetify ;;
            3) extra_obsidian ;;
            q|Q|"") break ;;
            *) warn "no such entry" ;;
        esac
    done
}

usage() {
    cat <<EOF
serpantinum-KDE installer

  ./install.sh                  check, build, install the shell, then the extras menu
  ./install.sh check            list what is missing, change nothing
  ./install.sh deps             install what is missing (pacman, plus an AUR helper)
  ./install.sh core             deps, build and install the shell, no extras
  ./install.sh wallpaper        reinstall the Plasma wallpaper plugin (core installs it)
  ./install.sh matugen          reinstall the templates and the Plasma hook (core installs them)
  ./install.sh shortcuts        reinstall the KDE shortcut actions (core installs them)
  ./install.sh update           replace the installed shell with this checkout, nothing else
  ./install.sh extras           the extras menu on its own
  ./install.sh <extra> [arg]    one extra: lockscreen | spicetify | obsidian [vault]
  -y                            take the default answer to every question
EOF
}

main() {
    local args=()
    for a in "$@"; do
        case "$a" in
            -y|--yes) ASSUME_YES=1 ;;
            -h|--help) usage; exit 0 ;;
            *) args+=("$a") ;;
        esac
    done

    case "${args[0]:-}" in
        check)      check_deps ;;
        deps)       check_deps --offer ;;
        core)       check_deps --offer; install_core; install_shortcuts; install_wallpaper
                    select_wallpaper_plugin; build_binaries; install_matugen ;;
        update)     update_shell ;;
        extras)     run_extras_menu ;;
        lockscreen) extra_lockscreen ;;
        wallpaper)  install_wallpaper; select_wallpaper_plugin ;;
        shortcuts)  install_shortcuts ;;
        spicetify)  extra_spicetify ;;
        obsidian)   extra_obsidian "${args[1]:-}" ;;
        matugen)    install_matugen ;;
        "")         check_deps --offer; install_core; install_shortcuts; install_wallpaper
                    select_wallpaper_plugin; build_binaries; install_matugen; run_extras_menu
                    head1 "Done"
                    say "  Start it now:  qs -n -c $SHELL_NAME"
                    say "  $DIM""It also starts with the session from now on.""$O" ;;
        *)          usage; exit 1 ;;
    esac
}

main "$@"
