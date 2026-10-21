#!/usr/bin/env python3
# tesseract tsv on stdin -> one JSON line for the screenshot overlay:
#   {"ok": true, "text": "...", "lines": [{"x","y","w","h","text"}, ...]}
#   {"ok": false, "error": "..."}
# argv: UPSCALE  TEXTFILE  [STDERRFILE]
#   UPSCALE     the magick resize factor the image got before OCR; boxes are divided by it
#   TEXTFILE    tesseract's plain-text output for the same run ("-" or missing: built from the tsv)
#   STDERRFILE  tesseract's stderr, only read when the tsv carries no words, for the error text
# Boxes are pixels of the cropped region: level-4 rows give the line, level-5 rows its words.

import json
import re
import sys


def read_file(path):
    if not path or path == "-":
        return ""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def parse_tsv(raw, scale):
    lines, current, words = [], None, []

    def flush():
        if current is None:
            return
        text = " ".join(w for w in words if w.strip())
        if text:
            lines.append({**current, "text": text})

    for row in raw.split("\n"):
        cols = row.split("\t")
        if len(cols) < 12 or not cols[0].isdigit():
            continue
        level = int(cols[0])
        if level == 4:
            flush()
            try:
                x, y, w, h = (int(round(int(c) / scale)) for c in cols[6:10])
            except ValueError:
                current, words = None, []
                continue
            current, words = {"x": x, "y": y, "w": w, "h": h}, []
        elif level == 5 and current is not None:
            words.append(cols[11].strip())
    flush()
    return lines


def failure_reason(stderr):
    m = re.search(r"Failed loading language '([^']+)'", stderr)
    if m:
        return "Language pack '%s' is not installed (tesseract-data-%s)." % (m.group(1), m.group(1))
    for line in stderr.splitlines():
        line = line.strip()
        if line and not line.startswith(("Warning", "Please make sure", "Empty page")):
            return line[:160]
    return "No text found"


def main():
    try:
        scale = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    except ValueError:
        scale = 1.0
    if scale <= 0:
        scale = 1.0
    text_path = sys.argv[2] if len(sys.argv) > 2 else "-"
    err_path = sys.argv[3] if len(sys.argv) > 3 else ""

    sys.stdin.reconfigure(errors="replace")
    lines = parse_tsv(sys.stdin.read(), scale)
    if not lines:
        print(json.dumps({"ok": False, "error": failure_reason(read_file(err_path))}, ensure_ascii=False))
        return

    text = read_file(text_path)
    if not text.strip():
        text = "\n".join(l["text"] for l in lines)
    text = "\n".join(l.rstrip() for l in text.replace("\r", "").split("\n")).strip("\n")
    print(json.dumps({"ok": True, "text": text, "lines": lines}, ensure_ascii=False))


main()
