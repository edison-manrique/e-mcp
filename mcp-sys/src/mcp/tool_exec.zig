const std = @import("std");
const Io = std.Io;
const proto = @import("../core/proto.zig");
const fstool = @import("../fs/fstool.zig");
const exectool = @import("../exec/exectool.zig");
const systool = @import("../core/systool.zig");
const job = @import("../exec/job.zig");
const jsonw = @import("../core/jsonw.zig");
const arg = @import("../core/args.zig");
const tools = @import("tools.zig");

// (movido de main.zig) Handlers `exec` (comando con timeout) y `job`
// (comandos en segundo plano).
pub fn runExec(gpa: std.mem.Allocator, ctx: proto.Ctx) Io.Writer.Error!void {
    const cmd = arg.sOpt(ctx.args, "cmd") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cmd debe ser texto.");
    const c = cmd orelse "";
    if (c.len == 0)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta cmd. Ej: {\"cmd\":\"echo hola\"}.");
    if (c.len > exectool.MAX_CMD)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cmd demasiado largo (max 4000).");
    const cwd = arg.sOpt(ctx.args, "cwd") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cwd debe ser texto.");
    if (cwd) |d| {
        if (d.len > fstool.MAX_PATH_LEN)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cwd demasiado largo (max 2000).");
    }
    const t = arg.iOpt(ctx.args, "timeout_ms") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: timeout_ms debe ser entero 100-120000.");
    const timeout: u32 = @intCast(t orelse exectool.DEF_TIMEOUT_MS);
    if (timeout < exectool.MIN_TIMEOUT_MS or timeout > exectool.MAX_TIMEOUT_MS)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: timeout_ms debe ser entero 100-120000. Tip: para más usa job.");
    const mb = arg.iOpt(ctx.args, "max_bytes") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: max_bytes debe ser entero 512-8192.");
    const max: usize = @intCast(mb orelse exectool.DEF_MAX_BYTES);
    if (max < exectool.MIN_MAX_BYTES or max > exectool.MAX_MAX_BYTES)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: max_bytes debe ser entero 512-8192. Tip: filtra con head/grep.");
    const enc_s = proto.argStr(ctx.args, "encoding", "auto");
    const enc = exectool.parseCodif(enc_s) orelse
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: encoding debe ser auto|utf8|oem|raw.");
    const b64 = arg.bOpt(ctx.args, "base64") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: base64 debe ser true|false.");
    const fc = arg.bOpt(ctx.args, "force") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: force debe ser true|false.");

    const cw: ?[]const u8 = if (cwd) |d| (if (d.len == 0) null else d) else null;
    fstool.checkCwd(ctx.io, cw) catch |e|
        return proto.sendToolError(ctx.out, ctx.id, fstool.msgDe(e));
    const t0 = jsonw.ahoraMs(ctx.io);
    const r = exectool.correr(gpa, ctx.io, c, cw, timeout, max, enc, b64 orelse false, fc orelse false) catch |e|
        return proto.sendToolError(ctx.out, ctx.id, exectool.msgDe(e));
    const ms = jsonw.ahoraMs(ctx.io) - t0;
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    const rc = jsonw.recorta(r.stdout, r.stderr);
    var ibuf: [24576]u8 = undefined;
    var jw: Io.Writer = .fixed(&ibuf);
    const ex: ?u8 = if (r.term) |tt| exectool.exitDe(tt) else null;
    jsonw.emitExec(&jw, ex, rc.a, rc.b, rc.cortado or r.truncado, r.timed_out, r.encoding) catch
        return proto.sendToolError(ctx.out, ctx.id, "Respuesta demasiado larga.");
    try proto.sendToolText(ctx.out, ctx.id, jw.buffered());
    const ec: i64 = if (ex) |x| x else -1;
    systool.auditar(gpa, ctx.io, "exec", c, cw, ec, ms);
}
pub fn runJob(gpa: std.mem.Allocator, ctx: proto.Ctx) Io.Writer.Error!void {
    const o = arg.sOpt(ctx.args, "op") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: op debe ser texto.");
    const op = o orelse
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta op (start|poll|kill|list|forget).");
    var ibuf: [12288]u8 = undefined;
    var jw: Io.Writer = .fixed(&ibuf);
    const j: *Io.Writer = &jw;
    if (std.mem.eql(u8, op, "start")) {
        const c = arg.sOpt(ctx.args, "cmd") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cmd debe ser texto.");
        const cmd = c orelse "";
        if (cmd.len == 0)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta cmd. Ej: {\"op\":\"start\",\"cmd\":\"make -j4\"}.");
        const cw = arg.sOpt(ctx.args, "cwd") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cwd debe ser texto.");
        if (cw != null and cw.?.len > fstool.MAX_PATH_LEN)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: cwd demasiado largo (max 2000).");
        const t = arg.iOpt(ctx.args, "timeout_ms") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: timeout_ms debe ser entero 1000-3600000.");
        const timeout: u32 = @intCast(t orelse job.DEF_BG_TIMEOUT);
        if (timeout < job.MIN_BG_TIMEOUT or timeout > job.MAX_BG_TIMEOUT)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: timeout_ms debe ser entero 1000-3600000 (def. 300000).");
        const cwd: ?[]const u8 = if (cw) |d| (if (d.len == 0) null else d) else null;
        fstool.checkCwd(ctx.io, cw) catch |e|
            return proto.sendToolError(ctx.out, ctx.id, fstool.msgDe(e));
        const fc = arg.bOpt(ctx.args, "force") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: force debe ser true|false.");
        if (!(fc orelse false) and exectool.esPeligroso(cmd))
            return proto.sendToolError(ctx.out, ctx.id, exectool.msgDe(error.Peligroso));
        const t0 = jsonw.ahoraMs(ctx.io);
        const r = job.lanzar(gpa, ctx.io, cmd, cwd, timeout) catch |e|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(e));
        defer gpa.free(r.id);
        defer gpa.free(r.dir);
        systool.auditar(gpa, ctx.io, "job-start", cmd, cwd, -1, jsonw.ahoraMs(ctx.io) - t0);
        j.writeAll("{\"job\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, r.id) catch return tools.errLarga(ctx);
        j.print(",\"pid\":{d},\"timeout_ms\":{d},\"dir\":", .{ r.pid, timeout }) catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, r.dir) catch return tools.errLarga(ctx);
        j.writeAll("}") catch return tools.errLarga(ctx);
    } else if (std.mem.eql(u8, op, "poll")) {
        const jb = arg.sOpt(ctx.args, "job") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: job debe ser texto.");
        const id = jb orelse
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta job (id de start).");
        const mb = arg.iOpt(ctx.args, "max_bytes") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: max_bytes debe ser entero 512-4096.");
        const max: usize = @intCast(mb orelse exectool.DEF_MAX_BYTES);
        if (max < exectool.MIN_MAX_BYTES or max > exectool.MAX_MAX_BYTES)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: max_bytes debe ser entero 512-4096.");
        const e = job.sondear(gpa, ctx.io, id) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(er));
        const sco = job.colaLog(gpa, ctx.io, id, "out.log", max) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(er));
        defer gpa.free(sco);
        const sce = job.colaLog(gpa, ctx.io, id, "err.log", max) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(er));
        defer gpa.free(sce);
        const enc_s = proto.argStr(ctx.args, "encoding", "auto");
        const enc = exectool.parseCodif(enc_s) orelse
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: encoding debe ser auto|utf8|oem|raw.");
        const b64 = arg.bOpt(ctx.args, "base64") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: base64 debe ser true|false.");
        const do_ = exectool.decodificar(gpa, sco, enc, b64 orelse false) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, exectool.msgDe(er));
        defer gpa.free(do_.texto);
        const de_ = exectool.decodificar(gpa, sce, enc, b64 orelse false) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, exectool.msgDe(er));
        defer gpa.free(de_.texto);
        const so = do_.texto;
        const se = de_.texto;
        const enc_out: []const u8 = if (de_.texto.len == 0) do_.encoding else if (do_.texto.len == 0) de_.encoding else if (std.mem.eql(u8, do_.encoding, de_.encoding)) do_.encoding else "mixed";
        const ln = arg.iOpt(ctx.args, "lines") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: lines debe ser entero 0-200.");
        const nl: usize = @intCast(ln orelse 0);
        if (nl > job.MAX_TAIL_LINES)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: lines debe ser entero 0-200.");
        const so_f = job.ultimasLineas(so, nl);
        const se_f = job.ultimasLineas(se, nl);
        j.writeAll("{\"job\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, id) catch return tools.errLarga(ctx);
        j.print(",\"running\":", .{}) catch return tools.errLarga(ctx);
        j.writeAll(if (e.running) "true" else "false") catch return tools.errLarga(ctx);
        j.writeAll(",\"exit\":") catch return tools.errLarga(ctx);
        if (e.exit) |x| {
            j.print("{d}", .{x}) catch return tools.errLarga(ctx);
        } else {
            j.writeAll("null") catch return tools.errLarga(ctx);
        }
        j.print(",\"elapsed_ms\":{d},\"timed_out\":", .{e.elapsed_ms}) catch return tools.errLarga(ctx);
        j.writeAll(if (e.timed_out) "true" else "false") catch return tools.errLarga(ctx);
        j.writeAll(",\"killed\":") catch return tools.errLarga(ctx);
        j.writeAll(if (e.killed) "true" else "false") catch return tools.errLarga(ctx);
        if (e.nota.len > 0) {
            j.writeAll(",\"note\":") catch return tools.errLarga(ctx);
            jsonw.writeJsonStr(j, e.nota) catch return tools.errLarga(ctx);
        }
        j.writeAll(",\"out\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, so_f) catch return tools.errLarga(ctx);
        j.writeAll(",\"err\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, se_f) catch return tools.errLarga(ctx);
        j.writeAll(",\"encoding\":\"") catch return tools.errLarga(ctx);
        j.writeAll(enc_out) catch return tools.errLarga(ctx);
        j.writeAll("\"}") catch return tools.errLarga(ctx);
    } else if (std.mem.eql(u8, op, "kill")) {
        const jb = arg.sOpt(ctx.args, "job") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: job debe ser texto.");
        const id = jb orelse
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta job.");
        const k = job.detener(gpa, ctx.io, id) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(er));
        j.writeAll("{\"job\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, id) catch return tools.errLarga(ctx);
        j.writeAll(",\"killed\":") catch return tools.errLarga(ctx);
        j.writeAll(if (k) "true}" else "false}") catch return tools.errLarga(ctx);
    } else if (std.mem.eql(u8, op, "list")) {
        var l = job.listar(gpa, ctx.io) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(er));
        defer job.freeLista(gpa, &l);
        j.print("{{\"total\":{d},\"truncated\":", .{l.total}) catch return tools.errLarga(ctx);
        j.writeAll(if (l.truncado) "true,\"jobs\":[" else "false,\"jobs\":[") catch return tools.errLarga(ctx);
        for (l.items, 0..) |it, i| {
            if (i > 0) j.writeAll(",") catch return tools.errLarga(ctx);
            j.writeAll("{\"job\":") catch return tools.errLarga(ctx);
            jsonw.writeJsonStr(j, it.id) catch return tools.errLarga(ctx);
            j.print(",\"pid\":{d},\"cmd\":", .{it.pid}) catch return tools.errLarga(ctx);
            jsonw.writeJsonStr(j, it.cmd) catch return tools.errLarga(ctx);
            j.writeAll(",\"running\":") catch return tools.errLarga(ctx);
            j.writeAll(if (it.running) "true" else "false") catch return tools.errLarga(ctx);
            j.print(",\"elapsed_ms\":{d}}}", .{it.elapsed_ms}) catch return tools.errLarga(ctx);
        }
        j.writeAll("]}") catch return tools.errLarga(ctx);
    } else if (std.mem.eql(u8, op, "forget")) {
        const jb = arg.sOpt(ctx.args, "job") catch
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: job debe ser texto.");
        const id = jb orelse
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta job.");
        job.olvidar(gpa, ctx.io, id) catch |er|
            return proto.sendToolError(ctx.out, ctx.id, job.msgDe(er));
        j.writeAll("{\"job\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, id) catch return tools.errLarga(ctx);
        j.writeAll(",\"forgotten\":true}") catch return tools.errLarga(ctx);
    } else {
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: op debe ser start|poll|kill|list|forget.");
    }
    try proto.sendToolText(ctx.out, ctx.id, jw.buffered());
}
