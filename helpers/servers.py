#!/usr/bin/env python3
"""Self-hosted servers on this machine, for Network -> Servers. Stdlib only.

    servers.py list                        {"servers": [...]} on stdout, always exit 0
    servers.py stop|start <kind> <id>      kind is docker|user|system
    servers.py --dry-run stop|start ...    print the call it would make, change nothing

Actions print {"ok": bool} and set the exit code; failures also go to stderr.

Sources merge, first claim on a port wins: docker ps, the units named in
settings.json servers.units, then every unit that owns a listening socket. `ss
--cgroup` names that unit even for a root-owned socket, which `ss -p` will not;
the displayed name is the unit's own Description, never invented here.

A unit seen once is remembered, so a service that is stopped - and therefore
listening on nothing - stays listed and can be started again. "ports" may
legitimately be empty, and portSource says where a port came from.

canStop means this row can be stopped or started from here at all: listening
processes we cannot tie to a unit are reported as kind "proc" and left alone,
because the cgroup a process sits in names whoever launched it, not what it is -
qbittorrent started from the panel sits in the panel's own unit.
"""

import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time

# The panel polls `list`, so the whole walk is bounded rather than each call.
BUDGET = 8.0
deadline = None

SETTINGS = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "quickshell", "settings.json")
CGROUP_ROOT = "/sys/fs/cgroup"
PORT_RANGE = "/proc/sys/net/ipv4/ip_local_port_range"

SYSTEMD_DEST = "org.freedesktop.systemd1"
SYSTEMD_PATH = "/org/freedesktop/systemd1"
SYSTEMD_IFACE = "org.freedesktop.systemd1.Manager"

UNIT_PROPS = ("Description", "LoadState", "ActiveState", "SubState",
              "CanStop", "MainPID", "ControlGroup")
# \Z, not $: $ also matches before a trailing newline. The first character is anchored
# outside the hyphen so an ident can never reach systemctl or gdbus as an option.
UNIT_RE = re.compile(r"^[A-Za-z0-9_.:@][A-Za-z0-9_.:@-]*\.[a-z]+\Z")
CONTAINER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*\Z")
SS_PROC_RE = re.compile(r'\(\("([^"]+)",pid=(\d+)')
CONTAINER_RUNTIMES = re.compile(r"/(docker|containerd|podman)[.-]")

SKIP_UNIT_PREFIXES = ("app-", "dbus-", "xdg-", "gvfs", "plasma-", "kde-", "at-spi",
                      "systemd-", "avahi-")
SKIP_UNITS = {
    "pipewire.service", "pipewire-pulse.service", "wireplumber.service", "dconf.service",
    "gnome-keyring-daemon.service", "obex.service", "dmemcg-booster-user.service",
}


# Desktop apps that listen for their own reasons; not servers.
SKIP_COMMS = {
    "steam", "steamwebhelper", "spotify", "firefox", "chrome", "chromium",
    "thunderbird", "discord", "slack", "telegram-desktop", "element-desktop",
    "code", "dolphin", "obs", "easyeffects", "kdeconnectd", "plasmashell",
    "kwin_wayland", "quickshell", "qs",
}
SKIP_ADDRS = ("127.0.0.53", "127.0.0.54")


def run(argv, timeout=4):
    if deadline is not None:
        left = deadline - time.monotonic()
        if left <= 0:
            return None
        timeout = min(timeout, left)
    try:
        res = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    if res.returncode != 0:
        return None
    return res.stdout.decode("utf-8", "replace")


def setting(path, fallback=None):
    """Dotted lookup into settings.json, matching ShellSettings.value()."""
    try:
        with open(SETTINGS, encoding="utf-8") as fh:
            cur = json.load(fh)
    except (OSError, ValueError):
        return fallback
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return fallback
        cur = cur[part]
    return cur


def ephemeral_range():
    try:
        with open(PORT_RANGE, encoding="utf-8") as fh:
            lo, hi = fh.read().split()[:2]
        return int(lo), int(hi)
    except (OSError, ValueError):
        return 32768, 60999


