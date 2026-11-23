"""areas (docs/areas.md): the matcher, the selection, the closest enclosing area, area-level reuse and the report, decided from PATHS ONLY (no source is read, no import traced, nothing run).
Run by lib/areas.sh (areas_run); the areas file is read with the json module. Exit 2 with the reason on a malformed file."""
import sys, re, json, itertools

class Refuse(Exception):
    pass

NAME = re.compile(r"[a-z0-9][a-z0-9_-]*")

def shape(s, what, literal):
    if not isinstance(s, str) or not s:
        raise Refuse("%s must be a non-empty string" % what)
    for c in "[]\\{}" + ("*?" if literal else ""):
        if c in s:
            raise Refuse("%s '%s' contains '%s'%s" % (what, s, c, "" if literal else " (the glob language is * and ? only)"))
    if s.startswith("/") or s.startswith("./") or s.endswith("/") or "//" in s or ".." in s.split("/"):
        raise Refuse("%s '%s' must be relative, with no leading ./, no trailing /, no // and no .. segment" % (what, s))
    return s

def rx(g):
    return re.compile("".join(".*" if c == "*" else "." if c == "?" else re.escape(c) for c in g), re.S)

def gdir(g):
    d = []
    for seg in g.split("/")[:-1]:
        if "*" in seg or "?" in seg:
            break
        d.append(seg)
    return "/".join(d)

class Area:
    def __init__(s, name, paths, excl=(), steps=(), nodel=False, carve=()):
        s.name, s.steps, s.nodel = name, list(steps), nodel
        s.paths, s.excl, s.carve = [rx(g) for g in paths], [rx(g) for g in excl], [rx(g) for g in carve]
        s.dirs = [gdir(g) for g in paths]
    def hit(s, rs, p):
        return any(r.fullmatch(p) for r in rs)
    def owns(s, p, st="A"):
        if st == "D" and s.nodel:
            return False
        if st != "D" and s.hit(s.carve, p):
            return False
        return s.hit(s.paths, p) and not s.hit(s.excl, p)
    def depth(s, p):
        if s.hit(s.excl, p):
            return None
        ds = [len(d) for d in s.dirs if d and p.startswith(d + "/")]
        return max(ds) if ds else None

def pairs(items):
    d = {}
    for k, v in items:
        if k in d:
            raise Refuse("duplicate key '%s'" % k)
        d[k] = v
    return d

def load(path):
    try:
        with open(path, "rb") as f:
            raw = f.read().decode("utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise Refuse("cannot read %s: %s" % (path, e))
    def bad(c):
        raise Refuse("not valid JSON: %s is not a JSON value" % c)
    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad)
    except (ValueError, RecursionError) as e:
        raise Refuse("not valid JSON: %s" % e)

class Areas(list):
    """the areas of a file; gate_areas: the areas a gate-defining change runs (None: every area)"""
    gate_areas = None

