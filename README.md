# serpantinum-KDE

A [Quickshell](https://quickshell.org) shell for **KDE Plasma 6 on Wayland** — bar, dock,
launcher, notifications and the panels below, all coloured from your wallpaper by matugen.

```bash
./install.sh
```

Needs Quickshell 0.3.1 or newer and a Plasma 6 Wayland session. The installer checks every
dependency and offers to install what is missing, then starts it with `qs -n -c serpantinum-kde`.

## Not a 1:1 port

The look is [serpantinum](https://github.com/ilyamiro/serpantinum)'s, rebuilt for KDE.
These are ours, with no upstream counterpart:

| | |
|---|---|
| Wallpaper plugin | a real Plasma wallpaper plugin, 47 shader transitions, video wallpapers |
| Lock screen | our own Plasma greeter, Classic or Dashboard, picked at install time |
| Application themes | matugen themes the apps you tick in Settings, nothing you do not |
| Dock previews | live window thumbnails over KWin's screencast protocol |
| Wallhaven browser | search, preview and set wallpapers without leaving the shell |
| Lyrics | local `.lrc`, lrclib or netease; word- or line-synced, with a per-track offset |
| KDE Connect | phone battery and signal in the battery panel, with actions |
| Power panel | the profile at the core, every app holding the machine awake orbiting it — revoke any of them |
| Servers | containers and systemd units you self-host, the ports they listen on, stopped from the panel |
| Polkit agent | optional; replaces KDE's when enabled |

Plus a Bluetooth panel, a VPN/Wi-Fi network panel, a calendar with KDE's holidays, a
clipboard panel, a cheat sheet built from your own KDE shortcuts, and a Settings app for
all of it.

## Layout

| | |
|---|---|
| `shell.qml` | the single entry point |
| `modules/` | the UI: bar, dock, launcher, panels, settings |
| `modules/widgets/` | serpantinum v2 desktop widgets on KDE: one layer-shell window per widget, the redactor (`qs ipc call redactor toggle` or right-click a widget) lays them out; clock faces first |
| `services/` | singletons and the shared v2 controls |
| `helpers/` | the script and Python backends the QML shells out to |
| `kwin/` | KWin scripts for workspace and window events |
| `plasma/` | lock screen package and the wallpaper plugin — see [plasma/](plasma/) |
| `extra/` | everything installed outside the shell — see [extra/](extra/) |

## Licence

AGPL-3.0-or-later. See [LICENSE](LICENSE), and [NOTICE](NOTICE) for what is borrowed and
from whom.
