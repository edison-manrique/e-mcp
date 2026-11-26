"""Regression tests for the mcp-ml MCP worker (stdio / NDJSON).

Run from anywhere:
    python tests/mcp.py

Covers the bugs fixed in the audit: protocol echo, duplicate tools,
non-finite numbers in JSON, buffer overflows, notifications, DMD rank=0
crash, input validation, basis validation, >64KB messages and relative
rank/tolerance in SVD/pinv.
"""
import json
import math
import pathlib
import subprocess
import sys
import tempfile

EXE = pathlib.Path(__file__).resolve().parent.parent / "zig-out" / "bin" / "mcp-ml.exe"
TMP = pathlib.Path(tempfile.gettempdir()) / "opencode" / "mcp-ml-tests"
TMP.mkdir(parents=True, exist_ok=True)

PASS = 0
FAIL = 0


def run(msgs, raw=None):
    if raw is None:
        raw = "".join(json.dumps(m) + "\n" for m in msgs)
    p = subprocess.run(
        [str(EXE)],
        input=raw.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


def rpc(i, method, params=None):
    m = {"jsonrpc": "2.0", "id": i, "method": method}
    if params is not None:
        m["params"] = params
    return m


def call(name, args, i=1):
    return rpc(i, "tools/call", {"name": name, "arguments": args})


def result(out):
    obj = json.loads(out.strip())
    assert "error" not in obj, obj
    return obj["result"]


def text(out):
    return result(out)["content"][0]["text"]


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("PASS:", name)
    else:
        FAIL += 1
        print("FAIL:", name, detail)


def csv(name, rows):
    p = TMP / name
    p.write_text("\n".join(",".join(repr(v) for v in row) for row in rows), encoding="ascii")
    return str(p)


def approx(a, b, tol=1e-6):
    return abs(a - b) <= tol


# ---------------------------------------------------------------- fixtures
lin = csv("lin.csv", [[1, 3], [2, 5], [3, 7], [4, 9], [5, 11]])
mat = csv("mat.csv", [[1, 2], [3, 4], [5, 6]])
wide = csv("wide.csv", [[1, 2, 3], [4, 5, 6]])
snap = csv("dmd.csv", [[math.sin(0.2 * k + j) for k in range(10)] for j in range(2)])
neg = csv("neg.csv", [[1, -0.5, 0.25, -0.125, 0.0625]])
dec = csv("dec.csv", [[1, 0.5, 0.25, 0.125, 0.0625]])
koop = csv("koop.csv", [[x, 2 * x] for x in range(6)])
pde = csv("pde.csv", [[math.sin(0.1 * i + j) for j in range(6)] for i in range(6)])
scaled = csv("scaled.csv", [[1e6, 0], [0, 1e6], [0, 0]])

# ---------------------------------------------------------------- protocol
rc, out, err = run([rpc(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {}})])
check("initialize echoes protocolVersion", result(out)["protocolVersion"] == "2025-06-18", out)

rc, out, err = run([rpc(1, "initialize", {})])
check("initialize fallback version", result(out)["protocolVersion"] == "2024-11-05", out)

rc, out, err = run([rpc(2, "ping")])
check("ping", result(out) == {}, out)

rc, out, err = run([{"jsonrpc": "2.0", "id": None, "method": "ping"}])
check("explicit id:null responds", json.loads(out)["id"] is None and "result" in json.loads(out), out)

rc, out, err = run([rpc(3, "tools/list")])
tools = result(out)["tools"]
names = [t["name"] for t in tools]
check("tools/list has no duplicates", len(names) == len(set(names)), names)
check("tools/list size", len(names) == 12, names)
check(
    "tools/list schemas",
    all(t.get("inputSchema", {}).get("type") == "object" for t in tools),
    names,
)

rc, out, err = run([{"jsonrpc": "2.0", "method": "foo/bar"}])
check("unknown notification is silent", out == "", out)

rc, out, err = run([rpc(4, "nope")])
check("method not found with id", json.loads(out)["error"]["code"] == -32601, out)

rc, out, err = run(None, raw="{no es json}\n")
check("parse error", json.loads(out)["error"]["code"] == -32700, out)
check("parse error id null", json.loads(out)["id"] is None, out)

rc, out, err = run([call("zzz", {})])
check("unknown tool", result(out).get("isError") is True, out)

# ---------------------------------------------------------------- help
help_ops = ""
for topic in ("all", "ops", "ejemplos"):
    rc, out, err = run([call("ml_help", {"topic": topic})])
    check(f"ml_help {topic}", len(text(out)) > 100 and "mcp-ml" in text(out), out)
    if topic == "ops":
        help_ops = text(out)

rc, out, err = run([call("ml_help", {"topic": "foo"})])
check("ml_help invalid topic", result(out).get("isError") is True, out)
check("ml_help lists real tool names", "sindy" in help_ops and "ml_sindy" not in help_ops, help_ops)

# ---------------------------------------------------------------- sequence
rc, out, err = run([call("sequence", {"values": "0,1,4,9,16,25"})])
seq = json.loads(text(out))
check("sequence predicts", approx(seq["next"], 36, 0.05), seq)

rc, out, err = run([call("sequence", {"values": "nan,nan,nan,nan,nan,nan"})])
check("sequence NaN -> null (valid JSON)", json.loads(text(out))["next"] is None, out)

