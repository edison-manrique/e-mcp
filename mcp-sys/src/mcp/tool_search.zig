const std = @import("std");
const Io = std.Io;
const proto = @import("../core/proto.zig");
const fstool = @import("../fs/fstool.zig");
const jsonw = @import("../core/jsonw.zig");
const arg = @import("../core/args.zig");
const tools = @import("tools.zig");

// (movido de main.zig) Handler `search` (contenido y modo files) y sus
// emisores de resultados.
pub fn runSearch(gpa: std.mem.Allocator, ctx: proto.Ctx) Io.Writer.Error!void {
    const pt = arg.sOpt(ctx.args, "pattern") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: pattern debe ser texto.");
    const pattern = pt orelse "";
    if (pattern.len == 0)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: falta pattern. Ej: {\"pattern\":\"timeout\"}.");
    if (pattern.len > fstool.MAX_PATRON)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: pattern demasiado largo (max 500).");
    const path = proto.argStr(ctx.args, "path", ".");
    const rec = arg.bOpt(ctx.args, "recursive") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: recursive debe ser true|false.");
    const glob = proto.argStr(ctx.args, "glob", "");
    const m = arg.iOpt(ctx.args, "max") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: max debe ser entero 1-500.");
    const max: usize = @intCast(m orelse 50);
    if (max < 1 or max > fstool.MAX_MATCH)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: max debe ser entero 1-500.");
    const cs = arg.bOpt(ctx.args, "case") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: case debe ser true|false.");
    const cx = arg.iOpt(ctx.args, "context") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: context debe ser entero 0-5.");
    const contexto: usize = @intCast(cx orelse 0);
    if (contexto > fstool.MAX_CTX)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: context debe ser entero 0-5.");
    const wd = arg.bOpt(ctx.args, "word") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: word debe ser true|false.");
    const excl = proto.argStr(ctx.args, "exclude", "");
    const rgx = arg.bOpt(ctx.args, "regex") catch
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: regex debe ser true|false.");
    const modo = proto.argStr(ctx.args, "mode", "content");
    if (std.mem.eql(u8, modo, "files")) {
        var n = fstool.buscarNombres(gpa, ctx.io, .{
            .raiz = path,
            .patron = pattern,
            .sensible = cs orelse false,
            .recursivo = rec orelse true,
            .glob = glob,
            .max = max,
            .excluir = excl,
            .regex = rgx orelse false,
        }) catch |e|
            return proto.sendToolError(ctx.out, ctx.id, fstool.msgDe(e));
        defer fstool.freeNombres(gpa, &n);
        return emitirArchivos(ctx.out, ctx.id, path, pattern, rgx orelse false, n.entradas, n.total, n.omitidos, n.truncado);
    }
    var s = fstool.buscar(gpa, ctx.io, .{
        .raiz = path,
        .patron = pattern,
        .sensible = cs orelse false,
        .recursivo = rec orelse true,
        .glob = glob,
        .max = max,
        .contexto = contexto,
        .palabra = wd orelse false,
        .excluir = excl,
        .regex = rgx orelse false,
    }) catch |e|
        return proto.sendToolError(ctx.out, ctx.id, fstool.msgDe(e));
    defer fstool.freeSearch(gpa, &s);
    // Presupuesto del wire: incluye matches hasta ~7KB.
    var incl = s.matches.len;
    var usado: usize = 0;
    for (s.matches, 0..) |e, i| {
        const costo = 64 + e.archivo.len * 2 + @min(e.texto.len, 320) + e.antes.len + e.despues.len;
        if (usado + costo > 7168) {
            incl = i;
            break;
        }
        usado += costo;
    }
    const trunc = s.truncado or incl < s.matches.len;
    const con_ctx = contexto > 0;
    var ibuf: [24576]u8 = undefined;
    var jw: Io.Writer = .fixed(&ibuf);
    const j: *Io.Writer = &jw;
    j.writeAll("{\"path\":") catch return tools.errLarga(ctx);
    jsonw.writeJsonStr(j, path) catch return tools.errLarga(ctx);
    j.writeAll(",\"pattern\":") catch return tools.errLarga(ctx);
    jsonw.writeJsonStr(j, pattern) catch return tools.errLarga(ctx);
    j.print(",\"regex\":{s}", .{if (rgx orelse false) "true" else "false"}) catch return tools.errLarga(ctx);
    j.print(",\"total\":{d},\"skipped\":{d},\"truncated\":", .{ s.total, s.omitidos }) catch return tools.errLarga(ctx);
    j.writeAll(if (trunc) "true,\"matches\":[" else "false,\"matches\":[") catch return tools.errLarga(ctx);
    for (s.matches[0..incl], 0..) |e, i| {
        if (i > 0) j.writeAll(",") catch return tools.errLarga(ctx);
        j.writeAll("{\"file\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, e.archivo) catch return tools.errLarga(ctx);
        j.print(",\"line\":{d},\"col\":{d},\"text\":", .{ e.linea, e.col }) catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, e.texto) catch return tools.errLarga(ctx);
        j.writeAll(",\"match\":") catch return tools.errLarga(ctx);
        jsonw.writeJsonStr(j, e.matched) catch return tools.errLarga(ctx);
        if (con_ctx) {
            j.writeAll(",\"before\":[") catch return tools.errLarga(ctx);
            jsonw.writeStrLines(j, e.antes) catch return tools.errLarga(ctx);
            j.writeAll("],\"after\":[") catch return tools.errLarga(ctx);
            jsonw.writeStrLines(j, e.despues) catch return tools.errLarga(ctx);
            j.writeAll("]") catch return tools.errLarga(ctx);
        }
        j.writeAll("}") catch return tools.errLarga(ctx);
    }
    j.writeAll("]}") catch return tools.errLarga(ctx);
    try proto.sendToolText(ctx.out, ctx.id, jw.buffered());
}
pub fn emitirArchivos(out: *Io.Writer, id: std.json.Value, path: []const u8, pattern: []const u8, rgx: bool, entradas: []fstool.Entrada, total: usize, omitidos: usize, truncado: bool) Io.Writer.Error!void {
    var incl = entradas.len;
    var usado: usize = 0;
    for (entradas, 0..) |e, i| {
        const costo = 64 + e.nombre.len * 2;
        if (usado + costo > 7168) {
            incl = i;
            break;
        }
        usado += costo;
    }
    var ibuf: [12288]u8 = undefined;
    var jw: Io.Writer = .fixed(&ibuf);
    escribeArchivos(&jw, path, pattern, rgx, entradas, total, omitidos, truncado, incl) catch
        return proto.sendToolError(out, id, "Respuesta demasiado larga.");
    try proto.sendToolText(out, id, jw.buffered());
}
pub fn escribeArchivos(j: *Io.Writer, path: []const u8, pattern: []const u8, rgx: bool, entradas: []fstool.Entrada, total: usize, omitidos: usize, truncado: bool, incl: usize) !void {
    const trunc = truncado or incl < entradas.len;
    try j.writeAll("{\"path\":");
    try jsonw.writeJsonStr(j, path);
    try j.writeAll(",\"pattern\":");
    try jsonw.writeJsonStr(j, pattern);
    try j.writeAll(",\"mode\":\"files\"");
    try j.print(",\"regex\":{s}", .{if (rgx) "true" else "false"});
    try j.print(",\"total\":{d},\"skipped\":{d},\"truncated\":", .{ total, omitidos });
    try j.writeAll(if (trunc) "true,\"entries\":[" else "false,\"entries\":[");
    for (entradas[0..incl], 0..) |e, i| {
        if (i > 0) try j.writeAll(",");
        try j.writeAll("{\"name\":");
        try jsonw.writeJsonStr(j, e.nombre);
        try j.writeAll(",\"kind\":\"");
        try j.writeAll(jsonw.kindStr(e.kind));
        try j.writeAll("\",\"size\":");
        if (e.tam) |s| {
            try j.print("{d}", .{s});
        } else {
            try j.writeAll("null");
        }
        try j.writeAll("}");
    }
    try j.writeAll("]}");
}
