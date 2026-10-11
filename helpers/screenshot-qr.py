#!/usr/bin/env python3
# zbarimg --xml on stdin -> one "x,y,w,h|||text" line per symbol, read by the
# screenshot overlay (from serpantinum's screenshot.sh heredoc, see NOTICE).
# Coordinates are pixels inside the cropped region; newlines are escaped as \n.

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
    for child in symbol:
        if child.tag.endswith("data"):
            return child.text or ""
    return ""


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

    found = False
    for elem in tree.iter():
        if not elem.tag.endswith("symbol"):
            continue
        found = True
        x, y, w, h = bounds(elem)
        text = data_of(elem).replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "")
        print("%d,%d,%d,%d|||%s" % (x, y, w, h, text))
    if not found:
        print("0,0,0,0|||NOT_FOUND")


main()
