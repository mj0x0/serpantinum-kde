# templates/

Matugen templates. `../matugen-plasma-hook.sh` renders them after a wallpaper
change; `../apps.json` maps each to its output.

Ported from Noctalia's, which use the same engine. Gotchas found porting:

- `lighten(10)` → `lighten: 10` (matugen wants a colon)
- `.hex` is always opaque; use `.hex_alpha` for `#RRGGBBAA`
- `heroic-matugen.css` — Heroic takes the body class from the **file name**, so
  the filename and the `body.` selector must agree
- Spicetify reads colours from `color.ini` and rules from `user.css`. Two files.
