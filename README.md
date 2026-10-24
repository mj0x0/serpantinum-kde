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
These have no upstream counterpart, or exist there only in a form KDE cannot use:

| | |
|---|---|
| Wallpaper plugin | a real Plasma wallpaper plugin, 47 shader transitions, video wallpapers |
| Lock screen | a real Plasma greeter package, Classic or Dashboard, picked at install time |
| Application themes | matugen themes the apps you tick in Settings, nothing you do not |
| Theme picker | 94 palettes previewed live across the whole running shell as the selection moves; Enter applies, Escape puts it back |
| Dock previews | live window thumbnails over KWin's screencast protocol |
| Wallhaven browser | search, preview and set wallpapers without leaving the shell |
| KDE Connect | phone battery and signal in the battery panel, with actions |
| Power panel | the profile at the core, every app holding the machine awake orbiting it — revoke any of them |
| Servers | containers and systemd units you self-host, the ports they listen on, stopped from the panel |

Plus a Bluetooth panel, a VPN/Wi-Fi network panel, a calendar with KDE's holidays, a
clipboard panel, a cheat sheet built from your own KDE shortcuts, and a Settings app for
all of it.

Upstream has its own lyrics, screenshot overlay, polkit agent, dock and lock screen; ours
are rebuilt on KDE's backends rather than ported, so they behave differently.

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

## IPC

Every panel and action is reachable over Quickshell's IPC, which is how the KDE global shortcuts
drive the shell:

```
qs ipc -p ~/.config/quickshell/serpantinum-kde/shell.qml call <target> <function> [args]
```

`qs ipc show` lists the live targets. **`show` is a `qs ipc` subcommand, so `call <target> show`
prints the interface instead of invoking it** — use `toggle` from the CLI.

| target | functions |
|---|---|
| `launcher`, `wallpaper`, `bluetooth`, `power`, `tray`, `cheatsheet`, `clipboard`, `themes`, `calendar`, `music`, `focustime` | `toggle` `show` `hide` |
| `notifcenter` | `toggle` `show` `hide` `clearAll` `list` |
| `network` | `toggle` `show` `hide` `vpn` `wifi` `ethernet` `servers` `openTab <tab>` |
| `volume` | `toggle` `show` `hide` `openTab <tab>` |
| `settings` | `toggle` `show` `hide` `open <page>` |
| `screenshot` | `toggle` `show` `hide` `edit` `state` |
| `record` | `toggle` `stop` `pause` `status` |
| `keepawake` | `toggle` `on` `off` |
| `dnd` | `toggle` `on` `off` `forMinutes <m>` |
| `osd` | `peek <kind>` `state` |
| `floating` | `toggle` `show` `hide` `openTab <i>` `setIndex <i>` `forceReload` |
| `redactor` (alias `widget-redactor`) | `activate` `open <mon> <id>` `toggle` `close` |
| `widgets-<monitor>` | `add` `remove` `move` `resize` `rotate` `opacity` `variant` `imagePath` `geometry` `bringToFront` `list` `save` `reload` `clear` `setRedactMode` |
| `topbar` | `forceReload` |
| `main` | `handleCommand <cmd> <target> <arg>` `hide` `current` |
| `memprobe` | `dump` — only with `debug.memProbe` set |

`widgets-<monitor>` is one target per screen, named after the output with non-alphanumerics
replaced by `_` (`widgets-HDMI-A-1`). Every function takes strings and returns a string.

Handy ones:

```
qs ipc -p <shell.qml> call record status          # recording state as JSON
qs ipc -p <shell.qml> call notifcenter list       # notification history as JSON
qs ipc -p <shell.qml> call dnd forMinutes 30
qs ipc -p <shell.qml> call network openTab vpn
```

## Licence

AGPL-3.0-or-later. See [LICENSE](LICENSE), and [NOTICE](NOTICE) for what is borrowed and
from whom.
