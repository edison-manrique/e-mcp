const std = @import("std");
const Io = std.Io;
const proto = @import("protocol.zig");
const eval = @import("eval.zig");
const ayuda = @import("ayuda.zig");
const registro = @import("registro.zig");
const abi = @import("abig/int.zig");
const afl = @import("abig/float.zig");
const ecf = @import("ec/field.zig");
const ecc = @import("ec/curve.zig");

// ============================================================
//  Motor matematico MCP "math" — entrada delgada.
//  Transporte/dispatch/CLI aqui; calculo en eval.zig,
//  identidad/herramientas en registro.zig, textos en ayuda.zig,
//  JSON-RPC en protocol.zig.
//  Sin argumentos: servidor MCP por stdio. Con args: CLI efimero.
// ============================================================

// Manifiesto de `--registro`: fuente unica en `registro.zig` (ver DEVELOPER.md §3).
const MANIFIESTO = registro.MANIFIESTO;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1 and std.mem.eql(u8, args[1], "--registro")) {
        var rbuf: [1024]u8 = undefined;
        var rw: Io.File.Writer = .initStreaming(.stdout(), io, &rbuf);
        try rw.interface.writeAll(MANIFIESTO);
        try rw.interface.writeAll("\n");
        try rw.interface.flush();
        return;
    }
    if (args.len > 1) {
        const code = runCli(io, args[1..]) catch 1;
        if (code != 0) std.process.exit(code);
        return;
    }

    var stdin_buf: [65536]u8 = undefined;
    var stdin_reader: Io.File.Reader = .initStreaming(.stdin(), io, &stdin_buf);
    var in: *Io.Reader = &stdin_reader.interface;

    var stdout_buf: [65536]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buf);
    var out: *Io.Writer = &stdout_writer.interface;

    var msg: std.ArrayList(u8) = .empty;
    defer msg.deinit(gpa);

    while (true) {
        const line = in.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed => break,
            error.StreamTooLong => {
                _ = in.discardDelimiterInclusive('\n') catch break;
                msg.clearRetainingCapacity();
                try proto.sendJsonError(out, null, -32700, "Parse error");
                out.flush() catch {};
                continue;
            },
        };
        if (line == null) {
            if (msg.items.len > 0) {
                const t = std.mem.trim(u8, msg.items, " \t\r\n");
                if (t.len > 0) try dispatch(t, io, out, gpa);
            }
            break;
        }
        var l = line.?;
        if (l.len > 0 and l[l.len - 1] == '\r') l = l[0 .. l.len - 1];
        if (l.len == 0 and msg.items.len == 0) continue;
        try msg.appendSlice(gpa, l);
        try msg.append(gpa, '\n');
        const trimmed = std.mem.trim(u8, msg.items, " \t\r\n");
        if (trimmed.len == 0) {
            msg.clearRetainingCapacity();
            continue;
        }
        if (!proto.bracesBalanced(trimmed)) {
            const solo = std.mem.trim(u8, l, " \t");
            if (solo.len > 0 and proto.parsesAsObject(solo, gpa)) {
                msg.clearRetainingCapacity();
                try dispatch(solo, io, out, gpa);
            }
            continue;
        }
        try dispatch(trimmed, io, out, gpa);
        msg.clearRetainingCapacity();
    }
    out.flush() catch {};
}

fn dispatch(raw: []const u8, io: Io, out: *Io.Writer, gpa: std.mem.Allocator) !void {
    // Flush por respuesta: el pool persistente lee linea a linea sin EOF.
    defer out.flush() catch {};
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch {
        try proto.sendJsonError(out, null, -32700, "Parse error");
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        try proto.sendJsonError(out, null, -32700, "Parse error");
        return;
    }
    const obj = parsed.value.object;
    const m = obj.get("method") orelse return;
    if (m != .string) return;
    const method = m.string;
    const id_opt = obj.get("id");

    if (method.len >= 14 and std.mem.eql(u8, method[0..@min(method.len, 14)], "notifications/")) return;

    if (std.mem.eql(u8, method, "initialize")) {
        try proto.sendResult(out, id_opt, "{\"protocolVersion\":\"" ++ registro.PROTOCOLO ++ "\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"" ++ registro.SERVIDOR ++ "\",\"version\":\"" ++ registro.VERSION ++ "\"}}");
        return;
    }
    if (std.mem.eql(u8, method, "ping")) {
        try proto.sendResult(out, id_opt, "{}");
        return;
    }
    if (std.mem.eql(u8, method, "tools/list")) {
        try sendToolsList(out, id_opt);
        return;
    }
    if (std.mem.eql(u8, method, "tools/call")) {
        const id = id_opt orelse return;
        const params = obj.get("params");
        var tool_name: []const u8 = "";
        var args: ?std.json.Value = null;
        if (params != null and params.? == .object) {
            const p = params.?.object;
            if (p.get("name")) |n| {
                if (n == .string) tool_name = n.string;
            }
            if (p.get("arguments")) |a| {
                if (a == .object) args = a;
            }
        }
        for (TOOLS) |t| {
            if (std.mem.eql(u8, tool_name, t.name)) {
                try t.run(.{ .io = io, .out = out, .id = id, .args = args });
                return;
            }
        }
        try proto.sendToolError(out, id, "Herramienta desconocida. Usa 'math_help' para ver la ayuda.");
        return;
    }
    try proto.sendJsonError(out, id_opt, -32601, "Method not found");
}

// ---------- Registro (1 linea por herramienta) ----------

const Tool = struct {
    name: []const u8,
    list_json: []const u8,
    run: *const fn (proto.Ctx) Io.Writer.Error!void,
};

const TOOLS = [_]Tool{
    .{ .name = registro.CALC, .list_json = registro.JSON_CALC, .run = runCalc },
    .{ .name = registro.AYUDA, .list_json = registro.JSON_AYUDA, .run = runMathHelp },
    .{ .name = registro.BIG, .list_json = registro.JSON_BIG, .run = runBig },
};

fn sendToolsList(out: *Io.Writer, id: ?std.json.Value) !void {
    if (id == null) return;
    try out.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try proto.writeId(out, id);
    try out.writeAll(",\"result\":{\"tools\":[");
    for (TOOLS, 0..) |t, i| {
        if (i > 0) try out.writeAll(",");
        try out.writeAll(t.list_json);
    }
    try out.writeAll("]}}\n");
    try out.flush();
}

