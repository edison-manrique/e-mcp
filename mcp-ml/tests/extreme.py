"""Extreme / adversarial tests for the mcp-ml MCP worker.

Black-box: only talks to the binary over stdio (NDJSON). Verifies the worker
never crashes, never emits invalid JSON, and stays bounded under abuse.

Run:  python tests/extreme.py
"""
import concurrent.futures
import json
import math
import os
import pathlib
import subprocess
import sys
import tempfile

EXE = pathlib.Path(__file__).resolve().parent.parent / "zig-out" / "bin" / "mcp-ml.exe"
TMP = pathlib.Path(tempfile.gettempdir()) / "opencode" / "mcp-ml-extreme"
TMP.mkdir(parents=True, exist_ok=True)

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("PASS:", name)
    else:
        FAIL += 1
        print("FAIL:", name, detail)


def run_raw(data: bytes, timeout=120):
    p = subprocess.run([str(EXE)], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def run(msgs, timeout=120):
    return run_raw("".join(json.dumps(m) + "\n" for m in msgs).encode(), timeout=timeout)


def call(name, args, i=1):
    return {"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": name, "arguments": args}}


def valid_lines(out: bytes):
    """Return (all_valid, count, bad_line_preview)."""
    ok = True
    n = 0
    bad = b""
    for line in out.split(b"\n"):
        if not line.strip():
            continue
        n += 1
        try:
            json.loads(line)
        except Exception:
            ok = False
            bad = line[:160]
    return ok, n, bad


def csv(name, text):
    p = TMP / name
    p.write_text(text, encoding="ascii")
    return str(p)


# ---------------------------------------------------------------- fuzz JSON-RPC
fuzz_cases = [
    b"",
    b"\n",
    b"\n\n\n",
    b"not json\n",
    b"{",
    b"}\n",
    b"{}\n",
    b"[]\n",
    b"null\n",
    b"123\n",
    b'"str"\n',
    b'{"jsonrpc":"2.0"}\n',
    b'{"id":1}\n',
    b'{"method":123}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call"}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":null}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":[]}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":5}}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"svd","arguments":[]}}\n',
    b'{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}\n',
    b'{"jsonrpc":"2.0","id":[1,2],"method":"ping"}\n',
    b'{"jsonrpc":"2.0","id":1e999,"method":"ping"}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"' + b"a" * 100000 + b'"}\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"sindy","arguments":{"data":"' + b"x" * 100000 + b'"}}}\n',
    b"\xff\xfe\x00\x01\n",
    b'{"jsonrpc":"2.0","id":1,"method":"\xc3\x28"}\n',  # invalid utf-8 sequence
    b"[" * 5000 + b"]" * 5000 + b"\n",
    b'{"a":' * 2000 + b'"x"' + b"}" * 2000 + b"\n",
    b'{"jsonrpc":"2.0","id":1,"method":"ping"}' + b"\x00" + b'\n',
    b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"svd","arguments":{"data":"' + b"." * 5000 + b'"}}}\n',
]

all_ok = True
detail = ""
for i, raw in enumerate(fuzz_cases):
    rc, out, err = run_raw(raw)
    if rc != 0:
        all_ok = False
        detail = f"case {i} rc={rc} raw={raw[:60]!r} err={err[:120]!r}"
        break
    ok, _, bad = valid_lines(out)
    if not ok:
        all_ok = False
        detail = f"case {i} invalid json line={bad!r} raw={raw[:60]!r}"
        break
check("fuzz JSON-RPC: no crash, always valid output", all_ok, detail)

# ---------------------------------------------------------------- unterminated flood (8MB cap)
rc, out, err = run_raw(b"{" + b"a" * (12 * 1024 * 1024))  # no newline, > cap
ok, n, bad = valid_lines(out)
check("unterminated 12MB input stays bounded", rc == 0 and ok, (rc, n, bad[:80]))

# ---------------------------------------------------------------- session: 2000 requests
msgs = [{"jsonrpc": "2.0", "id": i, "method": "ping"} for i in range(2000)]
rc, out, err = run(msgs)
ok, n, bad = valid_lines(out)
check("2000 requests in one session", rc == 0 and ok and n == 2000, (rc, n, bad[:80]))
ids = [json.loads(l)["id"] for l in out.split(b"\n") if l.strip()]
check("2000 responses keep ids in order", ids == list(range(2000)), ids[:5])

# ---------------------------------------------------------------- mixed session
mixed = [
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    call("chaos_lorenz", {}, 3),
    {"jsonrpc": "2.0", "method": "some/notification"},
    call("sequence", {"values": "1,2,3,4,5"}, 4),
]
rc, out, err = run(mixed)
ok, n, bad = valid_lines(out)
ids = [json.loads(l)["id"] for l in out.split(b"\n") if l.strip()]
check("mixed session only answers requests", rc == 0 and ok and ids == [1, 2, 3, 4], (rc, ids, bad[:80]))

