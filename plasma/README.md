# plasma/

Our lock screen overlay. Runs in `kscreenlocker_greet`, not Quickshell — no
access to our singletons; colours come from Kirigami, which matugen drives.

```bash
../install.sh lockscreen           # rebuild from stock, pick Dashboard or Classic, select
kscreenlocker_greet --testing      # preview
```

`org.serpantinum.wallpaper/` is the desktop wallpaper plugin, installed by core:
the picker points every desktop at it. `../install.sh wallpaper` reinstalls it alone.

`serpantinum-kde.shell/` holds **only the files we wrote**: the Dashboard look
(`LockScreenUi.qml`, its `Lock*.qml` cards, the small v2 reusables), `rpoly/` and
`pushy.gif`. Everything else is copied from the installed `plasma-desktop` at install
time. `lockscreen-v1/` is the Classic look, laid over the same package as a rollback.

The Dashboard is serpantinum v2's lock screen: an idle clock, then a three-column
card on the first keypress. Two deliberate differences: the vitals slot is our
calendar (KDE's headless calendar plus its holiday plugins), and the password echo is
rpoly's, shared with the polkit dialog. It reads `~/.config/quickshell/settings.json`
once (`ui.font`, `ui.radius`, `calendar.weekStart`, `calendar.astro`), the weather cache
the session keeps, and the running shell's notifications over `qs ipc --pid`.

Greeter limits: no `WAYLAND_DISPLAY` (use `qs ipc --pid`), remote images blocked,
`font.pixelSize` is an int (a `10.5` fails the whole theme at load, not in qmlcachegen).

`LockScreenUi.qml` started as a plasma-desktop file and keeps its SPDX header. Do not
strip it.
