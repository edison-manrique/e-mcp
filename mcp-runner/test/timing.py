import json, subprocess, time

EXE = str(__import__("pathlib").Path(__file__).resolve().parent.parent / "zig-out" / "bin" / "mcp-runner.exe")

def timed(code, lang, timeout_ms=0):
    r = {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"run_code","arguments":{"code":code,"lang":lang,"timeout_ms":timeout_ms}}}
    t0 = time.time()
    p = subprocess.run([EXE], input=(json.dumps(r)+"\n").encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
    dt = time.time() - t0
    j = json.loads(json.loads(p.stdout.decode())["result"]["content"][0]["text"])
    return dt, j

cases = {
    "rust": 'fn main(){ println!("x"); }',
    "zig": 'const std=@import("std"); pub fn main() !void { std.debug.print("x\\n", .{}); }',
    "c": '#include <stdio.h>\nint main(){ printf("x\\n"); return 0; }',
    "cpp": '#include <iostream>\nint main(){ std::cout << "x" << std::endl; }',
}
for lang, code in cases.items():
    times = []
    for i in range(4):
        dt, j = timed(code, lang)
        times.append(round(dt, 2))
        err = j.get("stderr", "")
        out = (j.get("stdout", "") + err).strip()
        if "timed out" in err or out != "x":
            print(f"  !! {lang} intento {i}: {dt:.2f}s  err={err[:60]!r}")
    print(f"{lang}: {times}")