def parse(doc):
    if not isinstance(doc, dict):
        raise Refuse("the file must be a JSON object")
    for k in doc:
        if k not in ("version", "areas", "gate_areas"):
            raise Refuse("unknown key '%s'" % k)
    if type(doc.get("version")) is not int or doc["version"] != 1:
        raise Refuse("version must be exactly 1")
    al = doc.get("areas")
    if not isinstance(al, list) or not al:
        raise Refuse("areas must be a non-empty list")
    seen, out = set(), []
    for i, a in enumerate(al):
        where = "area #%d" % (i + 1)
        try:
            if not isinstance(a, dict):
                raise Refuse("not an object")
            n = a.get("name")
            if isinstance(n, str):
                where = "area '%s'" % n
            for k in a:
                if k not in ("name", "paths", "exclude", "steps"):
                    raise Refuse("unknown key '%s'" % k)
            if not isinstance(n, str) or not NAME.fullmatch(n):
                raise Refuse("name must match [a-z0-9][a-z0-9_-]*")
            if n == "inert":
                raise Refuse("the name 'inert' is reserved")
            if n in seen:
                raise Refuse("duplicate name")
            seen.add(n)
            paths, excl = a.get("paths"), a.get("exclude", [])
            if not isinstance(paths, list) or not paths:
                raise Refuse("paths must be a non-empty list of globs")
            if not isinstance(excl, list):
                raise Refuse("exclude must be a list of globs")
            paths = [shape(g, "paths glob", False) for g in paths]
            excl = [shape(g, "exclude glob", False) for g in excl]
            if "steps" not in a or not isinstance(a["steps"], list):
                raise Refuse("steps is required and must be a list ([] for an area with no steps)")
            steps = []
            for j, s in enumerate(a["steps"]):
                if not isinstance(s, dict):
                    raise Refuse("step #%d is not an object" % (j + 1))
                for k in s:
                    if k not in ("run", "cwd"):
                        raise Refuse("step #%d: unknown key '%s'" % (j + 1, k))
                r = s.get("run")
                if not isinstance(r, str) or not r.strip():
                    raise Refuse("step #%d has no run" % (j + 1))
                steps.append((shape(s["cwd"], "step #%d cwd" % (j + 1), True) if "cwd" in s else ".", r))
        except Refuse as e:
            raise Refuse("%s: %s" % (where, e))
        out.append(Area(n, paths, excl, steps))
    out = Areas(out)
    if "gate_areas" in doc:
        ga = doc["gate_areas"]
        if not isinstance(ga, list) or not ga or not all(isinstance(x, str) for x in ga):
            raise Refuse("gate_areas must be a non-empty list of area names")
        for x in ga:
            if x not in seen:
                raise Refuse("gate_areas names '%s', which is not an area" % x)
        if len(set(ga)) != len(ga):
            raise Refuse("gate_areas names an area twice")
        out.gate_areas = list(ga)
    return out

def build(o):
    if o["file"]:
        areas = parse(load(o["file"]))
    else:
        areas = [Area("all", ["*"], steps=[(".", c) for c in (o["gates"], o["test"]) if c], carve=o["inert"])]
    if o["inert"]:
        areas.append(Area("inert", o["inert"], nodel=True))
    return areas

def enclosing(areas, p):
    best, names = -1, []
    for a in areas:
        d = a.depth(p)
        if d is not None and d >= best:
            names = [a.name] if d > best else names + [a.name]
            best = d
    return names

def is_gate(p, prot):
    return p.startswith(".land/") or any(r.fullmatch(p) for r in prot)

def decide(areas, prot, changes, rc):
    full, touched, unmapped, gate = rc, {}, set(), set()
    ga = getattr(areas, "gate_areas", None)
    for c in changes:
        for st, p in ([("D", c[1]), ("A", c[2])] if c[0] == "R" else [c]):
            gd = is_gate(p, prot)
            if gd:
                gate.add(p)
                if ga:   # the file declares which areas a change to what judges runs; the release candidate still runs every area
                    for n in ga:
                        touched.setdefault(n, p)
                else:
                    full = True
            owners = [a.name for a in areas if a.owns(p, st)]
            if not owners and not gd:
                owners = enclosing(areas, p)
                if not owners:
                    unmapped.add(p)
                    full = True
            for n in owners:
                touched.setdefault(n, p)
    return {"touched": touched, "full": full, "unmapped": sorted(unmapped), "gate": sorted(gate)}

def outcome(areas, d, reused=()):
    every = [a.name for a in areas]
    run = [a for a in areas if (d["full"] or a.name in d["touched"]) and a.name not in reused]
    names = [a.name for a in run]
    steps, seen = [], set()
    for a in run:
        for cwd, r in a.steps:
            if (cwd, r) not in seen:
                seen.add((cwd, r))
                steps.append((a.name, cwd, r))
    validation = "tier1" if steps else "reused" if reused else "inert"
    return {"areas": sorted(names), "skipped_areas": sorted(n for n in every if n not in names and n not in reused),
            "reused_areas": sorted(reused), "unmapped": d["unmapped"], "gate_defining": d["gate"], "full_suite": d["full"],
            "steps": steps, "validation": validation}

