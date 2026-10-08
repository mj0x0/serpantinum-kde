#!/usr/bin/env python3
"""Fetch timed lyrics for a track. Prints JSON on stdout, always exit 0.

Backends, tried in order under --backend auto:
    local    *.lrc on disk
    lrclib   lrclib.net — free, no key, no auth
    netease  music.163.com internal API — no key, but REQUIRES a Referer header

That Referer is why this is a helper and not QML: Qt's QML XMLHttpRequest
implements the fetch spec's forbidden-header list, and Referer is on it, so a
pure-QML client can never talk to netease. Verified in libQt6Qml.so.6.

Stdlib only — this ships with the shell and must not need pip.

Usage:
    lyrics.py --title T --artist A [--album X] [--duration 202] [--words]
              [--backend auto|local|lrclib|netease]
    lyrics.py --search  --title T --artist A      # candidates, no lyrics
    lyrics.py --id ID --backend lrclib|netease    # fetch one known candidate

--words hunts netease for word timings (its `yrc`, line-level `lrc`'s sibling)
and serves them as lines[].words; without it the output is line-level only.
"""

import argparse
import concurrent.futures as futures
import difflib
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

TIMEOUT = 8

UA_POLITE = "quickshell-rice-mj0x0 (https://github.com/mj0x0)"
UA_BROWSER = "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"

LRCLIB_HEADERS = {"User-Agent": UA_POLITE}
NETEASE_HEADERS = {"User-Agent": UA_BROWSER, "Referer": "https://music.163.com/"}


def xdg(var, fallback):
    return os.environ.get(var) or os.path.expanduser(fallback)


CACHE_DIR = os.path.join(xdg("XDG_CACHE_HOME", "~/.cache"), "quickshell", "lyrics")
DEFAULT_LOCAL_DIRS = [
    os.path.join(xdg("XDG_DATA_HOME", "~/.local/share"), "quickshell", "lyrics"),
    os.path.expanduser("~/Music"),
]


# --- LRC parsing ------------------------------------------------------------

TIME_RE = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")
OFFSET_RE = re.compile(r"^\s*\[offset:\s*([+-]?\d+)\s*\]", re.M)

# Lines like "作词：X" or "Composer: Y" are credits, not lyrics. Only stripped
# near the start of the file, where they actually appear.
CREDIT_WORDS = (
    "作词", "作曲", "编曲", "制作", "收录", "演奏", "词：", "曲：",
    "lyricist", "composer", "arranger", "producer", "mixing", "mastering",
)


def is_credit(t, lyric):
    if t >= 20.0:
        return False
    low = lyric.lower()
    if not any(w in low for w in CREDIT_WORDS):
        return False
    return ":" in lyric or "：" in lyric or len(lyric) < 25


def parse_lrc(text):
    out = []
    # A positive [offset:] means the lyrics are shown that many ms earlier.
    m = OFFSET_RE.search(text)
    shift = int(m.group(1)) / 1000.0 if m else 0.0
    for line in text.splitlines():
        stamps = list(TIME_RE.finditer(line))
        if not stamps:
            continue

        lyric = TIME_RE.sub("", line).strip()

        def stamp_time(m):
            return int(m.group(1)) * 60.0 + float(m.group(2).replace(":", ".")) - shift

        if is_credit(stamp_time(stamps[0]), lyric):
            continue

        for m in stamps:
            out.append({"t": round(max(0.0, stamp_time(m)), 3), "text": lyric})

    out.sort(key=lambda l: l["t"])
    return out


# --- yrc (netease word timings) --------------------------------------------
# One line per lyric line: [lineMs,durMs](wordMs,durMs,0)word(wordMs,durMs,0)word...
# Word text keeps its own spacing, so the words concatenate back into the line.

YRC_LINE_RE = re.compile(r"^\[(\d+),(\d+)\](.*)$")
YRC_WORD_RE = re.compile(r"\((\d+),(\d+),\d+\)([^(]*)")


def parse_yrc(text):
    out = []
    for line in (text or "").splitlines():
        m = YRC_LINE_RE.match(line.lstrip())
        if not m:
            continue
        t, d = int(m.group(1)) / 1000.0, int(m.group(2)) / 1000.0
        words = []
        for a, b, w in YRC_WORD_RE.findall(m.group(3)):
            if not w.strip() and words:
                words[-1]["text"] += w
            elif w.strip():
                words.append({"t": round(int(a) / 1000.0, 3),
                              "d": round(int(b) / 1000.0, 3), "text": w})
        joined = "".join(w["text"] for w in words).strip()
        if is_credit(t, joined):
            continue
        entry = {"t": round(t, 3), "d": round(d, 3), "text": joined}
        if words:
            entry["words"] = words
        out.append(entry)
    out.sort(key=lambda l: l["t"])
    return out


