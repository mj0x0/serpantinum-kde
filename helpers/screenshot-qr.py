#!/usr/bin/env python3
# zbarimg --xml on stdin -> one "x,y,w,h|||text" line per symbol, read by the
# screenshot overlay (from serpantinum's screenshot.sh heredoc, see NOTICE).
# Coordinates are pixels inside the cropped region; newlines are escaped as \n.
#
# argv[1] is optional: the same scan through `zbarimg --raw`. The XML path transcodes
# with a guessed charset, so a UTF-8 payload comes back corrupted and then base64'd
# (an em dash arrives as ff ff 94). --raw passes the bytes through untouched, so its
# text wins whenever it lines up one-for-one with the symbols.

import base64
import re
import sys
import xml.etree.ElementTree as ET


def bounds(symbol):
    xs, ys = [], []
    for child in symbol:
        if not child.tag.endswith("polygon"):
            continue
        for pair in child.get("points", "").replace("+", "").split(" "):
            if "," not in pair:
                continue
            try:
                x, y = pair.split(",")
                xs.append(int(x))
                ys.append(int(y))
            except ValueError:
                pass
    if not xs:
        return 0, 0, 0, 0
    return min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)


def data_of(symbol):
    """The symbol's text. zbar base64s anything its charset guess left invalid."""
    for child in symbol:
        if not child.tag.endswith("data"):
            continue
        text = child.text or ""
        if (child.get("format") or "").lower() != "base64":
            return text
        try:
            return base64.b64decode(text, validate=False).decode("utf-8", "replace")
        except (ValueError, TypeError):
            return text
    return ""


def raw_lines(path):
    """`zbarimg --raw` output: one payload per line, bytes as the symbol carried them."""
    if not path:
        return []
    try:
        with open(path, "rb") as fh:
            blob = fh.read()
    except OSError:
        return []
    return blob.decode("utf-8", "replace").split("\n")[:-1]


def escape(text):
    return text.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "")


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        print("0,0,0,0|||NOT_FOUND")
        return
    try:
        clean = re.sub(r"\sxmlns=\"[^\"]+\"", "", raw)
        clean = re.sub(r"\sxmlns='[^']+'", "", clean)
        tree = ET.fromstring(clean)
    except ET.ParseError as e:
        print("0,0,0,0|||ERROR: XML parse failure: %s" % e)
        return

    symbols = [e for e in tree.iter() if e.tag.endswith("symbol")]
    if not symbols:
        print("0,0,0,0|||NOT_FOUND")
        return

    # Only pair positionally when the two passes agree on the count: a payload holding
    # a newline splits into extra lines, and a wrong pairing is worse than mangled text.
    raw = raw_lines(sys.argv[1] if len(sys.argv) > 1 else "")
    use_raw = len(raw) == len(symbols)

    for i, elem in enumerate(symbols):
        x, y, w, h = bounds(elem)
        text = raw[i] if use_raw else data_of(elem)
        print("%d,%d,%d,%d|||%s" % (x, y, w, h, escape(text)))


main()
