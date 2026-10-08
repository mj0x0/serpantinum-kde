"""Extract the embedded icon from a Windows .exe, with no extra packages.

Games installed through Heroic/Steam rarely have a cached cover, but every
Windows binary carries its own icon as a PE resource — so we read it straight out
of the executable. That keeps this fully local (no steamgriddb download) and is
literally "the icon of the exe".

`icoutils`/`pefile` would do this too, but neither is installed and both would be
a new dependency for ~100 lines of well-specified format parsing.

extract(exe, out_png) -> out_png | None
"""

import os
import struct

RT_ICON = 3

_ICONDIR = struct.Struct("<HHH")        # reserved, type, count
_ICONDIRENTRY = struct.Struct("<BBBBHHII")


def _rva_to_off(rva, sections):
    for va, vsz, praw, rawsz in sections:
        if va <= rva < va + max(vsz, rawsz):
            return praw + (rva - va)
    return None


def _walk(fh, base, off, sections, depth=0, want=None, out=None):
    """Recursively collect (type_id, data_rva, size) leaves of the resource tree."""
    if out is None:
        out = []
    fh.seek(base + off)
    hdr = fh.read(16)
    if len(hdr) < 16:
        return out
    n_named, n_id = struct.unpack_from("<HH", hdr, 12)
    entries = fh.read((n_named + n_id) * 8)
    for i in range(n_named + n_id):
        name, offset = struct.unpack_from("<II", entries, i * 8)
        is_dir = offset & 0x80000000
        offset &= 0x7FFFFFFF
        if depth == 0:
            # Top level is resource TYPE; only descend into the one we want.
            if (name & 0x80000000) or (want is not None and name != want):
                continue
        if is_dir:
            _walk(fh, base, offset, sections, depth + 1, want, out)
        else:
            fh.seek(base + offset)
            data_rva, size = struct.unpack("<II", fh.read(8))
            out.append((data_rva, size))
    return out


def _icon_dims(blob):
    """(w, h, bpp) for an RT_ICON payload (DIB or embedded PNG)."""
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", blob[16:24])
        return w, h, 32
    if len(blob) >= 40:
        w, h, planes, bpp = struct.unpack_from("<iiHH", blob, 4)
        return w, h // 2, bpp        # DIB height covers XOR+AND masks
    return 0, 0, 0


def extract(exe, out_png):
    """Write the largest embedded icon of `exe` to `out_png`. Returns the path or None."""
    try:
        with open(exe, "rb") as fh:
            if fh.read(2) != b"MZ":
                return None
            fh.seek(0x3C)
            pe_off = struct.unpack("<I", fh.read(4))[0]
            fh.seek(pe_off)
            if fh.read(4) != b"PE\0\0":
                return None
            coff = fh.read(20)
            nsec = struct.unpack_from("<H", coff, 2)[0]
            optsz = struct.unpack_from("<H", coff, 16)[0]
            opt = fh.read(optsz)
            magic = struct.unpack_from("<H", opt, 0)[0]
            dd = 112 if magic == 0x20B else 96          # PE32+ vs PE32
            rsrc_rva = struct.unpack_from("<I", opt, dd + 2 * 8)[0]
            if not rsrc_rva:
                return None

            sections = []
            for _ in range(nsec):
                s = fh.read(40)
                vsz, va, rawsz, praw = struct.unpack_from("<IIII", s, 8)
                sections.append((va, vsz, praw, rawsz))

            base = _rva_to_off(rsrc_rva, sections)
            if base is None:
                return None

            leaves = _walk(fh, base, 0, sections, want=RT_ICON)
            if not leaves:
                return None

            best, best_px = None, -1
            for data_rva, size in leaves:
                off = _rva_to_off(data_rva, sections)
                if off is None:
                    continue
                fh.seek(off)
                blob = fh.read(size)
                w, h, bpp = _icon_dims(blob)
                px = w * h * (2 if bpp >= 32 else 1)     # prefer 32-bit at equal size
                if px > best_px:
                    best, best_px = blob, px
            if not best:
                return None

        # Wrap the single image in a minimal ICO so Pillow can decode it.
        w, h, bpp = _icon_dims(best)
        ico = (_ICONDIR.pack(0, 1, 1)
               + _ICONDIRENTRY.pack(w if w < 256 else 0, h if h < 256 else 0,
                                    0, 0, 1, bpp, len(best), _ICONDIR.size + _ICONDIRENTRY.size)
               + best)

        from io import BytesIO
        from PIL import Image
        img = Image.open(BytesIO(ico))
        img = img.convert("RGBA")
        os.makedirs(os.path.dirname(out_png), exist_ok=True)
        img.save(out_png, "PNG")
        return out_png
    except Exception:
        return None