def yrc_has_words(text):
    return any("words" in l for l in parse_yrc(text))


def letters(s):
    return re.sub(r"[\W_]+", "", (s or "").lower())


def word_lines(yrc, lrc):
    """Lines timed by the yrc, worded by the lrc where it is the same line.

    The yrc mangles punctuation (a comma comes back as an apostrophe) and its
    line times differ from the lrc's by up to seconds, so it must be the sole
    timing source; the lrc only lends its text, token for token, when the
    token counts agree.
    """
    lines = parse_yrc(yrc)
    if not any("words" in l for l in lines):
        return []
    clean = {}
    for l in parse_lrc(lrc):
        clean.setdefault(letters(l["text"]), l["text"])
    for l in lines:
        text = clean.get(letters(l["text"]))
        if not text:
            continue
        l["text"] = text
        toks = text.split()
        if "words" in l and len(toks) == len(l["words"]):
            for w, tok in zip(l["words"], toks):
                raw = w["text"]
                w["text"] = raw[:len(raw) - len(raw.lstrip())] + tok + raw[len(raw.rstrip()):]
    return lines


# --- matching helpers -------------------------------------------------------

def norm(s):
    s = unicodedata.normalize("NFKD", s or "").lower()
    s = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", s)
    s = re.sub(r"[^\w\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def contains_ci(a, b):
    a, b = norm(a), norm(b)
    return bool(a) and bool(b) and (a in b or b in a)


def safe_name(s):
    return re.sub(r"[^\w.\- ]", "_", s or "").strip() or "unknown"


# --- cache ------------------------------------------------------------------

INDEX_PATH = os.path.join(CACHE_DIR, "index.json")


def track_key(track):
    return "%s|%s" % (norm(track["artist"]), norm(track["title"]))


def index_load():
    try:
        with open(INDEX_PATH, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def index_save(idx):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = INDEX_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(idx, f, ensure_ascii=False)
        os.replace(tmp, INDEX_PATH)
    except OSError:
        pass


def index_put(track, backend, ident, has_words=None):
    if not ident:
        return
    idx = index_load()
    entry = idx.get(track_key(track)) or {}
    if entry.get("backend") != backend or entry.get("id") != str(ident):
        entry.pop("hasWords", None)
    entry.update({"backend": backend, "id": str(ident)})
    if has_words is not None:
        entry["hasWords"] = bool(has_words)
    idx[track_key(track)] = entry
    index_save(idx)


def index_offset(track):
    entry = index_load().get(track_key(track)) or {}
    try:
        return float(entry.get("offset") or 0.0)
    except (TypeError, ValueError):
        return 0.0


def index_set_offset(track, offset):
    idx = index_load()
    entry = idx.get(track_key(track)) or {}
    entry["offset"] = round(float(offset), 3)
    idx[track_key(track)] = entry
    index_save(idx)


def cache_path(backend, ident):
    if not ident or backend in ("auto", "local"):
        return None
    return os.path.join(CACHE_DIR, backend, safe_name(str(ident)) + ".lrc")


def cache_read(backend, ident):
    p = cache_path(backend, ident)
    if p and os.path.isfile(p):
        try:
            with open(p, encoding="utf-8") as f:
                return f.read()
        except OSError:
            pass
    return ""


def cache_write(backend, ident, text, force=False):
    p = cache_path(backend, ident)
    if not p or not (text or force):
        return
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, p)
    except OSError:
        pass


# The yrc sits beside its lrc as <id>.yrc; an empty file records "fetched, none".
def yrc_path(ident):
    p = cache_path("netease", ident)
    return p[:-4] + ".yrc" if p else None


def yrc_cache_read(ident):
    """(known, text): known is False when the yrc was never fetched."""
    p = yrc_path(ident)
    if p and os.path.isfile(p):
        try:
            with open(p, encoding="utf-8") as f:
                return True, f.read()
        except OSError:
            pass
    return False, ""


def yrc_cache_write(ident, text):
    p = yrc_path(ident)
    if not p:
        return
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text or "")
        os.replace(tmp, p)
    except OSError:
        pass


# --- http -------------------------------------------------------------------