def as_ports(val):
    """A settings port value: one number, or a list of them. Junk yields nothing."""
    out = []
    for item in val if isinstance(val, (list, tuple)) else [val]:
        try:
            port = int(item)
        except (TypeError, ValueError):
            continue
        if 0 < port < 65536:
            out.append(port)
    return sorted(set(out))


SEEN_PATH = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "quickshell", "servers", "seen.json")
_seen_cache = None


def seen_load():
    """{(scope, unit): [ports]} from earlier runs. Unreadable state is simply empty."""
    global _seen_cache
    if _seen_cache is None:
        _seen_cache = {}
        try:
            with open(SEEN_PATH, encoding="utf-8") as fh:
                raw = json.load(fh)
            for key, ports in (raw or {}).items():
                scope, _, unit = key.partition(":")
                if scope in ("system", "user") and UNIT_RE.match(unit):
                    _seen_cache[(scope, unit)] = as_ports(ports)
        except (OSError, ValueError, AttributeError):
            _seen_cache = {}
    return _seen_cache


def seen_ports(scope, unit):
    return seen_load().get((scope, unit)) or []


def seen_save(entries):
    """Remember every unit we listed, with the ports it was last seen on."""
    keep = dict(seen_load())
    for entry in entries:
        # Only units actually observed listening. A settings pin is not evidence, or
        # unpinning one would never take effect.
        if entry["kind"] not in ("system", "user"):
            continue
        if entry["portSource"] not in ("cgroup", "seen"):
            continue
        ports = entry["ports"] or seen_ports(entry["kind"], entry["id"])
        keep[(entry["kind"], entry["id"])] = ports
    out = {"%s:%s" % (scope, unit): ports for (scope, unit), ports in keep.items()}
    try:
        os.makedirs(os.path.dirname(SEEN_PATH), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(SEEN_PATH), prefix=".seen.")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(out, fh)
        os.replace(tmp, SEEN_PATH)
    except (OSError, ValueError):
        pass


# -- discovery -----------------------------------------------------------------

def cgroup_unit(path):
    """(scope, unit) for a socket's cgroup, or None when it is not a managed service.

    A .scope or an app-*.service is a desktop app systemd happens to supervise — the
    terminal that launched qbittorrent, not a server.
    """
    leaf = path.rstrip("/").rsplit("/", 1)[-1]
    if not leaf.endswith(".service") or leaf.startswith(SKIP_UNIT_PREFIXES):
        return None
    leaf = leaf.replace("\\x2d", "-")
    if leaf in SKIP_UNITS or not UNIT_RE.match(leaf):
        return None
    return ("user" if "/user.slice/" in path else "system", leaf)


def listeners():
    """[(port, addr, cgroup, comm, pid)]. --cgroup names the owning unit even for
    root-owned sockets, which `ss -p` will not do for another user."""
    out = []
    text = run(["ss", "-tlnpH", "--cgroup"], timeout=3)
    if text is None:
        # Older iproute2 without --cgroup: ports still land, attribution does not.
        text = run(["ss", "-tlnpH"], timeout=3) or run(["ss", "-tlnH"], timeout=3)
    for line in (text or "").splitlines():
        fields = line.split()
        if len(fields) < 4 or ":" not in fields[3]:
            continue
        addr, _, port = fields[3].rpartition(":")
        try:
            port = int(port)
        except ValueError:
            continue
        cgroup = ""
        for field in fields:
            if field.startswith("cgroup:"):
                cgroup = field[7:]
                break
        match = SS_PROC_RE.search(line)
        comm = match.group(1) if match else None
        pid = int(match.group(2)) if match else None
        out.append((port, addr, cgroup, comm, pid))
    return out


def unit_servers(heard, claimed, seen):
    """Every unit that owns a listening port, named by its cgroup. No catalog."""
    found = {}
    for port, _addr, cgroup, _comm, _pid in heard:
        if port in claimed or not cgroup:
            continue
        # Container ports belong to docker-proxy; `docker ps` names them properly.
        if CONTAINER_RUNTIMES.search(cgroup):
            continue
        key = cgroup_unit(cgroup)
        if key is None or key in seen:
            continue
        found.setdefault(key, set()).add(port)
    if not found:
        return []

    scoped = {"system": [], "user": []}
    for scope, unit in found:
        scoped[scope].append(unit)
    props = {scope: unit_props(scope, units) for scope, units in scoped.items()}

    entries = []
    for (scope, unit), ports in found.items():
        prop = props[scope].get(unit) or {}
        if prop.get("LoadState") != "loaded":
            continue
        entries.append(unit_entry(scope, unit, prop, sorted(ports), "cgroup"))
        claimed.update(ports)
        seen.add((scope, unit))
    entries.sort(key=lambda e: e["name"].lower())
    return entries


