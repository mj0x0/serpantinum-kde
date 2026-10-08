#!/usr/bin/env python3
# Regenerate emoji.json from KDE's CLDR emoji dictionaries in /usr/share/plasma/emoji.
# Emits {e, n, k} entries, dropping skin-tone variants. Optional arg: locale.

import zlib, struct, json, os, sys

LOCALE = sys.argv[1] if len(sys.argv) > 1 else "en"
DICT = f"/usr/share/plasma/emoji/{LOCALE}.dict"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "emoji.json")


def main():
    if not os.path.exists(DICT):
        sys.exit(f"missing {DICT} — is plasma-workspace installed?")
    buf = zlib.decompress(open(DICT, "rb").read()[4:])
    pos = 0

    def u32():
        nonlocal pos
        v = struct.unpack_from("<I", buf, pos)[0]
        pos += 4
        return v

    def s():
        nonlocal pos
        n = u32()
        v = buf[pos:pos + n].decode("utf-8")
        pos += n
        return v

    count = u32()
    out = []
    for _ in range(count):
        emoji = s()
        name = s()
        u32()               # category id (unused)
        kn = u32()
        kws = [s() for _ in range(kn)]
        if "skin tone" in name:     # drop 👋🏻/👋🏼/… variants
            continue
        out.append({"e": emoji, "n": name, "k": kws})

    if pos != len(buf):
        print(f"warning: trailing bytes ({pos} != {len(buf)})", file=sys.stderr)
    json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {OUT}: {len(out)} emoji, {os.path.getsize(OUT)} bytes")


if __name__ == "__main__":
    main()