// ---------- Handlers ----------

fn runCalc(ctx: proto.Ctx) !void {
    const expr = proto.argStr(ctx.args, "expr", "");
    const digits = proto.argDigits(ctx.args);
    const frac = proto.argBool(ctx.args, "frac");
    if (expr.len > 4000) {
        try proto.sendToolError(ctx.out, ctx.id, "Invalid params: expr demasiado larga (max 4000).");
        return;
    }
    if (ctx.args) |a| {
        if (a == .object) {
            if (a.object.get("digits")) |_| {
                if (digits == null) {
                    try proto.sendToolError(ctx.out, ctx.id, "Invalid params: digits debe ser entero 0-15.");
                    return;
                }
            }
        }
    }
    var pos: usize = 0;
    const v = eval.evaluate(expr, &pos) catch |e| {
        var mbuf: [128]u8 = undefined;
        try proto.sendToolError(ctx.out, ctx.id, eval.evalMessage(e, pos, &mbuf));
        return;
    };
    if (!std.math.isFinite(v) or !std.math.isFinite(eval.roundDigits(v, digits))) {
        try proto.sendToolError(ctx.out, ctx.id, "Desbordamiento: resultado no finito (infinito)");
        return;
    }
    var inner_buf: [8192]u8 = undefined;
    var inner: Io.Writer = .fixed(&inner_buf);
    eval.writeCalcJson(&inner, std.mem.trim(u8, expr, " \t\r\n"), v, digits, frac) catch {
        try proto.sendToolError(ctx.out, ctx.id, "Expresion demasiado larga (max ~8KB de respuesta)");
        return;
    };
    try proto.sendToolText(ctx.out, ctx.id, inner.buffered());
}

fn runMathHelp(ctx: proto.Ctx) !void {
    const topic = proto.argStr(ctx.args, "topic", "all");
    const md = ayuda.topicMd(topic) orelse {
        try proto.sendToolError(ctx.out, ctx.id, "Invalid params: topic desconocido (all|ops|ejemplos|calc|big).");
        return;
    };
    try proto.sendToolText(ctx.out, ctx.id, md);
}

// ---------- big: enteros arbitrarios + decimales de alta precision ----------
// Nucleo puro: mismo codigo para MCP (runBig) y CLI (--op). Usa arena
// del llamador; devuelve el JSON de resultado ya formateado.
fn runBig(ctx: proto.Ctx) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var msg: []const u8 = "Invalid params: revisa op/a/b/m/e/prec/out";
    const json = bigJsonArgs(alloc, ctx.args, &msg) catch |e| {
        const m: []const u8 = switch (e) {
            error.DivZero => "Division entre cero",
            error.NoInverse => "Sin inverso modular (gcd(a,m) != 1)",
            error.TooBig => "Demasiado grande (max 16384 bits, prec 1-500, exp acotado)",
            error.Invalid => msg,
            else => "Error interno de calculo",
        };
        try proto.sendToolError(ctx.out, ctx.id, m);
        return;
    };
    defer alloc.free(json);
    try proto.sendToolText(ctx.out, ctx.id, json);
}

const BigReq = struct {
    op: []const u8,
    a: []const u8,
    b: []const u8 = "",
    m: []const u8 = "",
    e: []const u8 = "",
    px: []const u8 = "",
    py: []const u8 = "",
    qx: []const u8 = "",
    qy: []const u8 = "",
    k: []const u8 = "",
    p: []const u8 = "",
    ca: []const u8 = "",
    cb: []const u8 = "",
    cn: []const u8 = "",
    gx: []const u8 = "",
    gy: []const u8 = "",
    prec: u16 = 30,
    out: []const u8 = "dec",
};

fn bigJsonArgs(alloc: std.mem.Allocator, args: ?std.json.Value, msg: *[]const u8) ![]u8 {
    var prec: u16 = 30;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("prec")) |v| {
                if (v != .integer or v.integer < 1 or v.integer > 500) {
                    msg.* = "Invalid params: prec 1-500.";
                    return error.Invalid;
                }
                prec = @intCast(v.integer);
            }
        }
    }
    return bigJson(alloc, .{
        .op = proto.argStr(args, "op", ""),
        .a = proto.argStr(args, "a", ""),
        .b = proto.argStr(args, "b", ""),
        .m = proto.argStr(args, "m", ""),
        .e = proto.argStr(args, "e", ""),
        .px = proto.argStr(args, "px", ""),
        .py = proto.argStr(args, "py", ""),
        .qx = proto.argStr(args, "qx", ""),
        .qy = proto.argStr(args, "qy", ""),
        .k = proto.argStr(args, "k", ""),
        .p = proto.argStr(args, "p", ""),
        .ca = proto.argStr(args, "ca", ""),
        .cb = proto.argStr(args, "cb", ""),
        .cn = proto.argStr(args, "cn", proto.argStr(args, "n", "")),
        .gx = proto.argStr(args, "gx", ""),
        .gy = proto.argStr(args, "gy", ""),
        .prec = prec,
        .out = proto.argStr(args, "out", "dec"),
    }, msg);
}