rc, out, err = run([call("sequence", {"values": "1e100,2e100,3e100,4e100"})])
check("sequence huge number", json.loads(text(out))["samples"] == 4, out)

rc, out, err = run([call("sequence", {"values": "5,5,5,5,5,5"})])
check("sequence constant", json.loads(text(out))["next"] == 5, out)

big = ",".join(str(math.sin(i / 10.0)) for i in range(20000))
rc, out, err = run([call("sequence", {"values": big})])
check("sequence >64KB message", json.loads(text(out))["samples"] == 20000, out[:200])

# ---------------------------------------------------------------- svd / pinv
rc, out, err = run([call("svd", {"data": mat})])
svd = json.loads(text(out))
check("svd basic", svd["m"] == 3 and svd["n"] == 2 and len(svd["singular_values"]) == 2, svd)

rc, out, err = run([call("svd", {"data": wide})])
check("svd wide rejected", result(out).get("isError") is True and "MatrizAncha" in text(out), out)

rc, out, err = run([call("svd", {"data": scaled})])
check("svd relative rank", json.loads(text(out))["rank"] == 2, out)

rc, out, err = run([call("pinv", {"data": mat})])
pinv = json.loads(text(out))
check("pinv m>=n", pinv["rows"] == 2 and pinv["cols"] == 3, pinv)

rc, out, err = run([call("pinv", {"data": wide})])
pinv = json.loads(text(out))
check("pinv m<n", pinv["rows"] == 3 and pinv["cols"] == 2, pinv)
check("pinv m<n values", approx(pinv["data"][0], -0.9444444444444449, 1e-9), pinv)

# ---------------------------------------------------------------- dmd
rc, out, err = run([call("dmd", {"data": snap, "dt": 0.1, "rank": 2})])
dmd = json.loads(text(out))
check("dmd basic", "dominant_frequency" in dmd and dmd["modes"] >= 1, dmd)

rc, out, err = run([call("dmd", {"data": snap, "rank": 0})])
check("dmd rank=0 does not crash", rc == 0 and result(out).get("isError") is True, out)
check("dmd rank=0 message", "rank" in text(out), out)

rc, out, err = run([call("dmd", {"data": snap, "dt": 0})])
check("dmd dt=0 rejected", result(out).get("isError") is True, out)

rc, out, err = run([call("dmd", {"data": neg, "dt": 1, "rank": 1})])
d = json.loads(text(out))
check("dmd negative eigenvalue growth", approx(d["growth_rate"], math.log(0.5)), d)
check("dmd negative eigenvalue frequency=pi", approx(d["dominant_frequency"], math.pi), d)

rc, out, err = run([call("dmd", {"data": dec, "dt": 0.5, "rank": 1})])
d = json.loads(text(out))
check("dmd decay growth", approx(d["growth_rate"], math.log(0.5) / 0.5), d)

# ---------------------------------------------------------------- koopman
rc, out, err = run([call("koopman", {"data": koop})])
k = json.loads(text(out))
check("koopman basic", k["state_dim"] == 1 and k["basis"] == "poly2", k)

rc, out, err = run([call("koopman", {"data": koop, "basis": "poli9"})])
check("koopman invalid basis", result(out).get("isError") is True and "BasisInvalido" in text(out), out)

rc, out, err = run([call("koopman_predict", {"data": koop, "steps": 3, "ridge": 1e-7})])
check("koopman_predict ridge", len(json.loads(text(out))["trajectory"]) == 3, out)

save = str(TMP / "kmodel.json")
rc, out, err = run([call("koopman", {"data": koop, "save": save})])
check("koopman save", pathlib.Path(save).exists(), out)

rc, out, err = run([call("koopman_load_predict", {"path": save, "x0": "0", "steps": 3})])
check("koopman_load_predict", len(json.loads(text(out))["trajectory"]) == 3, out)

# ---------------------------------------------------------------- pdefind / io
rc, out, err = run([call("pdefind", {"data": pde, "dt": 0.1, "dx": 0.5})])
check("pdefind basic", "equation" in json.loads(text(out)), out)

rc, out, err = run([call("pdefind", {"data": pde, "dt": 0, "dx": 0.5})])
check("pdefind dt=0", result(out).get("isError") is True, out)

rc, out, err = run([call("svd", {"data": str(TMP / "no-existe.csv")})])
check("missing file", result(out).get("isError") is True, out)

# ---------------------------------------------------------------- all JSON valid
cases = [
    ("chaos_lorenz", {}),
    ("sindy", {"data": lin}),
    ("svd", {"data": mat}),
    ("pinv", {"data": mat}),
    ("dmd", {"data": snap, "rank": 2}),
    ("koopman", {"data": koop}),
    ("koopman_predict", {"data": koop, "steps": 2}),
    ("pdefind", {"data": pde, "dt": 0.1, "dx": 0.5}),
]
ok = True
bad = []
for name, args in cases:
    rc, out, err = run([call(name, args)])
    try:
        r = result(out)
        if not r.get("isError"):
            json.loads(r["content"][0]["text"])
    except Exception as exc:  # noqa: BLE001
        ok = False
        bad.append((name, str(exc)))
check("all tool payloads are valid JSON", ok, bad)

print()
print("PASS=%d FAIL=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
