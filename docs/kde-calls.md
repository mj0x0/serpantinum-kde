# KDE calls

Every KDE-specific thing the shell talks to. Quickshell gives us audio, Bluetooth,
networking, MPRIS, notifications and polkit natively — those are not here. systemd is out
of scope too: the Servers tab's `StopUnit`/`StartUnit` go straight to
`org.freedesktop.systemd1`, and `systemctl --user` handles a user unit — see
`helpers/servers.py`.

## KWin

| | |
|---|---|
| `qdbus6 org.kde.KWin /org/kde/KWin/NightLight …` | `running` / `daylight` to read Night Light, `preview <K>` + `stopPreview` to audition a temperature |
| `qdbus6 org.kde.KWin /KWin reconfigure` | make KWin re-read `kwinrc` after we write a Night Light temperature |
| `qdbus6 org.kde.kglobalaccel /component/kwin invokeShortcut <name>` | `Switch to Next/Previous Desktop` for the workspace wheel, `Toggle Night Color` |
| `gdbus call … org.kde.KWin /Layouts org.kde.KeyboardLayouts.switchToNextLayout` | cycle keyboard layout; `getLayoutsList` + `getLayout` read it back |
| `org.kde.KWin /VirtualDesktopManager` | `desktops` to list, `current` to switch (python-dbus, in `helpers/desktops.py`) |
| `org.kde.KWin /Scripting org.kde.kwin.Scripting` | load and `start` our two scripts in `kwin/` — window and workspace events QML cannot see |
| `gdbus call … org.kde.KWin /KWin org.kde.KWin.activeOutputName` | which monitor the screenshot overlay opens on; `kscreen-doctor` cannot answer it |
| `X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1` | not a call: the desktop-file grant that lets us capture live dock thumbnails |

KWin reuses `/Scripting/Script<id>`, so another client loading a script can stop ours by
id. The bridges watchdog themselves and exit on `NameLost`.

## Screen capture

| | |
|---|---|
| `spectacle -b -n -m -o <file>` | the current monitor, no UI and no notification of its own — the overlay's freeze and the `--full` shortcut |
| `spectacle -R region` | hand recording over to Spectacle, which draws its own selector; `-R` toggles, so the same call stops a recording |
| `swappy -f <file>` | annotate a region before it is saved (optional, `--edit`) |

| `org.kde.KWin.ScreenShot2.CaptureArea` | `helpers/kwinshot` — the overlay's freeze, pixels straight from the compositor instead of a ~250 ms Spectacle launch |

`CaptureArea` hands the frame back through a pipe the caller passes, so the call and the
read have to overlap or both ends wedge on a 64 KB pipe buffer. It is restricted: KWin
canonicalises the caller's `/proc/<pid>/exe` and wants an installed desktop file whose
`Exec` is that same binary, carrying `X-KDE-DBUS-Restricted-Interfaces`. That is per
binary, so a `qs -p <checkout>` shell runs a different `kwinshot` than `qs -c
serpantinum-kde` does and needs its own grant — `install.sh` writes both. Without one the
answer is `NoAuthorized` and the overlay falls back to Spectacle without a word.

Spectacle is single-instance: a capture started while another is live exits 0 and writes
nothing, so both callers test the file instead of the exit code.

## Plasma session

| | |
|---|---|
| `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript` | set the wallpaper: assigns `wallpaperPlugin` and writes its config per desktop |
| `qdbus6 org.kde.Shutdown /Shutdown logout` | log out from the power panel |
| `qdbus6 org.kde.ScreenBrightness /org/kde/ScreenBrightness/<display> …` | `Brightness` / `MaxBrightness` to read, `SetBrightness` to write; `DisplaysDBusNames` finds the display first |
| `kscreen-doctor -j` | the monitor list for the wallpaper picker |

Service name is lowercase `org.kde.plasmashell`, interface is CamelCase
`org.kde.PlasmaShell`. Swapping them gives a bare "Cannot find … evaluateScript".

## PowerDevil

| | |
|---|---|
| `busctl --user call org.kde.Solid.PowerManagement /…/Actions/PowerProfile setProfile` | performance / balanced / power-saver |
| `busctl --user call org.kde.Solid.PowerManagement /…/PolicyAgent SetInhibitionAllowed` | allow or block one app's sleep inhibition — PowerDevil persists this to `powerdevilrc`, so a block survives a relog |
| `org.kde.Solid.PowerManagement /…/PolicyAgent` → `RequestedInhibitions`, `HasInhibition` | who is keeping the machine awake — `a(ssssu)`, last field 0 = blocked; watched in `helpers/power-watch.py` |

Our own keep-awake holds `org.freedesktop.ScreenSaver` at **`/ScreenSaver`**, not
`/org/freedesktop/ScreenSaver` — KDE only answers the short path. PolicyAgent never
reports inhibitions taken by other clients that way.

## KDE Connect

`qdbus6 org.kde.kdeconnect` — `/modules/kdeconnect` `daemon.devices(true, true)` to enumerate, then per device
`battery.charge`, `battery.isCharging`, `clipboard.sendClipboard`, ring and share. About
5 ms a call, so `helpers/kdeconnect.sh` batches them and a `gdbus monitor` re-reads on
change instead of parsing signals.

## Config and packages

| | |
|---|---|
| `kreadconfig6 --file kdeglobals --group General --key ColorScheme` | which colour scheme is live (the matugen hook) |
| `kreadconfig6 --file kwinrc --group NightColor --key NightTemperature` | the Night Light temperature slider's starting value |
| `kwriteconfig6 --file kwinrc` | Night Light temperature |
| `kwriteconfig6 --file kglobalshortcutsrc` | register our commands unbound (`_launch=none,none,<Name>`) so they appear in System Settings |
| `kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage` | select our lock-screen package |
| `kwriteconfig6 --file kscreenlockerrc` | the lock-screen wallpaper |
| `kbuildsycoca6` | rebuild the desktop-file cache after we install one |
| `kpackagetool6 --type Plasma/Wallpaper` | install our wallpaper plugin; no `Version` in metadata, so it is remove-then-install, never `--upgrade` |
| `plasma-apply-colorscheme` | apply the scheme matugen just rendered |

`kglobalaccel` only reads `kglobalshortcutsrc` at login — a `.desktop` file alone is
inert, and a new entry will not appear until the next session.
