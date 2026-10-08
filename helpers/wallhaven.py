#!/usr/bin/env python3
"""wallhaven.cc browser backend for the wallpaper picker. Stdlib only.

Every line on stdout is one JSON object with an `event` key:
    meta | result | thumb | progress | done | error | end

Usage:
    wallhaven.py search [--q Q] [--categories 111] [--purity 100] [--sorting S]
                        [--order desc] [--top-range 1M] [--atleast 2560x1440]
                        [--resolutions R,R] [--ratios R,R] [--colors HEX]
                        [--page N] [--seed S] [--no-thumbs] [--fresh]
    wallhaven.py thumbs ID_OR_URL...
    wallhaven.py get ID [--dest DIR] [--no-thumb]
    wallhaven.py preview ID          # full image into the cache; `get` then renames it
    wallhaven.py status

The API key (NSFW only) is read from settings.json in-process and sent as a
header; it never touches argv, a URL, stdout or settings.json.
"""

import argparse
import concurrent.futures as futures
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://wallhaven.cc/api/v1/"
UA = "quickshell-rice-mj0x0 (https://github.com/mj0x0)"
TIMEOUT = 12
SEARCH_TTL = 300
BUDGET_PER_MINUTE = 40
MAX_WAIT = 6
THUMB_WORKERS = 4


def xdg(var, fallback):
    return os.environ.get(var) or os.path.expanduser(fallback)


PICKER_CACHE = os.path.join(xdg("XDG_CACHE_HOME", "~/.cache"), "quickshell", "wallpaper_picker")
CACHE = os.path.join(PICKER_CACHE, "wallhaven")
SEARCH_CACHE = os.path.join(CACHE, "search")
THUMB_CACHE = os.path.join(CACHE, "thumbs")
FULL_CACHE = os.path.join(CACHE, "full")
BUDGET_FILE = os.path.join(CACHE, "ratelimit.json")
PICKER_THUMBS = os.path.join(PICKER_CACHE, "thumbs")
PICKER_MARKERS = os.path.join(PICKER_CACHE, "colors_markers")
SETTINGS = os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "quickshell", "settings.json")


