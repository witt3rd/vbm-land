import json, os, subprocess, sys, tempfile
BIN = sys.argv[1]; vec = sys.argv[2]; env = dict(os.environ)
d = json.load(open(vec)); bad = []; n = 0
def run(args, stdin, **kw):
    return subprocess.run([BIN] + args, input=stdin, capture_output=True, text=True, env=env, **kw)
def lines(ch):
    return "".join(("R\t%s\t%s\n" % (c[1], c[2])) if c[0] == "R" else "%s\t%s\n" % (c[0], c[1]) for c in ch)
with tempfile.TemporaryDirectory() as t:
    for c in d["cases"]:
        i, k, e = c["input"], c["kind"], c["expect"]
        opts = []
        if "areas_file" in i:
            f = os.path.join(t, "areas.json"); json.dump(i["areas_file"], open(f, "w")); opts = ["--file", f]
        else:
            L = i["legacy"]; opts = ["--gates", L.get("LAND_GATES_CMD", ""), "--test", L.get("LAND_TEST_CMD", "")]
            if L.get("LAND_INERT"): i = dict(i, land_inert=L["LAND_INERT"])
            if L.get("LAND_PROTECTED"): i = dict(i, protected=L["LAND_PROTECTED"])
        if i.get("land_inert"): opts += ["--inert", " ".join(i["land_inert"])]
        if i.get("protected"): opts += ["--protected", " ".join(i["protected"])]
        env["CASE_FACTS"] = json.dumps(i.get("facts", {}))
        if k == "validate":
            r = run(["validate"] + opts, ""); got = {"valid": r.returncode == 0}
            if r.returncode not in (0, 2) or (r.returncode == 2 and not r.stderr.strip()): got = "exit %d, reason: %r" % (r.returncode, r.stderr)
        elif k == "decide":
            r = run(["touched"] + (["--rc"] if i.get("release_candidate") else []) + opts, lines(i["changes"]))
            got = json.loads(r.stdout) if r.returncode == 0 else r.stderr
        elif k == "reuse":
            mv = os.path.join(t, "moved"); open(mv, "w").write(lines(i["moved"]))
            r = run(["reuse", "--moved", mv] + opts, lines(i["mine"]))
            got = json.loads(r.stdout) if r.returncode == 0 else r.stderr
        else:
            r = run(["report", "--json"] + opts, "".join(p + "\n" for p in i["tracked"]))
            got = json.loads(r.stdout) if r.returncode == 0 else r.stderr
        n += 1
        if got != e: bad.append((c["id"], got, e))
for b in bad: print("FAIL %s\n  got  %s\n  want %s" % b)
print("%d cases, %d failed" % (n, len(bad)))
sys.exit(1 if bad else 0)