def get_json(url, params, headers):
    full = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(full, headers={
        "Accept": "application/json",
        "Cache-Control": "no-cache, no-store",
        **headers,
    })
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


# --- backends ---------------------------------------------------------------

def try_local(track, dirs):
    flat = "%s - %s.lrc" % (safe_name(track["artist"]), safe_name(track["title"]))
    want = norm("%s %s" % (track["artist"], track["title"]))
    want_title = norm(track["title"])

    for d in dirs:
        if not os.path.isdir(d):
            continue

        direct = os.path.join(d, flat)
        if os.path.isfile(direct):
            return direct

        for root, _, files in os.walk(d):
            for fn in files:
                if not fn.lower().endswith(".lrc"):
                    continue
                stem = norm(os.path.splitext(fn)[0])
                if stem == want or (want_title and stem == want_title):
                    return os.path.join(root, fn)
    return None


def try_lrclib(track):
    params = {"track_name": track["title"], "artist_name": track["artist"]}
    if track["album"]:
        params["album_name"] = track["album"]
    if track["duration"] > 0:
        params["duration"] = int(round(track["duration"]))

    obj = get_json("https://lrclib.net/api/get", params, LRCLIB_HEADERS)
    synced = obj.get("syncedLyrics") or ""
    if not synced:
        return None

    ident = str(obj.get("id") or "")
    cache_write("lrclib", ident, synced)
    return {
        "id": ident,
        "lrc": synced,
        "candidate": {
            "backend": "lrclib", "id": ident,
            "title": obj.get("trackName") or "", "artist": obj.get("artistName") or "",
            "album": obj.get("albumName") or "", "duration": obj.get("duration") or 0,
        },
    }


def lrclib_by_id(ident):
    obj = get_json("https://lrclib.net/api/get/" + urllib.parse.quote(str(ident)), {}, LRCLIB_HEADERS)
    synced = obj.get("syncedLyrics") or ""
    if synced:
        cache_write("lrclib", ident, synced)
    return synced


def _lrclib_rows(params):
    arr = get_json("https://lrclib.net/api/search", params, LRCLIB_HEADERS)
    out = []
    for o in arr if isinstance(arr, list) else []:
        if not o.get("syncedLyrics"):
            continue
        out.append({
            "backend": "lrclib", "id": str(o.get("id") or ""),
            "title": o.get("trackName") or "", "artist": o.get("artistName") or "",
            "album": o.get("albumName") or "", "duration": o.get("duration") or 0,
        })
    return out


def lrclib_search(track):
    """Two passes: the structured one, then free text.

    `q=` reaches records the track_name/artist_name pair does not — notably the
    Hebrew catalogue, where the structured lookup returns nothing at all.
    """
    out = _lrclib_rows({"track_name": track["title"], "artist_name": track["artist"]})
    seen = {c["id"] for c in out}
    try:
        for c in _lrclib_rows({"q": track["title"]}):
            if c["id"] not in seen:
                seen.add(c["id"])
                out.append(c)
    except (urllib.error.URLError, OSError, ValueError):
        pass
    return out


def netease_songs(track):
    obj = get_json("https://music.163.com/api/search/get",
                   {"s": "%s %s" % (track["title"], track["artist"]), "type": 1, "limit": 5},
                   NETEASE_HEADERS)
    return (obj.get("result") or {}).get("songs") or []


def netease_fetch(ident):
    """(lrc, yrc) for one song, both cached. yv=1 asks for the word timings."""
    obj = get_json("https://music.163.com/api/song/lyric",
                   {"id": ident, "lv": 1, "kv": 1, "tv": -1, "yv": 1}, NETEASE_HEADERS)
    lrc = (obj.get("lrc") or {}).get("lyric") or ""
    yrc = (obj.get("yrc") or {}).get("lyric") or ""
    if lrc:
        cache_write("netease", ident, lrc)
        yrc_cache_write(ident, yrc)
    return lrc, yrc


def netease_by_id(ident):
    return netease_fetch(ident)[0]


def netease_cached(ident):
    """(lrc, yrc) from the cache, fetching only when the yrc was never asked for."""
    lrc = cache_read("netease", ident)
    known, yrc = yrc_cache_read(ident)
    if lrc and known:
        return lrc, yrc
    return netease_fetch(ident)


def netease_candidate(s):
    return {
        "backend": "netease", "id": str(s.get("id") or ""),
        "title": s.get("name") or "",
        "artist": ", ".join(a.get("name") or "" for a in (s.get("artists") or [])),
        "album": (s.get("album") or {}).get("name") or "",
        "duration": (s.get("duration") or 0) / 1000.0,
    }