def emit(event, **kw):
    kw["event"] = event
    sys.stdout.write(json.dumps(kw, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def fail(kind, message, **kw):
    emit("error", kind=kind, message=message, **kw)
    return 1


def expand_home(p):
    s = str(p or "")
    return os.path.join(os.environ.get("HOME", "~"), s[2:]) if s.startswith("~/") else s


# --- settings ---------------------------------------------------------------

def settings_value(cfg, path, fallback):
    cur = cfg
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return fallback
        cur = cur[part]
    return cur


def load_settings():
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def images_dir(cfg):
    return expand_home(settings_value(cfg, "wallpaper.imageDir", "~/Pictures/Wallpapers"))


def download_dir(cfg):
    return expand_home(settings_value(cfg, "wallpaper.wallhaven.dir", "") or "") or images_dir(cfg)


# --- key --------------------------------------------------------------------

def read_key():
    key = ("" + str(settings_value(load_settings(), "wallpaper.wallhaven.apiKey", "") or "")).strip()
    return key or None


def headers(key):
    h = {"User-Agent": UA, "Accept": "application/json"}
    if key:
        h["X-API-Key"] = key
    return h


# --- rate limit budget ------------------------------------------------------

class Budget:
    """Request timestamps shared across processes, so 40/min holds even when the
    picker spawns one helper per page."""

    def __init__(self):
        os.makedirs(CACHE, exist_ok=True)
        self.lock_path = BUDGET_FILE + ".lock"

    def _load(self):
        try:
            with open(BUDGET_FILE, encoding="utf-8") as f:
                d = json.load(f)
            return list(d.get("stamps") or []), float(d.get("blocked_until") or 0)
        except (OSError, ValueError):
            return [], 0.0

    def _save(self, stamps, blocked):
        tmp = BUDGET_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"stamps": stamps, "blocked_until": blocked}, f)
        os.replace(tmp, BUDGET_FILE)

    def _locked(self, fn):
        with open(self.lock_path, "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            try:
                return fn()
            finally:
                fcntl.flock(lk, fcntl.LOCK_UN)

    def status(self):
        stamps, blocked = self._load()
        now = time.time()
        stamps = [s for s in stamps if now - s < 60]
        return {"used": len(stamps), "limit": BUDGET_PER_MINUTE,
                "blocked_for": max(0, int(blocked - now))}

    def acquire(self):
        """Returns seconds to wait before retrying, or 0 when a slot was taken."""
        def step():
            stamps, blocked = self._load()
            now = time.time()
            if blocked > now:
                return blocked - now
            stamps = [s for s in stamps if now - s < 60]
            if len(stamps) >= BUDGET_PER_MINUTE:
                return stamps[0] + 60 - now
            stamps.append(now)
            self._save(stamps, blocked)
            return 0
        return self._locked(step)

    def block(self, seconds):
        def step():
            stamps, _ = self._load()
            self._save(stamps, time.time() + seconds)
        self._locked(step)


BUDGET = Budget()


def api_get(path, params, key):
    """One rate-limited API call. Returns (obj, None) or (None, error-dict)."""
    wait = BUDGET.acquire()
    if wait > MAX_WAIT:
        return None, {"kind": "ratelimit", "message": "Rate limit reached", "retry_after": int(wait) + 1}
    if wait > 0:
        time.sleep(wait)
        BUDGET.acquire()

    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=headers(key))
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            body = r.read().decode("utf-8", "replace")
            remaining = r.headers.get("x-ratelimit-remaining")
            if remaining is not None and remaining.isdigit() and int(remaining) <= 1:
                BUDGET.block(60)
            return json.loads(body), None
    except urllib.error.HTTPError as e:
        if e.code == 429:
            retry = e.headers.get("Retry-After")
            secs = int(retry) if retry and retry.isdigit() else 60
            BUDGET.block(secs)
            return None, {"kind": "ratelimit", "message": "wallhaven asked us to slow down", "retry_after": secs}
        if e.code == 401:
            return None, {"kind": "key", "message": "wallhaven rejected the API key"}
        if e.code == 404:
            return None, {"kind": "notfound", "message": "Not found on wallhaven"}
        return None, {"kind": "http", "message": "wallhaven answered HTTP %d" % e.code}
    except urllib.error.URLError as e:
        return None, {"kind": "offline", "message": "Could not reach wallhaven.cc (%s)" % getattr(e, "reason", e)}
    except (OSError, ValueError) as e:
        return None, {"kind": "http", "message": str(e)}


# --- plain downloads (CDN, not rate limited) --------------------------------