def unit_props(scope, units):
    """{unit: {prop: value}} in one systemctl call, or per unit if they disagree."""
    units = [u for u in units if u and not u.isspace()]
    if not units:
        return {}
    argv = ["systemctl"] + (["--user"] if scope == "user" else []) + ["show"]
    text = run(argv + units + ["-p", ",".join(UNIT_PROPS)])
    # A call that timed out or failed would do the same once per unit; only a record
    # count that disagrees with an answer we did get is worth asking again.
    if text is None:
        return {}
    records = [r for r in text.split("\n\n") if r.strip()]
    if len(records) != len(units):
        if len(units) == 1:
            return {}
        merged = {}
        for unit in units:
            merged.update(unit_props(scope, [unit]))
        return merged
    out = {}
    for unit, record in zip(units, records):
        props = {}
        for line in record.splitlines():
            key, _, val = line.partition("=")
            props[key] = val
        out[unit] = props
    return out


def norm_unit(name):
    return name if "." in name else name + ".service"


def unit_pids(props):
    group = props.get("ControlGroup") or ""
    if not group.startswith("/"):
        return set()
    try:
        with open(CGROUP_ROOT + group + "/cgroup.procs", encoding="utf-8") as fh:
            return {int(line) for line in fh.read().split()}
    except (OSError, ValueError):
        return set()


def unit_state(props):
    if props.get("LoadState") != "loaded":
        return "unknown"
    active = props.get("ActiveState")
    if active in ("active", "reloading"):
        return "running"
    if active == "failed":
        return "failed"
    if active == "inactive":
        return "stopped"
    return "unknown"


def unit_name(unit, props, label=""):
    desc = (props.get("Description") or "").strip()
    if props.get("LoadState") == "loaded" and desc and desc != unit:
        # "Syncthing - Open Source Continuous File Synchronization" is a sentence, not a name.
        for sep in (" - ", " \u2014 ", ": "):
            head = desc.split(sep, 1)[0].strip()
            if len(head) >= 3:
                desc = head
        return desc
    return label or unit.rsplit(".", 1)[0]


def unit_entry(scope, unit, props, ports, source, label=""):
    loaded = props.get("LoadState") == "loaded"
    # The name is prose, so the detail names the unit a stop would actually hit.
    detail = unit if loaded else (props.get("LoadState") or "not-found").replace("-", " ")
    return {
        "id": unit,
        "kind": scope,
        "name": unit_name(unit, props, label),
        "state": unit_state(props),
        "ports": ports,
        "detail": detail,
        "canStop": loaded and props.get("CanStop") == "yes",
        "portSource": source if ports else None,
    }


def host_ports(spec):
    """Published host ports from a `docker ps` Ports string. Unmapped ones are skipped."""
    out = []
    for part in spec.split(","):
        part = part.strip()
        if "->" not in part:
            continue
        host = part.split("->", 1)[0]
        head, _, tail = host.rpartition(":")
        lo, _, hi = (tail if head else host).partition("-")
        try:
            first = int(lo)
            last = int(hi) if hi else first
        except ValueError:
            continue
        if first <= last and last - first < 32:
            out.extend(range(first, last + 1))
    return sorted(set(out))


def bound_ports(names):
    """HostConfig.PortBindings for containers whose Ports column was empty."""
    out = {}
    text = run(["docker", "inspect", "--format",
                "{{.Name}} {{json .HostConfig.PortBindings}}"] + names)
    for line in (text or "").splitlines():
        name, _, raw = line.partition(" ")
        try:
            bindings = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(bindings, dict):
            continue
        ports = []
        for binds in bindings.values():
            for bind in binds or []:
                if isinstance(bind, dict):
                    ports.extend(as_ports(bind.get("HostPort") or []))
        out[name.lstrip("/")] = sorted(set(ports))
    return out