def explain(areas, d, o, res, changes, rc):
    out = []
    if rc:
        out.append("release candidate: every area runs")
    elif not changes:
        out.append("none: the net change holds no path; nothing to validate")
    for a in areas:
        n = a.name
        if n in res["areas"]:
            out.append("run %s: %s" % (n, "first touched by %s" % d["touched"][n] if n in d["touched"] else "the full suite runs"))
        elif n in res["reused_areas"]:
            out.append("reuse %s: its verdict on the earlier base stands (nothing that moved touches it)" % n)
        else:
            out.append("skip %s: no changed path touches it" % n)
    out += ["unmapped %s: no area owns or encloses it: the full suite runs" % p for p in res["unmapped"]]
    ga = getattr(areas, "gate_areas", None)
    if ga: out += ["gate-defining %s: judges every change: it runs the declared gate areas (%s); the release candidate runs every area" % (p, ", ".join(ga)) for p in res["gate_defining"]]
    else: out += ["gate-defining %s: judges every change: the full suite runs" % p for p in res["gate_defining"]]
    return out

def shown(res):
    return {k: [[c, r] for _, c, r in v] if k == "steps" else v for k, v in res.items() if k != "reused_areas"}

def emit(o, areas, d, res, changes):
    j = lambda v: json.dumps(v, separators=(",", ":"))
    if o["into"]:
        vj = "" if res["validation"] == "tier1" else ',"validation":"%s"' % res["validation"]
        vj += ',"areas":%s,"skipped_areas":%s' % (j(res["areas"]), j(res["skipped_areas"]))
        if res["reused_areas"]:
            vj += ',"reused_areas":%s' % j(res["reused_areas"])
        txt = {"areas": res["areas"], "skipped": res["skipped_areas"], "reused": res["reused_areas"], "unmapped": res["unmapped"],
               "gate": res["gate_defining"], "explain": explain(areas, d, o, res, changes, o["rc"])}
        for k, v in txt.items():
            with open("%s/%s" % (o["into"], k), "w") as f:
                f.write("".join(x + "\n" for x in v))
        with open(o["into"] + "/passed", "w") as f:
            f.write("".join(n + "\n" for n in sorted(set(a.name for a in areas if a.steps and a.name in res["areas"]) | set(res["reused_areas"]))))
        with open(o["into"] + "/validation", "w") as f:
            f.write(res["validation"] + "\n")
        with open(o["into"] + "/vjson", "w") as f:
            f.write(vj + "\n")
        with open(o["into"] + "/steps0", "wb") as f:
            f.write("".join("%s\0%s\0%s\0" % s for s in res["steps"]).encode())

def read_changes(text):
    out = []
    for ln in text.split("\n"):
        if not ln:
            continue
        f = ln.split("\t")
        if len(f) == 1:
            out.append(("M", f[0]))
        elif f[0][:1] in ("R", "C") and len(f) == 3:
            out.append(("R", f[1], f[2]) if f[0][0] == "R" else ("A", f[2]))
        elif f[0][:1] in "AMDT" and len(f) == 2:
            out.append(("M" if f[0][0] == "T" else f[0][0], f[1]))
        else:
            raise Refuse("a changed path is 'STATUS<TAB>path' or 'R<TAB>old<TAB>new' (git diff --name-status), or a bare path: '%s'" % ln)
    return out

def report(areas, prot, tracked):
    owned = {p: [a.name for a in areas if a.owns(p)] for p in tracked}
    pairs_ = {}
    for p, ns in owned.items():
        for pr in itertools.combinations(sorted(ns), 2):
            pairs_.setdefault(pr, []).append(p)
    overlap = [{"areas": list(k), "paths": sorted(v)} for k, v in sorted(pairs_.items())]
    unowned = [{"path": p, "enclosed_by": sorted(enclosing(areas, p))} for p in sorted(tracked) if not owned[p] and not is_gate(p, prot)]
    return {"overlap": overlap, "unowned": unowned, "no_steps": sorted(a.name for a in areas if not a.steps)}