fn bigJson(alloc: std.mem.Allocator, req: BigReq, msg: *[]const u8) ![]u8 {
    const op = req.op;
    const sa = req.a;
    const is_ec = std.mem.eql(u8, op, "econcurve") or std.mem.eql(u8, op, "ecadd") or std.mem.eql(u8, op, "ecneg") or std.mem.eql(u8, op, "ecmul") or std.mem.eql(u8, op, "ecgen") or std.mem.eql(u8, op, "ecdecomp") or std.mem.eql(u8, op, "ecenum") or std.mem.eql(u8, op, "ecord");
    const needs_a = !is_ec and !(std.mem.eql(u8, op, "ecmul") or std.mem.eql(u8, op, "ecadd") or std.mem.eql(u8, op, "ecneg") or std.mem.eql(u8, op, "econcurve"));
    if (op.len == 0 or (needs_a and sa.len == 0)) {
        msg.* = "Invalid params: op y a obligatorios. op: add|sub|mul|div|mod|pow|powmod|invmod|gcd|sqrt|neg|abs|cmp|fadd|fsub|fmul|fdiv|fsqrt.";
        return error.Invalid;
    }
    if (sa.len > 2000) {
        msg.* = "Invalid params: a demasiado largo (max 2000).";
        return error.Invalid;
    }
    const sb = req.b;
    const sm = req.m;
    const se = req.e;
    for ([_][]const u8{ sb, sm, se, req.px, req.py, req.qx, req.qy, req.k, req.p, req.ca, req.cb, req.cn, req.gx, req.gy }) |s| {
        if (s.len > 2000) {
            msg.* = "Invalid params: campo demasiado largo (max 2000).";
            return error.Invalid;
        }
    }
    const prec = req.prec;
    const out = req.out;
    const want_hex = std.mem.eql(u8, out, "hex") or std.mem.eql(u8, out, "both");
    const want_dec = !std.mem.eql(u8, out, "hex");
    if (!want_hex and !std.mem.eql(u8, out, "dec") and !std.mem.eql(u8, out, "both")) {
        msg.* = "Invalid params: out dec|hex|both.";
        return error.Invalid;
    }

    // Flotantes de alta precision.
    if (op.len > 0 and op[0] == 'f') {
        if (want_hex and !want_dec) {
            msg.* = "Invalid params: out=hex solo para enteros.";
            return error.Invalid;
        }
        var fa = try afl.parse(alloc, sa);
        defer fa.deinit();
        var res: afl.Dec = undefined;
        var owned = false;
        if (std.mem.eql(u8, op, "fadd") or std.mem.eql(u8, op, "fsub") or std.mem.eql(u8, op, "fmul") or std.mem.eql(u8, op, "fdiv")) {
            if (sb.len == 0) {
                msg.* = "Invalid params: falta b.";
                return error.Invalid;
            }
            var fb = try afl.parse(alloc, sb);
            defer fb.deinit();
            if (std.mem.eql(u8, op, "fadd")) res = try afl.add(alloc, &fa, &fb, prec);
            if (std.mem.eql(u8, op, "fsub")) res = try afl.sub(alloc, &fa, &fb, prec);
            if (std.mem.eql(u8, op, "fmul")) res = try afl.mul(alloc, &fa, &fb, prec);
            if (std.mem.eql(u8, op, "fdiv")) res = try afl.div(alloc, &fa, &fb, prec);
            owned = true;
        } else if (std.mem.eql(u8, op, "fsqrt")) {
            res = try afl.sqrt(alloc, &fa, prec);
            owned = true;
        } else {
            msg.* = "Invalid params: op fadd|fsub|fmul|fdiv|fsqrt.";
            return error.Invalid;
        }
        defer {
            if (owned) res.deinit();
        }
        const txt = try afl.format(alloc, &res);
        return formatBigJson(alloc, op, txt, null, null, null, null);
    }

    // Campo primo Fp (pide m) y curva eliptica (preset secp256k1).
    if (std.mem.eql(u8, op, "madd") or std.mem.eql(u8, op, "msub") or std.mem.eql(u8, op, "mmul") or std.mem.eql(u8, op, "mdiv") or std.mem.eql(u8, op, "mpow") or std.mem.eql(u8, op, "msqrt")) {
        if (sm.len == 0) {
            msg.* = "Invalid params: operacion modular necesita m (primo).";
            return error.Invalid;
        }
        var fld = ecf.Field.init(alloc, sm) catch {
            msg.* = "Invalid params: m debe ser primo impar > 2.";
            return error.Invalid;
        };
        defer fld.deinit();
        var fa = abi.parse(alloc, sa) catch {
            msg.* = "Invalid params: a mal formado.";
            return error.Invalid;
        };
        defer fa.deinit();
        var rr: abi.Big = undefined;
        var rr_owned = false;
        defer {
            if (rr_owned) rr.deinit();
        }
        if (std.mem.eql(u8, op, "msqrt")) {
            rr = fld.sqrt(alloc, &fa) catch |er| {
                if (er == error.NoResidue) {
                    msg.* = "Sin raiz cuadrada mod m (no-residuo).";
                    return error.Invalid;
                }
                return er;
            };
            rr_owned = true;
        } else {
            if (sb.len == 0 and !std.mem.eql(u8, op, "msqrt")) {
                msg.* = "Invalid params: falta b.";
                return error.Invalid;
            }
            var fb = try abi.parse(alloc, sb);
            defer fb.deinit();
            if (std.mem.eql(u8, op, "madd")) rr = try fld.add(alloc, &fa, &fb);
            if (std.mem.eql(u8, op, "msub")) rr = try fld.sub(alloc, &fa, &fb);
            if (std.mem.eql(u8, op, "mmul")) rr = try fld.mul(alloc, &fa, &fb);
            if (std.mem.eql(u8, op, "mdiv")) rr = try fld.div(alloc, &fa, &fb);
            if (std.mem.eql(u8, op, "mpow")) rr = try fld.pow(alloc, &fa, &fb);
            rr_owned = true;
        }
        if (want_dec) {
            const txt = try abi.toDec(alloc, &rr);
            var hx: ?[]u8 = null;
            defer if (hx) |t| alloc.free(t);
            if (want_hex) hx = try abi.toHex(alloc, &rr);
            const js = try formatBigJson(alloc, op, txt, null, hx, null, null);
            alloc.free(txt);
            return js;
        } else {
            const txt = try abi.toHex(alloc, &rr);
            defer alloc.free(txt);
            return formatBigJson(alloc, op, txt, null, null, null, null);
        }
    }

    // Curva eliptica: preset secp256k1 o personalizada y^2=x^3+ca*x+cb sobre Fp.
    // Personalizada: pasa p (+ ca, cb, cn opcionales; gx,gy para ecgen).
    if (std.mem.eql(u8, op, "econcurve") or std.mem.eql(u8, op, "ecadd") or std.mem.eql(u8, op, "ecneg") or std.mem.eql(u8, op, "ecmul") or std.mem.eql(u8, op, "ecgen") or std.mem.eql(u8, op, "ecdecomp") or std.mem.eql(u8, op, "ecenum") or std.mem.eql(u8, op, "ecord")) {
        const custom = req.p.len > 0 or req.ca.len > 0 or req.cb.len > 0 or req.cn.len > 0 or req.gx.len > 0 or req.gy.len > 0;
        var curve: ecc.Curve = undefined;
        var curve_ok = false;
        defer {
            if (curve_ok) curve.deinit();
        }
        if (custom) {
            if (req.p.len == 0) {
                msg.* = "Invalid params: curva personalizada necesita p (primo).";
                return error.Invalid;
            }
            curve = ecc.Curve.initParams(alloc, req.p, req.ca, req.cb, if (req.cn.len == 0) null else req.cn) catch {
                msg.* = "Invalid params: p debe ser primo impar > 2 y 4a^3+27b^2 != 0.";
                return error.Invalid;
            };
            curve_ok = true;
        } else {
            curve = ecc.Curve.initSecp256k1(alloc) catch {
                msg.* = "Error interno de curva.";
                return error.Invalid;
            };
            curve_ok = true;
        }
        var pt: ecc.Point = undefined;
        var has_pt = false;
        defer {
            if (has_pt) pt.deinit();
        }
        if (std.mem.eql(u8, op, "ecenum")) {
            // Enumera puntos afines para p chico (didactico). Limite p<=5000.
            var pv = abi.parse(alloc, req.p) catch {
                msg.* = "Invalid params: ecenum necesita p (usa p<=5000).";
                return error.Invalid;
            };
            defer pv.deinit();
            const pu = pv.toInt(usize) catch {
                msg.* = "Invalid params: ecenum necesita p<=5000.";
                return error.Invalid;
            };
            if (pu < 5 or pu > 5000) {
                msg.* = "Invalid params: ecenum necesita p 5..5000.";
                return error.Invalid;
            }
            return ecEnumJson(alloc, &curve, pu, op, msg);
        }
        if (std.mem.eql(u8, op, "econcurve")) {
            if (req.px.len == 0 or req.py.len == 0) {
                msg.* = "Invalid params: econcurve necesita px, py.";
                return error.Invalid;
            }
            var x = abi.parse(alloc, req.px) catch {
                msg.* = "Invalid params: px mal formado.";
                return error.Invalid;
            };
            defer x.deinit();
            var y = abi.parse(alloc, req.py) catch {
                msg.* = "Invalid params: py mal formado.";
                return error.Invalid;
            };
            defer y.deinit();
            var p = ecc.Point{ .x = try x.clone(), .y = try y.clone(), .inf = false };
            defer p.deinit();
            const ok = try curve.isOnCurve(&p);
            return formatBigJson(alloc, op, if (ok) "1" else "0", null, null, null, null);
        }
        if (std.mem.eql(u8, op, "ecord")) {
            if (req.px.len == 0 or req.py.len == 0) {
                msg.* = "Invalid params: ecord necesita px, py (+ p/ca/cb si es personalizada).";
                return error.Invalid;
            }
            var x = abi.parse(alloc, req.px) catch {
                msg.* = "Invalid params: px mal formado.";
                return error.Invalid;
            };
            defer x.deinit();
            var y = abi.parse(alloc, req.py) catch {
                msg.* = "Invalid params: py mal formado.";
                return error.Invalid;
            };
            defer y.deinit();
            var p = ecc.Point{ .x = try x.clone(), .y = try y.clone(), .inf = false };
            defer p.deinit();
            if (!try curve.isOnCurve(&p)) {
                msg.* = "Punto fuera de curva.";
                return error.Invalid;
            }
            var ord = curve.orderOf(alloc, &p, 1000000) catch |e| {
                if (e == error.Range) {
                    msg.* = "Orden > 1e6 (fuera de limite didactico).";
                    return error.Invalid;
                }
                if (e == error.Invalid) {
                    msg.* = "Punto fuera de curva.";
                    return error.Invalid;
                }
                return e;
            };
            defer ord.deinit();
            const txt = try abi.toDec(alloc, &ord);
            defer alloc.free(txt);
            return formatBigJson(alloc, op, txt, null, null, null, null);
        }
        if (std.mem.eql(u8, op, "ecdecomp")) {
            if (sa.len == 0) {
                msg.* = "Invalid params: ecdecomp necesita a = 0x02|03...";
                return error.Invalid;
            }
            pt = curve.decompress(alloc, sa) catch {
                msg.* = "Invalid params: comprimido invalido para esta curva.";
                return error.Invalid;
            };
            has_pt = true;
        } else if (std.mem.eql(u8, op, "ecgen")) {
            var kk = abi.parse(alloc, sa) catch {
                msg.* = "Invalid params: a (k) mal formado.";
                return error.Invalid;
            };
            defer kk.deinit();
            if (custom) {
                if (req.gx.len == 0 or req.gy.len == 0) {
                    msg.* = "Invalid params: ecgen personalizado necesita gx, gy (generador).";
                    return error.Invalid;
                }
                var gx = abi.parse(alloc, req.gx) catch {
                    msg.* = "Invalid params: gx mal formado.";
                    return error.Invalid;
                };
                defer gx.deinit();
                var gy = abi.parse(alloc, req.gy) catch {
                    msg.* = "Invalid params: gy mal formado.";
                    return error.Invalid;
                };
                defer gy.deinit();
                var g = ecc.Point{ .x = try gx.clone(), .y = try gy.clone(), .inf = false };
                defer g.deinit();
                if (!try curve.isOnCurve(&g)) {
                    msg.* = "Generador (gx,gy) fuera de curva.";
                    return error.Invalid;
                }
                pt = try curve.mul(alloc, &kk, &g);
            } else {
                pt = try curve.gen(alloc, &kk);
            }
            has_pt = true;
        } else {
            if (req.px.len == 0 or req.py.len == 0) {
                msg.* = "Invalid params: se necesita px, py.";
                return error.Invalid;
            }
            var x = abi.parse(alloc, req.px) catch {
                msg.* = "Invalid params: px mal formado.";
                return error.Invalid;
            };
            defer x.deinit();
            var y = abi.parse(alloc, req.py) catch {
                msg.* = "Invalid params: py mal formado.";
                return error.Invalid;
            };
            defer y.deinit();
            var p = ecc.Point{ .x = try x.clone(), .y = try y.clone(), .inf = false };
            defer p.deinit();
            if (std.mem.eql(u8, op, "ecneg")) {
                pt = try curve.neg(&p);
                has_pt = true;
            } else if (std.mem.eql(u8, op, "ecmul")) {
                if (req.k.len == 0) {
                    msg.* = "Invalid params: ecmul necesita k.";
                    return error.Invalid;
                }
                var kk = abi.parse(alloc, req.k) catch {
                    msg.* = "Invalid params: k mal formada.";
                    return error.Invalid;
                };
                defer kk.deinit();
                if (!try curve.isOnCurve(&p)) {
                    msg.* = "Punto fuera de curva.";
                    return error.Invalid;
                }
                pt = try curve.mul(alloc, &kk, &p);
                has_pt = true;
            } else if (std.mem.eql(u8, op, "ecadd")) {
                if (req.qx.len == 0 or req.qy.len == 0) {
                    msg.* = "Invalid params: ecadd necesita qx, qy.";
                    return error.Invalid;
                }
                var qx = abi.parse(alloc, req.qx) catch {
                    msg.* = "Invalid params: qx mal formada.";
                    return error.Invalid;
                };
                defer qx.deinit();
                var qy = abi.parse(alloc, req.qy) catch {
                    msg.* = "Invalid params: qy mal formada.";
                    return error.Invalid;
                };
                defer qy.deinit();
                var q = ecc.Point{ .x = try qx.clone(), .y = try qy.clone(), .inf = false };
                defer q.deinit();
                if (!try curve.isOnCurve(&p) or !try curve.isOnCurve(&q)) {
                    msg.* = "Punto fuera de curva.";
                    return error.Invalid;
                }
                pt = try curve.add(alloc, &p, &q);
                has_pt = true;
            } else {
                msg.* = "Invalid params: op ec econcurve|ecadd|ecneg|ecmul|ecgen|ecdecomp|ecenum|ecord.";
                return error.Invalid;
            }
        }
        if (pt.inf) return formatBigJson(alloc, op, "infinito", null, null, null, null);
        const comp = try curve.compress(alloc, &pt);
        defer alloc.free(comp);
        const xd = try abi.toDec(alloc, &pt.x);
        defer alloc.free(xd);
        const yd = try abi.toDec(alloc, &pt.y);
        defer alloc.free(yd);
        return formatBigJson(alloc, op, comp, null, null, xd, yd);
    }

    // Enteros arbitrarios.
    var ia = try abi.parse(alloc, sa);
    defer ia.deinit();
    var ri: abi.Big = undefined;
    var owned_i = false;
    var rem_txt: ?[]u8 = null;
    defer if (rem_txt) |t| alloc.free(t);
    if (std.mem.eql(u8, op, "add") or std.mem.eql(u8, op, "sub") or std.mem.eql(u8, op, "mul") or std.mem.eql(u8, op, "div") or std.mem.eql(u8, op, "mod") or std.mem.eql(u8, op, "gcd") or std.mem.eql(u8, op, "cmp")) {
        if (sb.len == 0) {
            msg.* = "Invalid params: falta b.";
            return error.Invalid;
        }
        var ib = try abi.parse(alloc, sb);
        defer ib.deinit();
        if (std.mem.eql(u8, op, "add")) ri = try abi.add(alloc, &ia, &ib);
        if (std.mem.eql(u8, op, "sub")) ri = try abi.sub(alloc, &ia, &ib);
        if (std.mem.eql(u8, op, "mul")) ri = try abi.mul(alloc, &ia, &ib);
        if (std.mem.eql(u8, op, "gcd")) {
            var x = ia;
            var y = ib;
            ri = try BigGcd(alloc, &x, &y);
        }
        if (std.mem.eql(u8, op, "cmp")) {
            const o = abi.Big.order(ia, ib);
            const txt: []const u8 = switch (o) {
                .lt => "-1",
                .eq => "0",
                .gt => "1",
            };
            return formatBigJson(alloc, op, txt, null, null, null, null);
        }
        if (std.mem.eql(u8, op, "div")) {
            const d = try abi.divTrunc(alloc, &ia, &ib);
            const q = d.q;
            var r = d.r;
            defer r.deinit();
            ri = q;
            rem_txt = try abi.toDec(alloc, &r);
        }
        if (std.mem.eql(u8, op, "mod")) {
            var im = ib;
            if (im.eqlZero() or !im.isPositive()) {
                msg.* = "Invalid params: b (modulo) debe ser > 0.";
                return error.Invalid;
            }
            ri = try abi.modPos(alloc, &ia, &ib);
        }
        owned_i = true;
    } else if (std.mem.eql(u8, op, "pow")) {
        if (sb.len == 0) {
            msg.* = "Invalid params: falta b (exponente 0-100000).";
            return error.Invalid;
        }
        const eu = std.fmt.parseInt(u32, sb, 10) catch {
            msg.* = "Invalid params: b debe ser entero 0-100000.";
            return error.Invalid;
        };
        ri = try abi.powU32(alloc, &ia, eu);
        owned_i = true;
    } else if (std.mem.eql(u8, op, "powmod")) {
        if (se.len == 0 or sm.len == 0) {
            msg.* = "Invalid params: powmod necesita e y m.";
            return error.Invalid;
        }
        var ie = try abi.parse(alloc, se);
        defer ie.deinit();
        var im = try abi.parse(alloc, sm);
        defer im.deinit();
        ri = try abi.powMod(alloc, &ia, &ie, &im);
        owned_i = true;
    } else if (std.mem.eql(u8, op, "invmod")) {
        if (sm.len == 0) {
            msg.* = "Invalid params: invmod necesita m.";
            return error.Invalid;
        }
        var im = try abi.parse(alloc, sm);
        defer im.deinit();
        ri = try abi.invMod(alloc, &ia, &im);
        owned_i = true;
    } else if (std.mem.eql(u8, op, "sqrt")) {
        if (!ia.isPositive()) {
            msg.* = "Fuera de dominio: sqrt de negativo.";
            return error.Invalid;
        }
        var r = try abi.Big.init(alloc);
        errdefer r.deinit();
        var x = ia;
        try r.sqrt(&x);
        ri = r;
        owned_i = true;
    } else if (std.mem.eql(u8, op, "neg")) {
        var r = try ia.clone();
        if (!r.eqlZero()) r.negate();
        ri = r;
        owned_i = true;
    } else if (std.mem.eql(u8, op, "abs")) {
        var r = try ia.clone();
        if (!r.isPositive()) r.abs();
        ri = r;
        owned_i = true;
    } else {
        msg.* = "Invalid params: op add|sub|mul|div|mod|pow|powmod|invmod|gcd|sqrt|neg|abs|cmp|fadd|fsub|fmul|fdiv|fsqrt|madd|msub|mmul|mdiv|mpow|msqrt|econcurve|ecadd|ecneg|ecmul|ecgen|ecdecomp|ecenum|ecord.";
        return error.Invalid;
    }
    defer {
        if (owned_i) ri.deinit();
    }
    if (want_dec) {
        const txt = try abi.toDec(alloc, &ri);
        var hx: ?[]u8 = null;
        defer if (hx) |t| alloc.free(t);
        if (want_hex) hx = try abi.toHex(alloc, &ri);
        const js = try formatBigJson(alloc, op, txt, rem_txt, hx, null, null);
        alloc.free(txt);
        return js;
    } else {
        const txt = try abi.toHex(alloc, &ri);
        defer alloc.free(txt);
        return formatBigJson(alloc, op, txt, rem_txt, null, null, null);
    }
}

