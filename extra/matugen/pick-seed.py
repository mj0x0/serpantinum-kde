#!/usr/bin/env python3
"""Pick a Material You seed colour from an image, skipping degenerate hues.

Near-black and near-white pixels report a small but non-zero HCT chroma, so they clear
Material's own filter and then win on area, handing the scheme a meaningless hue.
"""
import sys

from PIL import Image
from materialyoucolor.hct import Hct
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score, ScoreOptions
from materialyoucolor.utils.color_utils import hex_from_argb

MIN_TONE = 8.0
MAX_TONE = 94.0
MIN_CHROMA = 12.0


def candidates(path):
    img = Image.open(path).convert("RGBA")
    w = 128
    img = img.resize((w, max(1, round(img.height * w / img.width))), Image.Resampling.LANCZOS)
    px = list(img.getdata())
    img.close()
    ranked = Score.score(QuantizeCelebi(px, 128),
                         ScoreOptions(desired=7, fallback_color_argb=0xFF4285F4, filter=True))
    return [Hct.from_int(c) for c in ranked]


def pick(path):
    ranked = candidates(path)
    if not ranked:
        return "#4285f4"
    for hct in ranked:
        if MIN_TONE <= hct.tone <= MAX_TONE and hct.chroma >= MIN_CHROMA:
            return hex_from_argb(hct.to_int())[:7]
    return hex_from_argb(ranked[0].to_int())[:7]


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: pick-seed.py <image> [--explain]")
    if "--explain" in sys.argv:
        for i, h in enumerate(candidates(sys.argv[1])):
            ok = MIN_TONE <= h.tone <= MAX_TONE and h.chroma >= MIN_CHROMA
            print(f"  {i}  {hex_from_argb(h.to_int())[:7]}  hue={h.hue:6.1f} "
                  f"chroma={h.chroma:5.1f} tone={h.tone:5.1f}  {'ok' if ok else 'REJECT'}")
    print(pick(sys.argv[1]))