def fetch_file(url, dest, progress=None):
    """Streams url into dest via a .tmp sibling and an atomic rename."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".tmp"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r, open(tmp, "wb") as out:
            total = int(r.headers.get("Content-Length") or 0)
            got = 0
            while True:
                chunk = r.read(256 * 1024)
                if not chunk:
                    break
                out.write(chunk)
                got += len(chunk)
                if progress:
                    progress(got, total)
        os.replace(tmp, dest)
        return None
    except urllib.error.HTTPError as e:
        err = "HTTP %d" % e.code
    except (urllib.error.URLError, OSError) as e:
        err = str(getattr(e, "reason", e))
    try:
        os.remove(tmp)
    except OSError:
        pass
    return err


# --- thumbs -----------------------------------------------------------------

def thumb_url(ident):
    return "https://th.wallhaven.cc/small/%s/%s.jpg" % (ident[:2], ident)


def thumb_path(ident, url):
    ext = os.path.splitext(urllib.parse.urlparse(url).path)[1] or ".jpg"
    return os.path.join(THUMB_CACHE, ident + ext)


def fetch_thumbs(pairs):
    """pairs: [(id, url)]. Emits a thumb event as each one lands."""
    todo = [(i, u, thumb_path(i, u)) for i, u in pairs]
    todo = [(i, u, p) for i, u, p in todo if not os.path.isfile(p)]
    if not todo:
        return
    with futures.ThreadPoolExecutor(max_workers=THUMB_WORKERS) as pool:
        jobs = {pool.submit(fetch_file, u, p): (i, p) for i, u, p in todo}
        for job in futures.as_completed(jobs):
            ident, path = jobs[job]
            err = job.result()
            if err:
                emit("thumb", id=ident, file="", error=err)
            else:
                emit("thumb", id=ident, file=path)


def prune():
    now = time.time()
    try:
        for fn in os.listdir(SEARCH_CACHE):
            p = os.path.join(SEARCH_CACHE, fn)
            if now - os.path.getmtime(p) > 3600:
                os.remove(p)
    except OSError:
        pass
    try:
        for fn in os.listdir(THUMB_CACHE):
            p = os.path.join(THUMB_CACHE, fn)
            if fn.endswith(".tmp") and now - os.path.getmtime(p) > 600:
                os.remove(p)
        files = [os.path.join(THUMB_CACHE, f) for f in os.listdir(THUMB_CACHE) if not f.endswith(".tmp")]
        if len(files) > 600:
            files.sort(key=os.path.getmtime)
            for p in files[:len(files) - 400]:
                os.remove(p)
    except OSError:
        pass


# --- search -----------------------------------------------------------------

SEARCH_KEYS = ("q", "categories", "purity", "sorting", "order", "topRange",
               "atleast", "resolutions", "ratios", "colors", "page", "seed")


def search_params(args, key):
    p = {}
    for k in SEARCH_KEYS:
        v = getattr(args, k if k != "topRange" else "top_range", None)
        if v not in (None, ""):
            p[k] = str(v)
    purity = (p.get("purity") or "100").ljust(3, "0")[:3]
    forced = False
    if not key and purity[2] == "1":
        purity = purity[:2] + "0"
        forced = True
    if purity == "000":
        purity = "100"
    p["purity"] = purity
    if "categories" in p and set(p["categories"]) <= {"0"}:
        p["categories"] = "111"
    return p, forced


def cache_file(params):
    digest = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()
    return os.path.join(SEARCH_CACHE, digest + ".json")


def slim(r):
    thumb = (r.get("thumbs") or {}).get("small") or thumb_url(r.get("id", ""))
    local = thumb_path(r["id"], thumb)
    return {
        "id": r.get("id"),
        "url": r.get("url"),
        "path": r.get("path"),
        "thumb_url": thumb,
        "thumb": local if os.path.isfile(local) else "",
        "resolution": r.get("resolution"),
        "dimension_x": r.get("dimension_x"),
        "dimension_y": r.get("dimension_y"),
        "ratio": r.get("ratio"),
        "file_size": r.get("file_size"),
        "file_type": r.get("file_type"),
        "colors": r.get("colors") or [],
        "purity": r.get("purity"),
        "category": r.get("category"),
    }


def cmd_search(args):
    key = read_key()
    params, forced = search_params(args, key)
    os.makedirs(SEARCH_CACHE, exist_ok=True)
    cf = cache_file(params)
    obj = None
    cached = False
    if not args.fresh and os.path.isfile(cf) and time.time() - os.path.getmtime(cf) < SEARCH_TTL:
        try:
            with open(cf, encoding="utf-8") as f:
                obj = json.load(f)
            cached = True
        except (OSError, ValueError):
            obj = None
    if obj is None:
        obj, err = api_get("search", params, key)
        if err:
            return fail(**err)
        try:
            tmp = cf + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(obj, f)
            os.replace(tmp, cf)
        except OSError:
            pass

    dl_dir = download_dir(load_settings())

    def local_file(r):
        """The file `get` would write for this result, if it is already there."""
        base = os.path.basename(urllib.parse.urlparse(r["path"] or "").path)
        stem, ext = os.path.splitext(base)
        stem = stem or ("wallhaven-" + r["id"])
        for e in (ext or ".jpg", ".png", ".jpg"):
            p = os.path.join(dl_dir, stem + e)
            if os.path.isfile(p):
                return p
        return ""

    meta = obj.get("meta") or {}
    rows = [slim(r) for r in obj.get("data") or [] if r.get("id")]
    for r in rows:
        r["local"] = local_file(r)
        cached = os.path.join(FULL_CACHE, file_name(r["id"], r["path"]))
        r["full"] = cached if os.path.isfile(cached) else ""
    emit("meta", page=meta.get("current_page", 1), last_page=meta.get("last_page", 1),
         per_page=meta.get("per_page", 24), total=meta.get("total", len(rows)),
         seed=meta.get("seed") or "", key=bool(key), purity_forced=forced,
         purity=params["purity"], cached=cached, count=len(rows))
    for r in rows:
        emit("result", **r)
    if not args.no_thumbs:
        fetch_thumbs([(r["id"], r["thumb_url"]) for r in rows if not r["thumb"]])
    prune()
    emit("end")
    return 0


def cmd_thumbs(args):
    pairs = []
    for item in args.items:
        if "://" in item:
            ident = os.path.splitext(os.path.basename(urllib.parse.urlparse(item).path))[0]
            pairs.append((ident, item))
        else:
            pairs.append((item, thumb_url(item)))
    fetch_thumbs(pairs)
    emit("end")
    return 0


# --- get --------------------------------------------------------------------

def cached_result(ident):
    try:
        names = sorted(os.listdir(SEARCH_CACHE), key=lambda f: -os.path.getmtime(os.path.join(SEARCH_CACHE, f)))
    except OSError:
        return None
    for fn in names:
        try:
            with open(os.path.join(SEARCH_CACHE, fn), encoding="utf-8") as f:
                for r in json.load(f).get("data") or []:
                    if r.get("id") == ident:
                        return r
        except (OSError, ValueError):
            continue
    return None


def writable_dir(path):
    try:
        os.makedirs(path, exist_ok=True)
    except OSError:
        return False
    return os.access(path, os.W_OK)


def is_webp(path):
    try:
        with open(path, "rb") as f:
            head = f.read(12)
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    except OSError:
        return False


def run_quiet(cmd, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def build_picker_thumb(src):
    """The x420 thumbnail plus colour marker the local tabs read, stamped with the
    source mtime like wallpaper-thumbs.sh does."""
    name = os.path.basename(src)
    thumb = os.path.join(PICKER_THUMBS, name)
    os.makedirs(PICKER_THUMBS, exist_ok=True)
    os.makedirs(PICKER_MARKERS, exist_ok=True)
    env = dict(os.environ, MAGICK_THREAD_LIMIT="1")
    try:
        subprocess.run(["magick", src, "-resize", "x420", "-quality", "70", thumb],
                       capture_output=True, timeout=60, env=env, check=True)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return ""
    try:
        st = os.stat(src)
        os.utime(thumb, (st.st_atime, st.st_mtime))
    except OSError:
        pass
    manifest = os.path.join(PICKER_THUMBS, ".manifest")
    if os.path.isfile(manifest):
        try:
            with open(manifest, encoding="utf-8") as f:
                listed = name in f.read().splitlines()
            if not listed:
                with open(manifest, "a", encoding="utf-8") as f:
                    f.write(name + "\n")
        except OSError:
            pass
    try:
        r = subprocess.run(["magick", thumb, "-modulate", "100,200", "-resize", "1x1^", "-gravity",
                            "center", "-extent", "1x1", "-depth", "8", "-format", "%[hex:p{0,0}]", "info:-"],
                           capture_output=True, text=True, timeout=30, env=env)
        hexcode = "".join(c for c in r.stdout.strip() if c in "0123456789abcdefABCDEF")[:6]
        if len(hexcode) == 6:
            open(os.path.join(PICKER_MARKERS, "%s_HEX_%s" % (name, hexcode.upper())), "a").close()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return thumb


def resolve(ident):
    """(info, path, error) for one id: the cached search row, else one API call."""
    info = cached_result(ident)
    if info is None:
        obj, err = api_get("w/" + urllib.parse.quote(ident), {}, read_key())
        if err:
            return None, None, err
        info = obj.get("data") or {}
    path = info.get("path")
    if not path:
        return None, None, {"kind": "notfound", "message": "wallhaven has no file for %s" % ident}
    return info, path, None


def file_name(ident, path):
    name = os.path.basename(urllib.parse.urlparse(path or "").path) or ("wallhaven-%s.jpg" % ident)
    return "".join(c for c in name if c.isalnum() or c in "-_.") or ("wallhaven-%s.jpg" % ident)


def progress_printer(ident):
    last = [0.0]

    def progress(got, total):
        now = time.time()
        if now - last[0] >= 0.2 or got == total:
            last[0] = now
            emit("progress", id=ident, received=got, total=total,
                 pct=int(got * 100 / total) if total else 0)
    return progress


def prune_full(keep=12):
    try:
        files = [os.path.join(FULL_CACHE, f) for f in os.listdir(FULL_CACHE) if not f.endswith(".tmp")]
        files.sort(key=os.path.getmtime)
        for p in files[:max(0, len(files) - keep)]:
            os.remove(p)
    except OSError:
        pass


def cmd_preview(args):
    """Full image into the cache, so a later `get` is a rename rather than a second download."""
    ident = args.id.strip()
    info, path, err = resolve(ident)
    if err:
        return fail(**err)
    os.makedirs(FULL_CACHE, exist_ok=True)
    dest = os.path.join(FULL_CACHE, file_name(ident, path))
    if not os.path.isfile(dest):
        err = fetch_file(path, dest, progress_printer(ident))
        if err:
            return fail("download", "Preview failed: %s" % err, id=ident)
    try:
        os.utime(dest, None)
    except OSError:
        pass
    prune_full()
    emit("preview", id=ident, file=dest, size=os.path.getsize(dest), url=info.get("url") or "")
    return 0


def cmd_get(args):
    ident = args.id.strip()
    cfg = load_settings()
    info, path, err = resolve(ident)
    if err:
        return fail(**err)

    dest_dir = expand_home(args.dest) if args.dest else download_dir(cfg)
    fallback = False
    if not writable_dir(dest_dir):
        dest_dir, fallback = images_dir(cfg), True
        if not writable_dir(dest_dir):
            return fail("disk", "Cannot write to %s" % dest_dir)

    name = file_name(ident, path)
    dest = os.path.join(dest_dir, name)
    png = os.path.splitext(dest)[0] + ".png"
    existed = os.path.isfile(dest) or os.path.isfile(png)
    if os.path.isfile(png) and not os.path.isfile(dest):
        dest = png

    if not existed:
        cached = os.path.join(FULL_CACHE, name)
        if os.path.isfile(cached):
            try:
                shutil.move(cached, dest)
            except OSError:
                cached = ""
        if not os.path.isfile(dest):
            err = fetch_file(path, dest, progress_printer(ident))
            if err:
                return fail("download", "Download failed: %s" % err, id=ident)
        if is_webp(dest):
            if run_quiet(["magick", dest, png]):
                os.remove(dest)
                dest = png
            else:
                return fail("convert", "Could not convert the webp", id=ident, file=dest)

    in_picker = os.path.realpath(dest_dir) == os.path.realpath(images_dir(cfg))
    thumb = ""
    if in_picker and not args.no_thumb:
        thumb = build_picker_thumb(dest)
    size = os.path.getsize(dest) if os.path.isfile(dest) else 0
    emit("done", id=ident, file=dest, thumb=thumb, size=size, existed=existed,
         in_picker=in_picker, dest_fallback=fallback, url=info.get("url") or "")
    return 0


def cmd_status(_args):
    st = BUDGET.status()
    cfg = load_settings()
    emit("status", key=bool(read_key()), download_dir=download_dir(cfg),
         images_dir=images_dir(cfg), magick=bool(shutil.which("magick")), **st)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("search")
    s.add_argument("--q", default="")
    s.add_argument("--categories", default="111")
    s.add_argument("--purity", default="100")
    s.add_argument("--sorting", default="date_added")
    s.add_argument("--order", default="desc")
    s.add_argument("--top-range", default="")
    s.add_argument("--atleast", default="")
    s.add_argument("--resolutions", default="")
    s.add_argument("--ratios", default="")
    s.add_argument("--colors", default="")
    s.add_argument("--page", type=int, default=1)
    s.add_argument("--seed", default="")
    s.add_argument("--no-thumbs", action="store_true")
    s.add_argument("--fresh", action="store_true", help="ignore the response cache")
    s.set_defaults(fn=cmd_search)

    t = sub.add_parser("thumbs")
    t.add_argument("items", nargs="+", metavar="ID_OR_URL")
    t.set_defaults(fn=cmd_thumbs)

    g = sub.add_parser("get")
    g.add_argument("id")
    g.add_argument("--dest", default="", help="folder; default from settings.json")
    g.add_argument("--no-thumb", action="store_true", help="skip the picker thumbnail")
    g.set_defaults(fn=cmd_get)

    v = sub.add_parser("preview")
    v.add_argument("id")
    v.set_defaults(fn=cmd_preview)

    sub.add_parser("status").set_defaults(fn=cmd_status)

    args = ap.parse_args()
    try:
        return args.fn(args)
    except KeyboardInterrupt:
        return 130
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0


if __name__ == "__main__":
    sys.exit(main())