fn BigGcd(alloc: std.mem.Allocator, x: *abi.Big, y: *abi.Big) !abi.Big {
    var r = try abi.Big.init(alloc);
    errdefer r.deinit();
    var a = x.*;
    var b = y.*;
    try r.gcd(&a, &b);
    if (!r.isPositive()) r.abs();
    return r;
}

// ecenum: cuenta puntos (incluye infinito) y muestra hasta 12 en "(x,y)".
// Solo curvas chicas (p<=5000). Respuesta compacta < 8KB.
fn ecEnumJson(alloc: std.mem.Allocator, curve: *ecc.Curve, pu: usize, op: []const u8, msg: *[]const u8) ![]u8 {
    _ = msg;
    var buf: [16384]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try w.writeAll("{\"op\":");
    try eval.writeJsonStr(&w, op);
    var count: usize = 1; // infinito
    try w.writeAll(",\"count\":\"");
    // Dos pasadas: primero contar, luego listar (evita guardar todo).
    var px: usize = 0;
    while (px < pu) : (px += 1) {
        var xb = try abi.Big.initSet(alloc, px);
        defer xb.deinit();
        const x2 = try curve.f.mul(alloc, &xb, &xb);
        defer {
            var t = x2;
            t.deinit();
        }
        const x3 = try curve.f.mul(alloc, &x2, &xb);
        defer {
            var t = x3;
            t.deinit();
        }
        const ax = try curve.f.mul(alloc, &curve.a, &xb);
        defer {
            var t = ax;
            t.deinit();
        }
        const s1 = try curve.f.add(alloc, &x3, &ax);
        defer {
            var t = s1;
            t.deinit();
        }
        const rhs = try curve.f.add(alloc, &s1, &curve.b);
        defer {
            var t = rhs;
            t.deinit();
        }
        const leg = try curve.f.legendre(alloc, &rhs);
        if (leg == 0) {
            count += 1;
        } else if (leg == 1) {
            count += 2;
        }
    }
    try w.print("{d}", .{count});
    try w.writeAll("\",\"pts\":[");
    var shown: usize = 0;
    px = 0;
    while (px < pu and shown < 12) : (px += 1) {
        var xb = try abi.Big.initSet(alloc, px);
        defer xb.deinit();
        const x2 = try curve.f.mul(alloc, &xb, &xb);
        defer {
            var t = x2;
            t.deinit();
        }
        const x3 = try curve.f.mul(alloc, &x2, &xb);
        defer {
            var t = x3;
            t.deinit();
        }
        const ax = try curve.f.mul(alloc, &curve.a, &xb);
        defer {
            var t = ax;
            t.deinit();
        }
        const s1 = try curve.f.add(alloc, &x3, &ax);
        defer {
            var t = s1;
            t.deinit();
        }
        const rhs = try curve.f.add(alloc, &s1, &curve.b);
        defer {
            var t = rhs;
            t.deinit();
        }
        const leg = try curve.f.legendre(alloc, &rhs);
        if (leg == 0) {
            if (shown > 0) try w.writeAll(",");
            try w.print("\"({d},0)\"", .{px});
            shown += 1;
        } else if (leg == 1) {
            var y0 = try curve.f.sqrt(alloc, &rhs);
            defer y0.deinit();
            const y0v = try y0.toInt(usize);
            var y1b = try curve.f.neg(alloc, &y0);
            defer y1b.deinit();
            const y1v = try y1b.toInt(usize);
            if (shown > 0) try w.writeAll(",");
            try w.print("\"({d},{d})\"", .{ px, y0v });
            shown += 1;
            if (shown < 12 and y1v != y0v) {
                try w.print(",\"({d},{d})\"", .{ px, y1v });
                shown += 1;
            }
        }
    }
    try w.writeAll("]}");
    return alloc.dupe(u8, w.buffered());
}