def artist_ok(track, s):
    artists = s.get("artists") or []
    return bool(artists) and contains_ci(track["artist"], artists[0].get("name") or "")


def duration_ok(track, c):
    return track["duration"] <= 0 or c["duration"] <= 0 \
        or abs(c["duration"] - track["duration"]) <= 5.0


def try_netease(track, want_words=False):
    songs = [s for s in netease_songs(track) if artist_ok(track, s)]
    if not songs:
        return None

    if not want_words:
        best = netease_candidate(songs[0])
        lrc, yrc = netease_fetch(best["id"])
        return {"id": best["id"], "lrc": lrc, "yrc": yrc, "candidate": best} if lrc else None

    # Word timings are not always on the first hit, so verify the close matches
    # and prefer one that has them, provided the recording is the same length.
    good = verify([netease_candidate(s) for s in songs[:5]])
    if not good:
        return None
    worded = [c for c in good if c["hasWords"] and duration_ok(track, c)]
    worded.sort(key=lambda c: (bool(track["album"]) and norm(c["album"]) == norm(track["album"]),
                               score_candidate(track, c)), reverse=True)
    best = worded[0] if worded else good[0]
    lrc, yrc = netease_cached(best["id"])
    return {"id": best["id"], "lrc": lrc, "yrc": yrc, "candidate": best} if lrc else None


def hunt_words(track):
    """A word-timed netease match good enough to replace line-level lyrics."""
    res = try_netease(track, True)
    if not res or not res["candidate"]["hasWords"]:
        return None
    # Never trade a sure match for a doubtful one just to get words.
    if score_candidate(track, res["candidate"]) < 0.75:
        return None
    return res


def netease_search(track):
    return [netease_candidate(s) for s in netease_songs(track)]


# --- driver -----------------------------------------------------------------

def emit(obj, final=True):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.stdout.flush()
    if final:
        sys.exit(0)


TRACK = {"artist": "", "title": ""}


def miss(reason, tried, candidates=None):
    emit({"ok": False, "reason": reason, "tried": tried, "lines": [],
          "candidates": candidates or [],
          "artist": TRACK["artist"], "title": TRACK["title"]})


def ratio(a, b):
    if not a or not b:
        return 0.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def score_candidate(track, c):
    """How plausible a match is, 0..1.

    The query title is the strongest signal: for a browser player it usually
    contains the real artist AND title, so a candidate whose title appears
    inside it is almost certainly right. Ranking matters because the two search
    passes interleave good and bad results.
    """
    qt, qa = norm(track["title"]), norm(track["artist"])
    ct, ca = norm(c.get("title")), norm(c.get("artist"))

    best = max(
        ratio(ct, qt),
        ratio((ca + " " + ct).strip(), (qa + " " + qt).strip()),
        ratio((ca + " " + ct).strip(), qt),
    )

    # Exact containment beats any fuzzy score; longer matches count for more.
    if ct and ct in qt:
        best = max(best, 0.90 + 0.09 * (len(ct) / max(len(qt), 1)))
    if ca and ca in qt:
        best += 0.05

    return min(best, 1.0)


def gather_candidates(track, backend="auto", want_words=False):
    """Options for the picker when the automatic lookup has failed.

    The second pass drops the artist. Browser players report the channel as the
    artist ("Helicon Music"), and that string poisons the query far more than the
    video title does — the title alone reliably surfaces the right track, while
    the channel name buries it. No separator parsing: YouTube titles are not
    consistent enough to split on, and the picker exists precisely because this
    match is ambiguous.
    """
    out = []
    seen = set()

    def collect(t):
        for fn, name in ((lrclib_search, "lrclib"), (netease_search, "netease")):
            if backend not in ("auto", name):
                continue
            try:
                for c in fn(t):
                    key = (c["backend"], c["id"])
                    if key not in seen:
                        seen.add(key)
                        out.append(c)
            except (urllib.error.URLError, OSError, ValueError):
                pass

    collect(track)
    if track["artist"]:
        collect({**track, "artist": ""})

    out.sort(key=lambda c: score_candidate(track, c), reverse=True)
    # Verification costs a request per netease candidate, so bound those to five;
    # lrclib's exact matches would otherwise crowd them out of the shortlist.
    short = out[:8]
    for c in out:
        if len([x for x in short if x["backend"] == "netease"]) >= 5:
            break
        if c["backend"] == "netease" and c not in short:
            short.append(c)
    out = verify(short)
    # Word timings break ties only; the bonus can never outrank a better match.
    bonus = 0.05 if want_words else 0.0
    out.sort(key=lambda c: score_candidate(track, c) + (bonus if c["hasWords"] else 0.0),
             reverse=True)
    return out[:10]