# ---------------------------------------------------------------- bad params for every tool
bad_params = [
    ("sindy", {}),
    ("sindy", {"data": 123}),
    ("sindy", {"data": "no-existe.csv"}),
    ("sindy", {"data": TMP.as_posix()}),  # a directory
    ("svd", {"data": ""}),
    ("svd", {"data": "no-existe.csv"}),
    ("sequence", {"values": ""}),
    ("sequence", {"values": "abc"}),
    ("sequence", {"values": "1,2"}),
    ("dmd", {"data": "no-existe.csv", "rank": -3}),
    ("dmd", {"data": "no-existe.csv", "dt": -1}),
    ("dmd", {"data": "no-existe.csv", "dt": "x"}),
    ("pinv", {"data": "no-existe.csv"}),
    ("koopman", {"data": "no-existe.csv", "basis": 7}),
    ("koopman", {"data": "no-existe.csv", "ridge": "x"}),
    ("koopman_predict", {"data": "no-existe.csv", "steps": -1}),
    ("koopman_load_predict", {"path": "no-existe.json", "x0": "1"}),
    ("pdefind", {"data": "no-existe.csv", "dt": -1, "dx": 0}),
    ("model_load", {}),
    ("nope", {}),
]
ok = True
bad = []
for name, args in bad_params:
    rc, out, err = run([call(name, args)])
    try:
        o = json.loads(out.strip())
        if rc != 0 or "result" not in o or o["result"].get("isError") is not True:
            ok = False
            bad.append((name, args, out[:120]))
    except Exception as exc:  # noqa: BLE001
        ok = False
        bad.append((name, args, str(exc), out[:120]))
check("bad params -> isError, no crash", ok, bad[:3])

# extra/unknown args are tolerated (only chaos takes none)
rc, out, err = run([call("chaos_lorenz", {"bogus": 1})])
check("unknown extra args tolerated", rc == 0 and "result" in json.loads(out.strip()), out[:120])

# very long paths must not crash the process (Zig std stack overflow)
for tool, key in [
    ("svd", "data"),
    ("pinv", "data"),
    ("dmd", "data"),
    ("koopman", "data"),
    ("sindy", "data"),
    ("pdefind", "data"),
    ("model_load", "path"),
    ("koopman_load_predict", "path"),
]:
    rc, out, err = run([call(tool, {key: "x" * 70000, "x0": "1"})])
    inner_ok = False
    try:
        o = json.loads(out.strip())
        inner_ok = o["result"].get("isError") is True
    except Exception:
        pass
    check(f"long path rejected: {tool}", rc == 0 and inner_ok, (rc, out[:120]))

# long save path must not crash
rc, out, err = run([call("sindy", {"data": csv("lin.csv", "1,3\n2,5\n3,7\n4,9\n5,11"), "save": "x" * 70000})])
check("long save path rejected", rc == 0, (rc, out[:120]))

# ---------------------------------------------------------------- weird CSVs
weird = [
    ("", "empty"),
    ("\n\n\n", "only newlines"),
    ("1", "single value"),
    ("1,2", "single row"),
    ("1,2\n", "trailing newline"),
    ("1,2\r\n3,4\r\n5,6\r\n", "CRLF"),
    ("  1 , 2 \n 3 , 4 \n 5 , 6 ", "spaces"),
    ("1e3,2e-3\n4e3,5e-3\n6e3,7e-3", "scientific"),
    ("-1,-2\n-3,-4\n-5,-6", "negatives"),
    ("inf,1\n2,3\n4,5", "inf token"),
    ("nan,1\n2,3\n4,5", "nan token"),
    ("1,2,3\n4,5\n6,7,8", "ragged rows"),
    ("1,2\n3,x\n5,6", "non numeric"),
    ("1,2;\n3,4", "semicolon"),
    ("0,0\n0,0\n0,0", "all zeros"),
    ("1,2\n3,4", "too few rows"),
]
ok = True
bad = []
for i, (txt, label) in enumerate(weird):
    f = csv(f"weird{i}.csv", txt)
    for tool, args in [
        ("svd", {"data": f}),
        ("pinv", {"data": f}),
        ("dmd", {"data": f, "rank": 2}),
        ("sindy", {"data": f}),
        ("koopman", {"data": f}),
        ("pdefind", {"data": f, "dt": 1, "dx": 1}),
    ]:
        rc, out, err = run([call(tool, args)])
        if rc != 0:
            ok = False
            bad.append((label, tool, "crash", rc))
            continue
        try:
            json.loads(out.strip())
        except Exception:
            ok = False
            bad.append((label, tool, "bad json", out[:120]))