fn formatBigJson(alloc: std.mem.Allocator, op: []const u8, result: []const u8, rem: ?[]u8, hex: ?[]u8, x: ?[]u8, y: ?[]u8) ![]u8 {
    // Resultados acotados por MAX_BITS (16384 bits ~ 5KB): buffer fijo + dupe.
    var buf: [16384]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try w.writeAll("{\"op\":");
    try eval.writeJsonStr(&w, op);
    try w.writeAll(",\"result\":");
    try eval.writeJsonStr(&w, result);
    if (rem) |t| {
        try w.writeAll(",\"rem\":");
        try eval.writeJsonStr(&w, t);
    }
    if (hex) |h| {
        try w.writeAll(",\"hex\":");
        try eval.writeJsonStr(&w, h);
    }
    if (x) |xv| {
        try w.writeAll(",\"x\":");
        try eval.writeJsonStr(&w, xv);
    }
    if (y) |yv| {
        try w.writeAll(",\"y\":");
        try eval.writeJsonStr(&w, yv);
    }
    try w.writeAll("}");
    return alloc.dupe(u8, w.buffered());
}

// ---------- CLI efimero ----------

fn cliErr(err: *Io.Writer, msg: []const u8) u8 {
    err.writeAll(msg) catch {};
    err.flush() catch {};
    return 2;
}