def verify(cands):
    """Drop candidates that have no lyrics behind them.

    netease's search lists songs from its catalogue whether or not it holds
    lyrics for them, and offering one that turns out empty is worse than not
    offering it — the user picks the right song and still gets nothing. Only a
    fetch can tell, so fetch them at once; the LRC lands in the cache, which
    also makes the pick itself instant. lrclib is already filtered at search
    time on syncedLyrics being present.
    """
    for c in cands:
        c.setdefault("hasWords", False)
    todo = [c for c in cands if c["backend"] == "netease" and c["id"]]
    if not todo:
        return cands

    def check(c):
        try:
            lrc, yrc = netease_cached(c["id"])
            return c["id"], bool(lrc.strip()), yrc_has_words(yrc)
        except (urllib.error.URLError, OSError, ValueError):
            return c["id"], False, False

    found = {}
    with futures.ThreadPoolExecutor(max_workers=min(8, len(todo))) as ex:
        for cid, ok, words in ex.map(check, todo):
            found[cid] = (ok, words)

    out = []
    for c in cands:
        if c["backend"] == "netease":
            ok, words = found.get(c["id"], (False, False))
            if not ok:
                continue
            c["hasWords"] = words
        out.append(c)
    return out


def hit(backend, ident, lines, candidate, cached, notes, offset=0.0, pending=False):
    """pending: these lines show now, a word-timed replacement may follow on the next line."""
    emit({
        "ok": True, "backend": backend, "id": ident, "cached": cached,
        "lines": lines, "count": len(lines), "offset": offset,
        "hasWords": any("words" in l for l in lines), "pending": pending,
        "artist": TRACK["artist"], "title": TRACK["title"],
        "candidate": candidate, "candidates": [], "notes": notes,
    }, final=not pending)


