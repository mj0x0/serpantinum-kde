# extra/

Installed outside the shell by `../install.sh`.

`../install.sh update` refreshes only `~/.config/quickshell/serpantinum-kde`; none of
this is touched.

| | |
|---|---|
| `matugen/` | app catalog, templates, themes, Plasma hook → `~/.config/matugen` |
| `bin/kvitals.sh` | bar vitals → `~/.local/bin`, run as `kvitals.sh --qs` |
| `kde/shortcuts.kksrc` | 27 commands, registered unbound; keys are yours to assign |
| `spicetify/` | Text theme → `~/.config/spicetify/Themes/Text` |
| `obsidian/` | Dashboard.md + snippets → your vault |
| `default-colors.json` | seed palette, or the shell renders transparent |
| `org.quickshell.serpantinum.desktop` | KWin screencast grant for dock thumbnails |
| `org.serpantinum.kwinshot.desktop` | KWin ScreenShot2 grant for the screenshot helper, path templated in |

Both grants are per executable: KWin resolves the caller's `/proc/<pid>/exe` and
reads the keys off whichever installed desktop file has that same binary as its
`Exec`. The screencast one it caches per connection, so restart Quickshell after
installing it or previews fall back to icons. The ScreenShot2 one it re-checks on
every call, so that helper needs no restart — but it does need the binary built,
which is why `install.sh` writes the file only after `kwinshot` compiles, and
removes it again if a later run cannot rebuild.

Per executable also means per *copy*: a shell run as `qs -p <checkout>` launches the
checkout's `kwinshot`, which is a different file from the installed one and needs its
own grant. So `install.sh` builds both copies and writes both desktop files whenever
the checkout is not the install target. Deleting a file plus `kbuildsycoca6` revokes
that one; the overlay then goes back to Spectacle silently.