const FLAGS = [_][]const u8{
    "--help", "--help-topic", "--version", "--expr", "-e", "--digits", "-d",
    "--frac", "--op",     "--a",       "--b",    "--m", "--e",      "--prec",
    "--out",  "--px",     "--py",      "--qx",   "--qy", "--k",     "--p",
    "--ca",   "--cb",     "--cn",      "--n",    "--gx", "--gy",
};

fn runCli(io: Io, args: []const [:0]const u8) !u8 {
    var expr: ?[]const u8 = null;
    var digits: ?u8 = null;
    var frac: bool = false;
    var help_topic: ?[]const u8 = null;
    var big = BigReq{ .op = "", .a = "" };
    var big_mode = false;

    var out_buf: [2048]u8 = undefined;
    var out_w: Io.File.Writer = .initStreaming(.stdout(), io, &out_buf);
    var out: *Io.Writer = &out_w.interface;
    var err_buf: [512]u8 = undefined;
    var err_w: Io.File.Writer = .initStreaming(.stderr(), io, &err_buf);
    var err: *Io.Writer = &err_w.interface;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a: []const u8 = args[i];
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "help")) {
            if (i + 1 < args.len and args[i + 1].len > 0 and args[i + 1][0] != '-') {
                if (ayuda.topicMd(args[i + 1]) != null) {
                    help_topic = args[i + 1];
                    i += 1;
                    continue;
                }
            }
            try out.writeAll(ayuda.USAGE_CLI ++ "\n");
            try out.flush();
            return 0;
        } else if (std.mem.eql(u8, a, "--version") or std.mem.eql(u8, a, "-V")) {
            try out.print("{s} {s}\n", .{ registro.NOMBRE, registro.VERSION });
            try out.flush();
            return 0;
        } else if (std.mem.eql(u8, a, "--expr") or std.mem.eql(u8, a, "-e")) {
            i += 1;
            if (i >= args.len) {
                try err.writeAll("Error: falta valor para --expr\n");
                try err.flush();
                return 2;
            }
            expr = args[i];
        } else if (std.mem.startsWith(u8, a, "--expr=")) {
            expr = a["--expr=".len..];
        } else if (std.mem.eql(u8, a, "--digits") or std.mem.eql(u8, a, "-d")) {
            i += 1;
            if (i >= args.len) {
                try err.writeAll("Error: falta valor para --digits\n");
                try err.flush();
                return 2;
            }
            digits = std.fmt.parseInt(u8, args[i], 10) catch {
                try err.writeAll("Error: --digits debe ser 0-15\n");
                try err.flush();
                return 2;
            };
            if (digits.? > 15) {
                try err.writeAll("Error: --digits debe ser 0-15\n");
                try err.flush();
                return 2;
            }
        } else if (std.mem.startsWith(u8, a, "--digits=")) {
            const v = a["--digits=".len..];
            digits = std.fmt.parseInt(u8, v, 10) catch {
                try err.writeAll("Error: --digits debe ser 0-15\n");
                try err.flush();
                return 2;
            };
            if (digits.? > 15) {
                try err.writeAll("Error: --digits debe ser 0-15\n");
                try err.flush();
                return 2;
            }
        } else if (std.mem.eql(u8, a, "--help-topic")) {
            i += 1;
            if (i >= args.len) {
                try err.writeAll("Error: falta valor para --help-topic\n");
                try err.flush();
                return 2;
            }
            help_topic = args[i];
        } else if (std.mem.startsWith(u8, a, "--help-topic=")) {
            help_topic = a["--help-topic=".len..];
        } else if (std.mem.eql(u8, a, "--frac")) {
            frac = true;
        } else if (std.mem.eql(u8, a, "--op")) {
            i += 1;
            if (i >= args.len) return cliErr(err, "Error: falta valor para --op\n");
            big.op = args[i];
            big_mode = true;
        } else if (std.mem.startsWith(u8, a, "--op=")) {
            big.op = a["--op=".len..];
            big_mode = true;
        } else if (std.mem.eql(u8, a, "--a") or std.mem.eql(u8, a, "--b") or std.mem.eql(u8, a, "--m") or std.mem.eql(u8, a, "--e")) {
            i += 1;
            if (i >= args.len) return cliErr(err, "Error: falta valor\n");
            if (a[2] == 'a') big.a = args[i];
            if (a[2] == 'b') big.b = args[i];
            if (a[2] == 'm') big.m = args[i];
            if (a[2] == 'e') big.e = args[i];
            big_mode = true;
        } else if (std.mem.eql(u8, a, "--prec")) {
            i += 1;
            if (i >= args.len) return cliErr(err, "Error: falta valor para --prec\n");
            big.prec = std.fmt.parseInt(u16, args[i], 10) catch return cliErr(err, "Error: --prec debe ser 1-500\n");
            big_mode = true;
        } else if (std.mem.startsWith(u8, a, "--prec=")) {
            big.prec = std.fmt.parseInt(u16, a["--prec=".len..], 10) catch return cliErr(err, "Error: --prec debe ser 1-500\n");
            big_mode = true;
        } else if (std.mem.eql(u8, a, "--out")) {
            i += 1;
            if (i >= args.len) return cliErr(err, "Error: falta valor para --out\n");
            big.out = args[i];
            big_mode = true;
        } else if (std.mem.startsWith(u8, a, "--out=")) {
            big.out = a["--out=".len..];
            big_mode = true;
        } else if (std.mem.eql(u8, a, "--px") or std.mem.eql(u8, a, "--py") or std.mem.eql(u8, a, "--qx") or std.mem.eql(u8, a, "--qy") or std.mem.eql(u8, a, "--k") or std.mem.eql(u8, a, "--p") or std.mem.eql(u8, a, "--ca") or std.mem.eql(u8, a, "--cb") or std.mem.eql(u8, a, "--cn") or std.mem.eql(u8, a, "--n") or std.mem.eql(u8, a, "--gx") or std.mem.eql(u8, a, "--gy")) {
            i += 1;
            if (i >= args.len) return cliErr(err, "Error: falta valor\n");
            if (std.mem.eql(u8, a, "--px")) big.px = args[i];
            if (std.mem.eql(u8, a, "--py")) big.py = args[i];
            if (std.mem.eql(u8, a, "--qx")) big.qx = args[i];
            if (std.mem.eql(u8, a, "--qy")) big.qy = args[i];
            if (std.mem.eql(u8, a, "--k")) big.k = args[i];
            if (std.mem.eql(u8, a, "--p")) big.p = args[i];
            if (std.mem.eql(u8, a, "--ca")) big.ca = args[i];
            if (std.mem.eql(u8, a, "--cb")) big.cb = args[i];
            if (std.mem.eql(u8, a, "--cn") or std.mem.eql(u8, a, "--n")) big.cn = args[i];
            if (std.mem.eql(u8, a, "--gx")) big.gx = args[i];
            if (std.mem.eql(u8, a, "--gy")) big.gy = args[i];
            big_mode = true;
        } else if (std.mem.startsWith(u8, a, "--p=") or std.mem.startsWith(u8, a, "--ca=") or std.mem.startsWith(u8, a, "--cb=") or std.mem.startsWith(u8, a, "--cn=") or std.mem.startsWith(u8, a, "--n=") or std.mem.startsWith(u8, a, "--gx=") or std.mem.startsWith(u8, a, "--gy=") or std.mem.startsWith(u8, a, "--px=") or std.mem.startsWith(u8, a, "--py=") or std.mem.startsWith(u8, a, "--qx=") or std.mem.startsWith(u8, a, "--qy=") or std.mem.startsWith(u8, a, "--k=") or std.mem.startsWith(u8, a, "--a=") or std.mem.startsWith(u8, a, "--b=") or std.mem.startsWith(u8, a, "--m=") or std.mem.startsWith(u8, a, "--e=")) {
            const eq = std.mem.indexOfScalar(u8, a, '=') orelse return cliErr(err, "Error: formato --x=v\n");
            const key = a[0..eq];
            const val: [:0]const u8 = args[i][eq + 1 ..];
            if (std.mem.eql(u8, key, "--px")) {
                big.px = val;
            } else if (std.mem.eql(u8, key, "--py")) {
                big.py = val;
            } else if (std.mem.eql(u8, key, "--qx")) {
                big.qx = val;
            } else if (std.mem.eql(u8, key, "--qy")) {
                big.qy = val;
            } else if (std.mem.eql(u8, key, "--k")) {
                big.k = val;
            } else if (std.mem.eql(u8, key, "--a")) {
                big.a = val;
            } else if (std.mem.eql(u8, key, "--b")) {
                big.b = val;
            } else if (std.mem.eql(u8, key, "--m")) {
                big.m = val;
            } else if (std.mem.eql(u8, key, "--e")) {
                big.e = val;
            } else if (std.mem.eql(u8, key, "--p")) {
                big.p = val;
            } else if (std.mem.eql(u8, key, "--ca")) {
                big.ca = val;
            } else if (std.mem.eql(u8, key, "--cb")) {
                big.cb = val;
            } else if (std.mem.eql(u8, key, "--cn") or std.mem.eql(u8, key, "--n")) {
                big.cn = val;
            } else if (std.mem.eql(u8, key, "--gx")) {
                big.gx = val;
            } else if (std.mem.eql(u8, key, "--gy")) {
                big.gy = val;
            }
            big_mode = true;
        } else {
            try err.print("Error: argumento desconocido: {s}\n", .{a});
            if (ayuda.sugerir(a, FLAGS[0..])) |s| try err.print("¿Quisiste decir {s}?\n", .{s});
            try err.print("Usa `math --help` para ver las opciones.\n", .{});
            try err.flush();
            return 2;
        }
    }

    if (help_topic) |t| {
        const md = ayuda.topicMd(t) orelse {
            try err.print("Error: tema desconocido: {s} (temas: {s})\n", .{ t, ayuda.TOPICS });
            try err.flush();
            return 2;
        };
        try out.writeAll(md);
        try out.writeAll("\n");
        try out.flush();
        return 0;
    }

    if (big_mode) {
        if (big.prec < 1 or big.prec > 500) return cliErr(err, "Error: --prec debe ser 1-500\n");
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        var msg: []const u8 = "Invalid params";
        const json = bigJson(alloc, big, &msg) catch |er| {
            const m: []const u8 = switch (er) {
                error.DivZero => "Error: division entre cero",
                error.NoInverse => "Error: sin inverso modular (gcd(a,m) != 1)",
                error.TooBig => "Error: demasiado grande (max 16384 bits)",
                error.Invalid => msg,
                else => "Error: fallo de calculo",
            };
            try err.writeAll(m);
            try err.writeAll("\n");
            try err.flush();
            return 2;
        };
        defer alloc.free(json);
        try out.writeAll(json);
        try out.writeAll("\n");
        try out.flush();
        return 0;
    }

    const e = expr orelse {
        try err.writeAll("Error: falta --expr. Usa --help.\n");
        try err.flush();
        return 2;
    };
    if (e.len > 4000) {
        try err.writeAll("Error: --expr demasiado larga (max 4000)\n");
        try err.flush();
        return 2;
    }
    var pos: usize = 0;
    const v = eval.evaluate(e, &pos) catch |er| {
        var mbuf: [128]u8 = undefined;
        try err.writeAll(eval.evalMessage(er, pos, &mbuf));
        try err.writeAll("\n");
        try err.flush();
        return 2;
    };
    if (!std.math.isFinite(v) or !std.math.isFinite(eval.roundDigits(v, digits))) {
        try err.writeAll("Error: desbordamiento, resultado no finito (infinito)\n");
        try err.flush();
        return 2;
    }
    var jbuf: [8192]u8 = undefined;
    var jw: Io.Writer = .fixed(&jbuf);
    eval.writeCalcJson(&jw, std.mem.trim(u8, e, " \t\r\n"), v, digits, frac) catch {
        try err.writeAll("Error: expresion demasiado larga (max ~8KB de respuesta)\n");
        try err.flush();
        return 2;
    };
    try out.writeAll(jw.buffered());
    try out.writeAll("\n");
    try out.flush();
    return 0;
}