check("weird CSVs never crash / always valid JSON", ok, bad[:5])

# ---------------------------------------------------------------- shapes / extremes
# dmd rank bigger than the data
f = csv("dmd_small.csv", "1,2,3,4")
rc, out, err = run([call("dmd", {"data": f, "dt": 1, "rank": 999})])
check("dmd rank > data", rc == 0 and "result" in json.loads(out.strip()), out[:120])

# dmd rank cap: rank > 256 -> isError (evita O(r^3) por paso con r enorme)
f = csv("dmd_cap.csv", "\n".join(",".join(str((i * j) % 9) for j in range(40)) for i in range(40)))
rc, out, err = run([call("dmd", {"data": f, "dt": 0.1, "rank": 100000})])
inner_ok = False
try:
    inner_ok = json.loads(out.strip())["result"].get("isError") is True
except Exception:
    pass
check("dmd rank > 256 -> isError", rc == 0 and inner_ok, out[:160])

# svd 1 x 1
f = csv("one.csv", "7")
rc, out, err = run([call("svd", {"data": f})])
check("svd 1x1", rc == 0 and json.loads(out.strip())["result"].get("isError") is not True, out[:160])

# svd wide (m<n) rejected cleanly
f = csv("wide2.csv", "1,2,3,4\n5,6,7,8")
rc, out, err = run([call("svd", {"data": f})])
check("svd m<n is a clean error", rc == 0 and json.loads(out.strip())["result"].get("isError") is True, out[:160])

# sequence: 100k values
big = ",".join(str(math.sin(i / 100.0)) for i in range(100000))
rc, out, err = run([call("sequence", {"values": big})])
check("sequence 100k values", rc == 0 and json.loads(out.strip())["result"].get("isError") is not True, out[:160])

# sequence: all zeros, all same, alternating
for vals in ("0,0,0,0,0,0", "1,-1,1,-1,1,-1", "1e308,1e308,1e308,1e308"):
    rc, out, err = run([call("sequence", {"values": vals})])
    inner = None
    try:
        inner = json.loads(json.loads(out.strip())["result"]["content"][0]["text"])
    except Exception:
        pass
    check(f"sequence degenerate {vals[:20]}", rc == 0 and isinstance(inner, dict), out[:160])

# koopman with all-zero data
f = csv("zeros.csv", "0,0\n0,0\n0,0\n0,0")
rc, out, err = run([call("koopman", {"data": f})])
check("koopman all zeros", rc == 0 and "result" in json.loads(out.strip()), out[:160])

# koopman_predict: cota del espacio elevado (evita O(L^3) con L enorme)
rows_txt = "\n".join(",".join(str((i + j) % 7 + 1) for j in range(200)) for i in range(20))
f = csv("kp_big.csv", rows_txt)  # 20 filas x 200 cols -> state_dim = 100 -> poly2 L = 5151
rc, out, err = run([call("koopman_predict", {"data": f, "steps": 5})])
inner_ok = False
try:
    inner_ok = json.loads(out.strip())["result"].get("isError") is True
except Exception:
    pass
check("koopman_predict lifted_dim > 1024 -> isError (rapido)", rc == 0 and inner_ok, out[:160])

# koopman: misma cota desde el ajuste puro
rc, out, err = run([call("koopman", {"data": f})])
inner_ok = False
try:
    inner_ok = json.loads(out.strip())["result"].get("isError") is True
except Exception:
    pass
check("koopman lifted_dim > 1024 -> isError (rapido)", rc == 0 and inner_ok, out[:160])

# koopman_predict: cota de salida steps*state_dim (> 50M -> isError, sin reservar GBs)
rc, out, err = run([call("koopman_predict", {"data": f, "basis": "state", "steps": 1000000})])
inner_ok = False
try:
    inner_ok = json.loads(out.strip())["result"].get("isError") is True
except Exception:
    pass
check("koopman_predict steps*state_dim > 50M -> isError", rc == 0 and inner_ok, out[:160])

# koopman_load_predict with malformed model files
models = [
    ("{}", "empty obj"),
    ('{"state_dim":-1,"lifted_dim":2,"K":[1,2,3,4]}', "negative dim"),
    ('{"state_dim":1,"lifted_dim":2,"K":[1,2,3]}', "wrong K len"),
    ('{"state_dim":1,"lifted_dim":100000,"K":[1]}', "huge dim"),
    ('{"state_dim":1,"lifted_dim":2,"K":["a","b","c","d"]}', "non numeric K"),
    ('{"state_dim":1,"lifted_dim":2,"basis":"nope","K":[1,2,3,4]}', "bad basis"),
    ("[]", "array"),
    ("nonsense", "not json"),
]
ok = True
bad = []
for i, (txt, label) in enumerate(models):
    p = TMP / f"model{i}.json"
    p.write_text(txt, encoding="ascii")
    rc, out, err = run([call("koopman_load_predict", {"path": str(p), "x0": "1", "steps": 2})])
    if rc != 0:
        ok = False
        bad.append((label, "crash", rc))
        continue
    try:
        o = json.loads(out.strip())
        if o["result"].get("isError") is not True and label != "ok":
            ok = False
            bad.append((label, "no error", out[:120]))
    except Exception:
        ok = False
        bad.append((label, "bad json", out[:120]))