def netease_lines(lrc, yrc, want_words):
    """Word-timed lines when asked for and available, else the plain lrc."""
    if want_words and yrc:
        lines = word_lines(yrc, lrc)
        if lines:
            return lines
    return parse_lrc(lrc)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--title", default="")
    ap.add_argument("--artist", default="")
    ap.add_argument("--album", default="")
    ap.add_argument("--duration", type=float, default=0.0)
    ap.add_argument("--backend", default="auto",
                    choices=["auto", "local", "lrclib", "netease"])
    ap.add_argument("--local-dir", action="append", default=None)
    ap.add_argument("--id", default="")
    ap.add_argument("--search", action="store_true")
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--set-offset", type=float, default=None)
    ap.add_argument("--words", action="store_true")
    args = ap.parse_args()

    track = {
        "title": args.title.strip(), "artist": args.artist.strip(),
        "album": args.album.strip(), "duration": args.duration,
    }
    TRACK.update(artist=track["artist"], title=track["title"])
    dirs = args.local_dir or DEFAULT_LOCAL_DIRS
    notes = []

    if args.set_offset is not None:
        if not track["title"]:
            return miss("--set-offset needs --title/--artist", [])
        index_set_offset(track, args.set_offset)
        emit({"ok": True, "offset": round(args.set_offset, 3), "lines": [], "candidates": []})

    # Fetch one specific candidate the user picked.
    if args.id:
        if args.backend == "auto":
            return miss("--id needs an explicit --backend", [])
        if args.backend == "local":
            try:
                with open(args.id, encoding="utf-8") as f:
                    return hit("local", args.id, parse_lrc(f.read()), None, False, notes)
            except OSError as e:
                return miss("cannot read %s: %s" % (args.id, e), ["local"])

        text, yrc = "", ""
        if not args.no_cache:
            text = cache_read(args.backend, args.id)
            if args.backend == "netease" and text:
                known, yrc = yrc_cache_read(args.id)
                if not known:
                    text = ""
        cached = bool(text)
        if not text:
            try:
                if args.backend == "lrclib":
                    text = lrclib_by_id(args.id)
                else:
                    text, yrc = netease_fetch(args.id)
            except (urllib.error.URLError, OSError, ValueError) as e:
                return miss("%s: %s" % (args.backend, e), [args.backend])
        lines = netease_lines(text, yrc, args.words) if args.backend == "netease" else parse_lrc(text)
        if not lines:
            return miss("that version has no synced lyrics \u2014 try another",
                        [args.backend])
        if track["title"]:
            index_put(track, args.backend, args.id, yrc_has_words(yrc))
        return hit(args.backend, args.id, lines, None, cached, notes, index_offset(track))

    if not track["title"]:
        return miss("no title", [])

    # Candidate search for the picker.
    if args.search:
        cands = gather_candidates(track, args.backend, args.words)
        emit({"ok": bool(cands), "candidates": cands, "lines": [], "notes": notes,
              "artist": TRACK["artist"], "title": TRACK["title"]})

    # A previous fetch recorded which backend/id served this track, so the
    # cached .lrc can be found without repeating the search.
    if not args.no_cache:
        known = index_load().get(track_key(track))
        if known and args.backend in ("auto", known.get("backend")):
            text = cache_read(known.get("backend"), known.get("id"))
            lines = parse_lrc(text) if text else []
            if lines:
                # A netease entry from before word timings: its own yrc may do.
                if args.words and known.get("backend") == "netease" and known.get("hasWords") is None:
                    try:
                        text, yrc = netease_cached(known["id"])
                    except (urllib.error.URLError, OSError, ValueError) as e:
                        yrc = ""
                        notes.append("netease: %s" % e)
                    if yrc_has_words(yrc):
                        index_put(track, "netease", known["id"], True)
                        return hit("netease", known["id"], word_lines(yrc, text), None, True,
                                   notes, index_offset(track))
                # Hunt once per track for word timings, remembering a miss too.
                if args.words and args.backend == "auto" and known.get("hasWords") is None:
                    hit(known["backend"], known["id"], lines, None, True, notes,
                        index_offset(track), pending=True)
                    try:
                        res = hunt_words(track)
                    except (urllib.error.URLError, OSError, ValueError) as e:
                        res = None
                        notes.append("netease: %s" % e)
                    if res:
                        index_put(track, "netease", res["id"], True)
                        return hit("netease", res["id"], word_lines(res["yrc"], res["lrc"]),
                                   res["candidate"], False, notes, index_offset(track))
                    index_put(track, known["backend"], known["id"], False)
                    sys.exit(0)
                if args.words and known.get("backend") == "netease":
                    try:
                        text, yrc = netease_cached(known["id"])
                    except (urllib.error.URLError, OSError, ValueError) as e:
                        yrc = ""
                        notes.append("netease: %s" % e)
                    lines = netease_lines(text, yrc, True) or lines
                return hit(known["backend"], known["id"], lines, None, True, notes,
                           index_offset(track))

    order = (["local", "lrclib", "netease"] if args.backend == "auto" else [args.backend])
    tried = []

    for backend in order:
        tried.append(backend)

        if backend == "local":
            path = try_local(track, dirs)
            if not path:
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    lines = parse_lrc(f.read())
            except OSError as e:
                notes.append("local: %s" % e)
                continue
            if lines:
                return hit("local", path, lines, None, False, notes, index_offset(track))
            continue

        try:
            res = try_lrclib(track) if backend == "lrclib" else try_netease(track, args.words)
        except (urllib.error.URLError, OSError, ValueError) as e:
            notes.append("%s: %s" % (backend, e))
            continue

        if not res:
            continue
        if backend == "lrclib":
            lines = parse_lrc(res["lrc"])
            if lines and args.words:
                # lrclib is line-level only; a worded netease match wins over it.
                index_put(track, backend, res["id"])
                hit(backend, res["id"], lines, res["candidate"], False, notes,
                    index_offset(track), pending=True)
                try:
                    up = hunt_words(track)
                except (urllib.error.URLError, OSError, ValueError) as e:
                    up = None
                    notes.append("netease: %s" % e)
                if up:
                    index_put(track, "netease", up["id"], True)
                    return hit("netease", up["id"], word_lines(up["yrc"], up["lrc"]),
                               up["candidate"], False, notes, index_offset(track))
                index_put(track, backend, res["id"], False)
                sys.exit(0)
            has_words = None
        else:
            lines = netease_lines(res["lrc"], res["yrc"], args.words)
            has_words = yrc_has_words(res["yrc"])
        if lines:
            index_put(track, backend, res["id"], has_words)
            return hit(backend, res["id"], lines, res["candidate"], False, notes,
                       index_offset(track))

    return miss("no lyrics found", tried, gather_candidates(track, "auto", args.words))


if __name__ == "__main__":
    main()