def docker_state(state, status):
    if state in ("running", "restarting"):
        return "running"
    if state == "dead":
        return "failed"
    if state == "exited":
        code = re.search(r"Exited \((\d+)\)", status or "")
        return "failed" if code and code.group(1) != "0" else "stopped"
    if state in ("created", "paused", "removing"):
        return "stopped"
    return "unknown"


def docker_servers():
    """(entries, answered). An empty list from a daemon that answered still counts."""
    text = run(["docker", "ps", "-a", "--format", "{{json .}}"], timeout=5)
    rows = []
    for line in (text or "").splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        name = (row.get("Names") or "").split(",")[0]
        if name:
            rows.append((name, row))

    entries = []
    unmapped = []
    for name, row in rows:
        ports = host_ports(row.get("Ports") or "")
        if not ports:
            unmapped.append(name)
        entries.append({
            "id": name,
            "kind": "docker",
            "name": name,
            "state": docker_state(row.get("State") or "", row.get("Status") or ""),
            "ports": ports,
            "detail": row.get("Status") or "",
            "canStop": True,
            "portSource": "docker" if ports else None,
        })
    if unmapped:
        extra = bound_ports(unmapped)
        for entry in entries:
            ports = extra.get(entry["id"]) or []
            if ports:
                entry["ports"] = ports
                entry["portSource"] = "docker"
    entries.sort(key=lambda e: e["name"].lower())
    return entries, text is not None


def settings_servers(heard, claimed):
    """The units named in servers.units, strongest port evidence first."""
    wanted = setting("servers.units")
    if not isinstance(wanted, (list, tuple)):
        return []

    scoped = {"user": [], "system": []}
    order = []
    for raw in wanted:
        if not isinstance(raw, str):
            continue
        scope, _, unit = raw.partition(":")
        if not unit:
            scope, unit = "system", scope
        scope = scope if scope in scoped else "system"
        unit = norm_unit(unit.strip())
        if not UNIT_RE.match(unit) or (scope, unit) in order:
            continue
        scoped[scope].append(unit)
        order.append((scope, unit))

    props = {scope: unit_props(scope, units) for scope, units in scoped.items()}
    fixed = setting("servers.ports")
    fixed = fixed if isinstance(fixed, dict) else {}

    heard_ports = {p for p, _a, _cg, _c, _pid in heard}
    entries = []
    for scope, unit in order:
        prop = props[scope].get(unit) or {}
        base = unit.rsplit(".", 1)[0]
        # The cgroup names the owner outright, so a pinned unit is matched the same way.
        ports = sorted({p for p, _a, cg, _c, _pid in heard
                        if cg and cgroup_unit(cg) == (scope, unit)})
        source = "cgroup"
        if not ports:
            ports, source = as_ports(fixed.get(unit, fixed.get(base))), "settings"
        if not ports:
            ports, source = sorted(set(seen_ports(scope, unit)) - claimed), "seen"
        entries.append(unit_entry(scope, unit, prop, ports, source))
        # Only a port something is really listening on can speak for its owner.
        claimed.update(p for p in ports if p in heard_ports)
    return entries


# Desktop apps systemd happens to supervise. qbittorrent lives under the autostart scope
# of our own shell, so attributing its port to that unit would offer to stop the shell.
def process_servers(heard, claimed):
    """Listeners we can see but cannot manage: one row per process, ports merged."""
    grouped = {}
    for port, addr, _cg, comm, pid in heard:
        if port in claimed or not comm or not pid:
            continue
        if comm.lower() in SKIP_COMMS or addr.startswith(SKIP_ADDRS):
            continue
        grouped.setdefault(pid, (comm, set()))[1].add(port)
    entries = []
    for pid, (comm, ports) in grouped.items():
        entries.append({
            "id": "pid:%d" % pid,
            "kind": "proc",
            "name": comm,
            "state": "running",
            "ports": sorted(ports),
            "detail": "pid %d, no unit" % pid,
            "canStop": False,
            "portSource": "ss",
        })
        claimed.update(ports)
    entries.sort(key=lambda e: e["name"].lower())
    return entries


