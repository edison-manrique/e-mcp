const std = @import("std");
const Io = std.Io;
const fstool = @import("../fs/fstool.zig");
const exectool = @import("../exec/exectool.zig");
const systool = @import("../core/systool.zig");
const job = @import("../exec/job.zig");
const jsonw = @import("../core/jsonw.zig");

// (movido de main.zig) Utilidades del CLI efimero: salida/errores, parsing de
// valores, ejecucion compartida y emisor de listados.
pub fn cliOut(io: Io, buf: []u8) Io.File.Writer {
    return .initStreaming(.stdout(), io, buf);
}

pub fn cliErr(err: *Io.Writer, msg: []const u8) u8 {
    err.writeAll(msg) catch {};
    err.flush() catch {};
    return 2;
}

pub fn toma(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* + 1 >= args.len) return null;
    const v: []const u8 = args[i.* + 1];
    // `--` escapa el siguiente token como valor literal (aunque
    // empiece con `--`): `--exec -- --raro`.
    if (std.mem.eql(u8, v, "--")) {
        if (i.* + 2 >= args.len) return null;
        i.* += 2;
        return args[i.*];
    }
    if (std.mem.startsWith(u8, v, "--")) return null;
    i.* += 1;
    return v;
}

pub fn parseU(obj: []const u8) ?usize {
    return std.fmt.parseInt(usize, obj, 10) catch null;
}

pub fn cliRango(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, path: []const u8) u8 {
    const w = fstool.readWindow(gpa, io, path, 0, 1, 512, false) catch
        return cliErr(err, "Error: línea fuera de rango.\n");
    defer gpa.free(w.texto);
    var mbuf: [256]u8 = undefined;
    var mw: Io.Writer = .fixed(&mbuf);
    mw.print("Error: línea fuera de rango (1-{d}).\n", .{w.total}) catch
        return cliErr(err, "Error: línea fuera de rango.\n");
    return cliErr(err, mw.buffered());
}

pub fn cliErr2(err: *Io.Writer, e: anyerror) u8 {
    var mbuf: [256]u8 = undefined;
    var mw: Io.Writer = .fixed(&mbuf);
    mw.writeAll("Error: ") catch {};
    mw.writeAll(fstool.msgDe(e)) catch {};
    mw.writeAll("\n") catch {};
    return cliErr(err, mw.buffered());
}

pub fn cliErrMsg(err: *Io.Writer, msg: []const u8) u8 {
    var mbuf: [512]u8 = undefined;
    var mw: Io.Writer = .fixed(&mbuf);
    mw.writeAll("Error: ") catch {};
    mw.writeAll(msg[0..@min(msg.len, 400)]) catch {};
    mw.writeAll("\n") catch {};
    return cliErr(err, mw.buffered());
}

pub fn cliErrJob(err: *Io.Writer, e: anyerror) u8 {
    var mbuf: [256]u8 = undefined;
    var mw: Io.Writer = .fixed(&mbuf);
    mw.writeAll("Error: ") catch {};
    mw.writeAll(job.msgDe(e)) catch {};
    mw.writeAll("\n") catch {};
    return cliErr(err, mw.buffered());
}

// Lee stdin hasta `tope`+1 (para detectar exceso). Dueño: gpa.
pub fn leeStdin(gpa: std.mem.Allocator, io: Io, tope: usize) ![]u8 {
    var sbuf: [4096]u8 = undefined;
    var sr: Io.File.Reader = .initStreaming(.stdin(), io, &sbuf);
    return sr.interface.allocRemaining(gpa, Io.Limit.limited(tope)) catch |e| switch (e) {
        error.ReadFailed => return sr.err orelse e,
        else => |x| return x,
    };
}

// Quita el BOM UTF-8 inicial (PowerShell y --cmd-file suelen añadirlo:
// si no, cmd recibe "\xEF\xBB\xBFecho" y falla con "no se reconoce").
pub fn sinBom(s: []const u8) []const u8 {
    if (s.len >= 3 and s[0] == 0xEF and s[1] == 0xBB and s[2] == 0xBF) return s[3..];
    return s;
}