def report_text(r, only):
    out = []
    if only in ("report", "overlap"):
        out += ["overlap %s: %s" % (",".join(x["areas"]), ", ".join(x["paths"])) for x in r["overlap"]]
    if only in ("report", "unmapped"):
        out += ["unowned %s: %s" % (x["path"], "enclosed by " + ",".join(x["enclosed_by"]) if x["enclosed_by"] else "UNMAPPED: every change to it runs the full suite") for x in r["unowned"]]
    if only == "report":
        out += ["no steps: %s" % n for n in r["no_steps"]]
    out.append("areas in overlap: %d" % len({n for x in r["overlap"] for n in x["areas"]}))
    out.append("paths in overlap: %d" % len({p for x in r["overlap"] for p in x["paths"]}))
    out.append("unmapped paths: %d" % len([x for x in r["unowned"] if not x["enclosed_by"]]))
    return "\n".join(out) + "\n"

def options(argv):
    o = {"file": "", "gates": "", "test": "", "inert": [], "protected": [], "rc": False, "into": "", "moved": "", "validated": "", "json": False}
    flags, i = {"--rc": "rc", "--json": "json"}, 0
    while i < len(argv):
        a = argv[i]
        if a in flags:
            o[flags[a]] = True
        elif a in ("--file", "--gates", "--test", "--inert", "--protected", "--into", "--moved", "--validated") and i + 1 < len(argv):
            i += 1
            o[a[2:]] = argv[i].split() if a in ("--inert", "--protected") else argv[i]
        else:
            raise Refuse("usage: land-areas validate|touched|reuse|overlap|unmapped|report [--file F | --gates CMD --test CMD] [--inert GLOBS] [--protected GLOBS] [--rc] [--moved F] [--validated F] [--into DIR] [--json]; bad argument '%s'" % a)
        i += 1
    return o

def main(argv):
    if not argv:
        raise Refuse("usage: land-areas validate|touched|reuse|overlap|unmapped|report|decide ...")
    cmd, o = argv[0], options(argv[1:])
    areas = build(o)
    prot = [rx(g) for g in o["protected"]]
    if cmd == "validate":
        return
    text = sys.stdin.read()
    if cmd in ("overlap", "unmapped", "report"):
        r = report(areas, prot, [p for p in text.split("\n") if p])
        if o["json"]:
            r = {k: v for k, v in r.items() if cmd == "report" or k == ("overlap" if cmd == "overlap" else "unowned")}
            sys.stdout.write(json.dumps(r, separators=(",", ":")) + "\n")
        else:
            sys.stdout.write(report_text(r, cmd))
        return
    if cmd not in ("touched", "reuse", "decide"):
        raise Refuse("unknown command '%s'" % cmd)
    changes = read_changes(text)
    d = decide(areas, prot, changes, o["rc"])
    mine = [a.name for a in areas if a.steps and (d["full"] or a.name in d["touched"])]
    reused = []
    if o["moved"] or cmd == "reuse":
        if not o["moved"]:
            raise Refuse("reuse needs --moved FILE (the changes of the trunk's move)")
        with open(o["moved"]) as f:
            moved = decide(areas, prot, read_changes(f.read()), False)
        ok = None
        if o["validated"]:
            with open(o["validated"]) as f:
                ok = set(f.read().split())
        reused = [n for n in mine if not d["full"] and not moved["full"] and n not in moved["touched"] and (ok is None or n in ok)]
    res = outcome(areas, d, reused)
    if cmd == "reuse":
        sys.stdout.write(json.dumps({"rerun": sorted(n for n in mine if n not in reused), "reused": sorted(reused)}, separators=(",", ":")) + "\n")
    elif cmd == "touched":
        sys.stdout.write(json.dumps(shown(res), separators=(",", ":")) + "\n")
    emit(o, areas, d, res, changes)

try:
    main(sys.argv[1:])
except Refuse as e:
    sys.stderr.write("land-areas: %s\n" % e)
    sys.exit(2)