def orphan_servers(heard, claimed, docker_answered):
    """Something is listening and we honestly cannot say what. Ephemeral ports excluded.

    Skipped unless docker was enumerated: every published container port then looks
    exactly like this, and a wall of anonymous rows says less than no row at all.
    """
    if not docker_answered:
        return []
    lo, hi = ephemeral_range()
    ports = set()
    for port, addr, _cg, comm, pid in heard:
        if port in claimed or comm or pid or addr.startswith(SKIP_ADDRS):
            continue
        if lo <= port <= hi:
            continue
        ports.add(port)
    return [{
        "id": "port:%d" % port,
        "kind": "port",
        "name": "port %d" % port,
        "state": "running",
        "ports": [port],
        "detail": "owner unknown",
        "canStop": False,
        "portSource": "ss",
    } for port in sorted(ports)]


def remembered_servers(claimed, seen):
    """Units discovered on an earlier run. Nothing listens while they are stopped, so
    without this a service vanishes the moment you stop it and can never be started."""
    scoped = {"system": [], "user": []}
    for scope, unit in seen_load():
        if (scope, unit) not in seen and scope in scoped:
            scoped[scope].append(unit)
    if not any(scoped.values()):
        return []
    props = {scope: unit_props(scope, units) for scope, units in scoped.items()}
    entries = []
    for scope, units in scoped.items():
        for unit in units:
            prop = props[scope].get(unit) or {}
            if prop.get("LoadState") != "loaded":
                continue
            ports = sorted(set(seen_ports(scope, unit)) - claimed)
            entries.append(unit_entry(scope, unit, prop, ports, "seen"))
            seen.add((scope, unit))
    entries.sort(key=lambda e: e["name"].lower())
    return entries


def collect():
    global deadline
    deadline = time.monotonic() + BUDGET
    claimed = set()
    entries = []
    answered = False
    if setting("servers.docker", True) is not False:
        found, answered = docker_servers()
        entries += found
        for entry in found:
            claimed.update(entry["ports"])
    heard = listeners()
    entries += settings_servers(heard, claimed)
    seen = {(e["kind"], e["id"]) for e in entries if e["kind"] in ("system", "user")}
    entries += unit_servers(heard, claimed, seen)
    entries += remembered_servers(claimed, seen)
    entries += process_servers(heard, claimed)
    entries += orphan_servers(heard, claimed, answered)
    seen_save(entries)
    return entries


# -- actions -------------------------------------------------------------------

def action_argv(verb, kind, ident):
    if kind == "docker":
        if not CONTAINER_RE.match(ident):
            return None
        return ["docker", verb, "--", ident]
    if kind in ("user", "system"):
        ident = norm_unit(ident)
        if not UNIT_RE.match(ident):
            return None
    if kind == "user":
        return ["systemctl", "--user", verb, "--", ident]
    if kind == "system":
        # Straight to systemd; polkit asks the session agent. Never sudo or pkexec.
        method = "StopUnit" if verb == "stop" else "StartUnit"
        return ["gdbus", "call", "--system", "--interactive", "--timeout", "120",
                "--dest", SYSTEMD_DEST, "--object-path", SYSTEMD_PATH,
                "--method", "%s.%s" % (SYSTEMD_IFACE, method), "--", ident, "replace"]
    return None


def act(verb, kind, ident, dry):
    argv = action_argv(verb, kind, ident)
    if argv is None:
        print("bad %s target: %s %s" % (verb, kind, ident), file=sys.stderr)
        return 2
    if dry:
        print(" ".join(shlex.quote(arg) for arg in argv))
        return 0
    try:
        res = subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                             timeout=130)
    except (OSError, subprocess.SubprocessError) as exc:
        print(json.dumps({"ok": False}))
        print("%s failed: %s" % (verb, exc), file=sys.stderr)
        return 1
    ok = res.returncode == 0
    print(json.dumps({"ok": ok}))
    if not ok:
        sys.stderr.write(res.stderr.decode("utf-8", "replace"))
    return 0 if ok else 1


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]

    if not args or args[0] == "list":
        print(json.dumps({"servers": collect()}))
        return 0
    if args[0] in ("stop", "start") and len(args) == 3:
        return act(args[0], args[1], args[2], dry)
    print("\n".join(__doc__.splitlines()[:5]), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