test "sinBom quita el BOM UTF-8 y respeta el resto" {
    const t = std.testing;
    try t.expectEqualStrings("hola", sinBom("\xEF\xBB\xBFhola"));
    try t.expectEqualStrings("hola", sinBom("hola"));
    try t.expectEqualStrings("", sinBom("\xEF\xBB\xBF"));
    try t.expectEqualStrings("\xEF\xBB", sinBom("\xEF\xBB")); // incompleto: no recorta
}

// Ejecución CLI compartida (max/encoding/base64/force/cwd/auditoría/emit).
pub fn cliExecCon(
    gpa: std.mem.Allocator,
    io: Io,
    err: *Io.Writer,
    jw: *Io.Writer,
    c: []const u8,
    timeout: u32,
    max_s: ?[]const u8,
    cwd: ?[]const u8,
    enc_s: []const u8,
    b64_b: bool,
    force_b: bool,
) !u8 {
    const max: usize = if (max_s) |s| parseU(s) orelse return cliErr(err, "Error: --max debe ser entero 512-8192\n") else exectool.DEF_MAX_BYTES;
    if (max < exectool.MIN_MAX_BYTES or max > exectool.MAX_MAX_BYTES) return cliErr(err, "Error: --max debe ser entero 512-8192\n");
    const enc = exectool.parseCodif(enc_s) orelse return cliErr(err, "Error: --encoding debe ser auto|utf8|oem|raw\n");
    const cw: ?[]const u8 = if (cwd) |d| (if (d.len == 0) null else d) else null;
    fstool.checkCwd(io, cw) catch |e| {
        return cliErrMsg(err, fstool.msgDe(e));
    };
    const t0 = jsonw.ahoraMs(io);
    const r = exectool.correr(gpa, io, c, cw, timeout, max, enc, b64_b, force_b) catch |e| {
        return cliErrMsg(err, exectool.msgDe(e));
    };
    const ms = jsonw.ahoraMs(io) - t0;
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    const rc = jsonw.recorta(r.stdout, r.stderr);
    const ex: ?u8 = if (r.term) |tt| exectool.exitDe(tt) else null;
    jsonw.emitExec(jw, ex, rc.a, rc.b, rc.cortado or r.truncado, r.timed_out, r.encoding) catch return cliErr(err, "Error: respuesta demasiado larga\n");
    const ec: i64 = if (ex) |x| x else -1;
    systool.auditar(gpa, io, "exec", c, cw, ec, ms);
    return 0;
}

// Emite {"path","total","truncated","entries":[...]} con presupuesto ~7KB.
pub fn emitCliLista(jw: *Io.Writer, p: []const u8, items: []fstool.Entrada, total: usize, trunc0: bool) Io.Writer.Error!void {
    var incl = items.len;
    var usado: usize = 0;
    for (items, 0..) |e, idx| {
        const costo = 64 + e.nombre.len * 2;
        if (usado + costo > 7168) {
            incl = idx;
            break;
        }
        usado += costo;
    }
    const trunc = trunc0 or incl < items.len;
    try jw.writeAll("{\"path\":");
    try jsonw.writeJsonStr(jw, p);
    try jw.print(",\"total\":{d},\"truncated\":", .{total});
    try jw.writeAll(if (trunc) "true,\"entries\":[" else "false,\"entries\":[");
    for (items[0..incl], 0..) |e, idx| {
        if (idx > 0) try jw.writeAll(",");
        try jw.writeAll("{\"name\":");
        try jsonw.writeJsonStr(jw, e.nombre);
        try jw.writeAll(",\"kind\":\"");
        try jw.writeAll(jsonw.kindStr(e.kind));
        try jw.writeAll("\",\"size\":");
        if (e.tam) |s| {
            try jw.print("{d}", .{s});
        } else {
            try jw.writeAll("null");
        }
        try jw.writeAll("}");
    }
    try jw.writeAll("]}");
}
