# extra/

Installed outside the shell by `../install.sh`.

`../install.sh update` refreshes only `~/.config/quickshell/serpantinum-kde`; none of
this is touched.

| | |
|---|---|
| `matugen/` | app catalog, templates, themes, Plasma hook → `~/.config/matugen` |
| `bin/kvitals.sh` | bar vitals → `~/.local/bin`, run as `kvitals.sh --qs` |
| `kde/shortcuts.kksrc` | 23 commands, registered unbound; keys are yours to assign |
| `spicetify/` | Text theme → `~/.config/spicetify/Themes/Text` |
| `obsidian/` | Dashboard.md + snippets → your vault |
| `default-colors.json` | seed palette, or the shell renders transparent |
| `org.quickshell.serpantinum.desktop` | KWin screencast grant for dock thumbnails |

The grant is per executable. KWin only binds `zkde_screencast_unstable_v1` for a
client whose installed desktop file lists it, and caches that per connection —
so restart Quickshell after installing it, or previews fall back to icons.