check("malformed koopman models -> isError", ok, bad[:4])

# koopman_load_predict: modelo con lifted_dim inconsistente => OOB si no se valida
oob_models = [
    ('{"state_dim":4096,"lifted_dim":1,"basis":"poly2","K":[5.0]}', "lifted demasiado pequeno"),
    ('{"state_dim":2,"lifted_dim":3,"basis":"poly2","K":[1,2,3,4,5,6,7,8,9]}', "lifted incorrecto (poly2 d=2 -> 6)"),
    ('{"state_dim":3,"lifted_dim":15,"basis":"poly3","K":[' + ",".join(["1"] * 225) + ']}', "poly3 d=3 -> 20 != 15"),
]
ok = True
bad = []
for i, (txt, label) in enumerate(oob_models):
    p = TMP / f"oob{i}.json"
    p.write_text(txt, encoding="ascii")
    rc, out, err = run([call("koopman_load_predict", {"path": str(p), "x0": "0", "steps": 2})])
    try:
        o = json.loads(out.strip())
        if rc != 0 or o["result"].get("isError") is not True:
            ok = False
            bad.append((label, rc, out[:100]))
    except Exception:
        ok = False
        bad.append((label, "crash/bad json", rc, out[:100]))
check("koopman lifted_dim inconsistente -> isError (no OOB)", ok, bad[:3])

# control positivo: modelo consistente (d=2, poly2 -> 6) debe funcionar
p = TMP / "oob_ok.json"
p.write_text('{"state_dim":2,"lifted_dim":6,"basis":"poly2","K":[' + ",".join(["0.5"] * 36) + "]}", encoding="ascii")
rc, out, err = run([call("koopman_load_predict", {"path": str(p), "x0": "1,2", "steps": 2})])
inner = None
try:
    inner = json.loads(out.strip())["result"]
except Exception:
    pass
check("koopman modelo consistente OK", rc == 0 and isinstance(inner, dict) and inner.get("isError") is not True, out[:160])

# ---------------------------------------------------------------- hostile arg types
# Para cada tool: `arguments` con tipos hostiles y cada propiedad del esquema con
# tipos hostiles. Solo exigimos "no crash + JSON valido + result/error presente".
rc, out, err = run([{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}])
tools = json.loads(out.strip())["result"]["tools"]

hostile_vals = [None, True, False, 0, -1, 1, 2**63 - 1, 1e308, -1e308, "x", "", [], {}, [1, 2, 3], {"a": 1}, "1,2,3"]

cases = []
for t in tools:
    name = t["name"]
    schema = t.get("inputSchema") or {}
    props = list((schema.get("properties") or {}).keys())
    if not props:
        props = ["topic"]
    for v in hostile_vals:
        cases.append((name, v))
    for key in props:
        for v in hostile_vals:
            cases.append((name, {key: v}))

ok = True
bad = []
BATCH = 200
for start in range(0, len(cases), BATCH):
    chunk = cases[start:start + BATCH]
    msgs = [call(n, a, i) for i, (n, a) in enumerate(chunk)]
    rc, out, err = run(msgs, timeout=300)
    if rc != 0:
        ok = False
        bad.append(("crash", start, rc, err[:120]))
        break
    valid, n, badline = valid_lines(out)
    if not valid or n != len(chunk):
        ok = False
        bad.append(("badjson", start, n, len(chunk), badline[:80]))
        break
    for l in out.split(b"\n"):
        if not l.strip():
            continue
        o = json.loads(l)
        if "result" not in o and "error" not in o:
            ok = False
            bad.append(("no result/error", start, l[:120]))
            break
check(f"hostile arg types ({len(cases)} casos): no crash, JSON valido", ok, bad[:3])

# ---------------------------------------------------------------- concurrency
def one_ping(_):
    rc, out, err = run([{"jsonrpc": "2.0", "id": 1, "method": "ping"}])
    return rc == 0 and json.loads(out.strip())["result"] == {}


with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    results = list(ex.map(one_ping, range(24)))
check("24 concurrent processes", all(results), results.count(False))

print()
print("PASS=%d FAIL=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
