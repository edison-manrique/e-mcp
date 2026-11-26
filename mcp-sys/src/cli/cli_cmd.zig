const std = @import("std");
const Io = std.Io;
const fstool = @import("../fs/fstool.zig");
const exectool = @import("../exec/exectool.zig");
const systool = @import("../core/systool.zig");
const job = @import("../exec/job.zig");
const jsonw = @import("../core/jsonw.zig");
const cli_util = @import("cli_util.zig");

// ---------- CLI: ejecucion por modo ----------
// (movido de cli.zig) Cada funcion recibe las opciones ya parseadas por
// cli.runCli y el writer JSON `jw`; escribe su respuesta y devuelve 0 (ok)
// o un codigo de error (!= 0). El buffer del writer lo vuelca runCli.
pub const Opts = struct {
    exec_cmd: ?[]const u8 = null,
    read_path: ?[]const u8 = null,
    write_path: ?[]const u8 = null,
    edit_path: ?[]const u8 = null,
    list_path: ?[]const u8 = null,
    sys_op: ?[]const u8 = null,
    search_pat: ?[]const u8 = null,
    job_op: ?[]const u8 = null,
    job_id: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    timeout_s: ?[]const u8 = null,
    max_s: ?[]const u8 = null,
    offset_s: ?[]const u8 = null,
    limit_s: ?[]const u8 = null,
    content: ?[]const u8 = null,
    old_s: ?[]const u8 = null,
    new_s: ?[]const u8 = null,
    occ_s: ?[]const u8 = null,
    at_s: ?[]const u8 = null,
    del_s: ?[]const u8 = null,
    pattern: ?[]const u8 = null,
    glob_s: ?[]const u8 = null,
    ctx_s: ?[]const u8 = null,
    excl_s: ?[]const u8 = null,
    depth_s: ?[]const u8 = null,
    lines_s: ?[]const u8 = null,
    path_s: ?[]const u8 = null,
    dest: ?[]const u8 = null,
    name_s: ?[]const u8 = null,
    filter: ?[]const u8 = null,
    cmd_file: ?[]const u8 = null,
    subst: ?[]const u8 = null,
    mode_s: []const u8 = "",
    enc_s: []const u8 = "auto",
    replace_all: bool = false,
    unique_b: bool = false,
    no_rec: bool = false,
    case_b: bool = false,
    no_numbers: bool = false,
    word_b: bool = false,
    regex_b: bool = false,
    files_b: bool = false,
    rec_b: bool = false,
    b64_b: bool = false,
    force_b: bool = false,
    dry_run: bool = false,
};

pub fn doExec(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const exec_cmd = o.exec_cmd;
    const cmd_file = o.cmd_file;
    const timeout_s = o.timeout_s;
    const max_s = o.max_s;
    const cwd = o.cwd;
    const enc_s = o.enc_s;
    const b64_b = o.b64_b;
    const force_b = o.force_b;
    var owned: ?[]u8 = null;
    defer if (owned) |buf| gpa.free(buf);
    if (cmd_file != null and exec_cmd != null) return cli_util.cliErr(err, "Error: usa --exec o --cmd-file, no ambos\n");
    var c: []const u8 = exec_cmd orelse "";
    if (cmd_file) |f| {
        const txt = fstool.readAll(gpa, io, f, exectool.MAX_CMD + 1) catch |e| {
            return cli_util.cliErrMsg(err, fstool.msgDe(e));
        };
        if (txt.len > exectool.MAX_CMD) {
            gpa.free(txt);
            return cli_util.cliErr(err, "Error: --cmd-file excede 4000 bytes\n");
        }
        owned = txt;
        c = cli_util.sinBom(txt);
    } else if (std.mem.eql(u8, c, "-")) {
        const txt = cli_util.leeStdin(gpa, io, exectool.MAX_CMD + 1) catch |e| {
            return cli_util.cliErrMsg(err, fstool.msgDe(e));
        };
        if (txt.len > exectool.MAX_CMD) {
            gpa.free(txt);
            return cli_util.cliErr(err, "Error: stdin excede 4000 bytes\n");
        }
        owned = txt;
        c = cli_util.sinBom(txt);
    }
    if (c.len == 0 or c.len > exectool.MAX_CMD) return cli_util.cliErr(err, "Error: --exec vacío o muy largo (max 4000)\n");
    const timeout: u32 = if (timeout_s) |s| std.fmt.parseInt(u32, s, 10) catch return cli_util.cliErr(err, "Error: --timeout debe ser entero 100-120000\n") else exectool.DEF_TIMEOUT_MS;
    if (timeout < exectool.MIN_TIMEOUT_MS or timeout > exectool.MAX_TIMEOUT_MS) return cli_util.cliErr(err, "Error: --timeout debe ser entero 100-120000\n");
    const rc = cli_util.cliExecCon(gpa, io, err, jw, c, timeout, max_s, cwd, enc_s, b64_b, force_b) catch
        return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    if (rc != 0) return rc;
    return 0;
}

pub fn doRead(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const read_path = o.read_path;
    const offset_s = o.offset_s;
    const limit_s = o.limit_s;
    const max_s = o.max_s;
    const no_numbers = o.no_numbers;
    const p = read_path.?;
    const off: usize = if (offset_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --offset debe ser entero >= 0\n") else 0;
    const lim: usize = if (limit_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --limit debe ser entero 1-1000\n") else 100;
    if (lim < 1 or lim > fstool.MAX_LIST) return cli_util.cliErr(err, "Error: --limit debe ser entero 1-1000\n");
    const max: usize = if (max_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --max debe ser entero 512-8192\n") else 4096;
    if (max < 512 or max > fstool.MAX_READ_BYTES) return cli_util.cliErr(err, "Error: --max debe ser entero 512-8192\n");
    var w = fstool.readWindow(gpa, io, p, off, lim, max, !no_numbers) catch |e| {
        var mbuf: [256]u8 = undefined;
        var mw: Io.Writer = .fixed(&mbuf);
        mw.writeAll("Error: ") catch {};
        mw.writeAll(fstool.msgDe(e)) catch {};
        mw.writeAll("\n") catch {};
        return cli_util.cliErr(err, mw.buffered());
    };
    defer gpa.free(w.texto);
    var texto = w.texto;
    if (texto.len > 7168) {
        var corte: usize = 7168;
        while (corte > 0 and texto[corte] != '\n') corte -= 1;
        texto = texto[0..corte];
        w.truncado = true;
    }
    jsonw.emitRead(jw, p, off, lim, w.total, w.devueltas, w.truncado, texto) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    return 0;
}

pub fn doWrite(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const write_path = o.write_path;
    const content = o.content;
    const mode_s = o.mode_s;
    const p = write_path.?;
    const c = content orelse return cli_util.cliErr(err, "Error: falta --content\n");
    const ms = if (mode_s.len == 0) "overwrite" else mode_s;
    const modo_w = fstool.parseMode(ms) orelse return cli_util.cliErr(err, "Error: --mode debe ser create|overwrite|append\n");
    const out = fstool.writeWholeInfo(gpa, io, p, c, modo_w) catch |e| {
        var mbuf: [256]u8 = undefined;
        var mw: Io.Writer = .fixed(&mbuf);
        mw.writeAll("Error: ") catch {};
        mw.writeAll(fstool.msgDe(e)) catch {};
        mw.writeAll("\n") catch {};
        return cli_util.cliErr(err, mw.buffered());
    };
    const via: ?[]const u8 = if (modo_w == .append) @tagName(out.via) else null;
    jsonw.emitWrite(jw, p, out.bytes, ms, via) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    return 0;
}

pub fn doEdit(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const edit_path = o.edit_path;
    const mode_s = o.mode_s;
    const old_s = o.old_s;
    const new_s = o.new_s;
    const occ_s = o.occ_s;
    const replace_all = o.replace_all;
    const unique_b = o.unique_b;
    const regex_b = o.regex_b;
    const at_s = o.at_s;
    const del_s = o.del_s;
    const p = edit_path.?;
    const ems = if (mode_s.len == 0) "sub" else mode_s;
    const em = fstool.parseEditMode(ems) orelse return cli_util.cliErr(err, "Error: --mode debe ser sub|ins|del\n");
    switch (em) {
        .sub => {
            const oldv = old_s orelse return cli_util.cliErr(err, "Error: falta --old\n");
            const n = new_s orelse return cli_util.cliErr(err, "Error: falta --new\n");
            const oc: usize = if (occ_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --occ debe ser entero >= 1\n") else 1;
            if (oc < 1) return cli_util.cliErr(err, "Error: --occ debe ser entero >= 1\n");
            const r = fstool.editSub(gpa, io, p, oldv, n, replace_all, oc, unique_b, regex_b) catch |e| {
                if (e == error.OccFueraRango) {
                    const hay = fstool.contar(gpa, io, p, oldv, regex_b) catch return cli_util.cliErr(err, "Error: occ fuera de rango\n");
                    var mbuf: [256]u8 = undefined;
                    var mw: Io.Writer = .fixed(&mbuf);
                    mw.print("Error: occ fuera de rango (solo hay {d})\n", .{hay}) catch {};
                    return cli_util.cliErr(err, mw.buffered());
                }
                if (e == error.FuzzyMultiple) {
                    const hay = fstool.countFuzzy(gpa, io, p, oldv) catch return cli_util.cliErr(err, "Error: coincide en varias líneas\n");
                    var mbuf: [256]u8 = undefined;
                    var mw: Io.Writer = .fixed(&mbuf);
                    mw.print("Error: coincide en {d} líneas ignorando espacios\n", .{hay}) catch {};
                    return cli_util.cliErr(err, mw.buffered());
                }
                var mbuf: [256]u8 = undefined;
                var mw: Io.Writer = .fixed(&mbuf);
                mw.writeAll("Error: ") catch {};
                mw.writeAll(fstool.msgDe(e)) catch {};
                mw.writeAll("\n") catch {};
                return cli_util.cliErr(err, mw.buffered());
            };
            jsonw.emitEdit(jw, p, r.replaced, r.total, r.bytes) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        },
        .ins => {
            const n = new_s orelse return cli_util.cliErr(err, "Error: falta --new (texto a insertar)\n");
            if (regex_b) {
                const pat = old_s orelse return cli_util.cliErr(err, "Error: --regex en ins requiere --old (patrón)\n");
                const r = fstool.editInsertRegex(gpa, io, p, pat, n) catch |e| {
                    var mbuf: [256]u8 = undefined;
                    var mw: Io.Writer = .fixed(&mbuf);
                    mw.writeAll("Error: ") catch {};
                    mw.writeAll(fstool.msgDe(e)) catch {};
                    mw.writeAll("\n") catch {};
                    return cli_util.cliErr(err, mw.buffered());
                };
                jsonw.emitEdit(jw, p, r.replaced, r.total, r.bytes) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            } else {
                const at: usize = if (at_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --at debe ser entero >= 1\n") else return cli_util.cliErr(err, "Error: falta --at (línea donde insertar)\n");
                if (at < 1) return cli_util.cliErr(err, "Error: --at debe ser entero >= 1\n");
                const r = fstool.editInsert(gpa, io, p, at, n) catch |e| {
                    if (e == error.LineaFueraDeRango) return cli_util.cliRango(gpa, io, err, p);
                    var mbuf: [256]u8 = undefined;
                    var mw: Io.Writer = .fixed(&mbuf);
                    mw.writeAll("Error: ") catch {};
                    mw.writeAll(fstool.msgDe(e)) catch {};
                    mw.writeAll("\n") catch {};
                    return cli_util.cliErr(err, mw.buffered());
                };
                jsonw.emitEdit(jw, p, r.replaced, r.total, r.bytes) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            }
        },
        .del => {
            const ds = del_s orelse return cli_util.cliErr(err, "Error: falta --del (N, A-B o patrón con --regex)\n");
            if (regex_b) {
                const r = fstool.editDelRegex(gpa, io, p, ds) catch |e| {
                    var mbuf: [256]u8 = undefined;
                    var mw: Io.Writer = .fixed(&mbuf);
                    mw.writeAll("Error: ") catch {};
                    mw.writeAll(fstool.msgDe(e)) catch {};
                    mw.writeAll("\n") catch {};
                    return cli_util.cliErr(err, mw.buffered());
                };
                jsonw.emitEdit(jw, p, r.replaced, r.total, r.bytes) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            } else {
                const rg = fstool.parseRango(ds) catch return cli_util.cliErr(err, "Error: --del debe ser N o A-B (ej. 5, 2-8)\n");
                const r = fstool.editDel(gpa, io, p, rg.desde, rg.hasta) catch |e| {
                    if (e == error.LineaFueraDeRango) return cli_util.cliRango(gpa, io, err, p);
                    var mbuf: [256]u8 = undefined;
                    var mw: Io.Writer = .fixed(&mbuf);
                    mw.writeAll("Error: ") catch {};
                    mw.writeAll(fstool.msgDe(e)) catch {};
                    mw.writeAll("\n") catch {};
                    return cli_util.cliErr(err, mw.buffered());
                };
                jsonw.emitEdit(jw, p, r.replaced, r.total, r.bytes) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            }
        },
    }
    return 0;
}

pub fn doList(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const list_path = o.list_path;
    const max_s = o.max_s;
    const depth_s = o.depth_s;
    const excl_s = o.excl_s;
    const rec_b = o.rec_b;
    const pattern = o.pattern;
    const p = list_path orelse ".";
    const max: usize = if (max_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --max debe ser entero 1-1000\n") else 50;
    if (max < 1 or max > fstool.MAX_LIST) return cli_util.cliErr(err, "Error: --max debe ser entero 1-1000\n");
    const dp: usize = if (depth_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --depth debe ser entero 0-10\n") else 3;
    if (dp > fstool.MAX_PROF_LIST) return cli_util.cliErr(err, "Error: --depth debe ser entero 0-10\n");
    const ex = excl_s orelse "";
    var items: []fstool.Entrada = &.{};
    var total: usize = 0;
    var trunc0 = false;
    if (rec_b) {
        var t = fstool.listTree(gpa, io, p, pattern orelse "", o.regex_b, ex, max, @intCast(dp)) catch |e| {
            return cli_util.cliErr2(err, e);
        };
        defer fstool.freeTree(gpa, &t);
        items = t.entradas;
        total = t.total;
        trunc0 = t.truncado;
        cli_util.emitCliLista(jw, p, items, total, trunc0) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else {
        var l = fstool.listDir(gpa, io, p, pattern orelse "", o.regex_b, max) catch |e| {
            return cli_util.cliErr2(err, e);
        };
        defer fstool.freeList(gpa, &l);
        items = l.entradas;
        total = l.total;
        trunc0 = l.truncado;
        cli_util.emitCliLista(jw, p, items, total, trunc0) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    }
    return 0;
}

pub fn doSearch(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const search_pat = o.search_pat;
    const path_s = o.path_s;
    const max_s = o.max_s;
    const ctx_s = o.ctx_s;
    var files_b = o.files_b;
    if (o.mode_s.len > 0) {
        if (std.mem.eql(u8, o.mode_s, "files")) {
            files_b = true;
        } else if (std.mem.eql(u8, o.mode_s, "content")) {
            files_b = false;
        } else {
            return cli_util.cliErr(err, "Error: --mode en search debe ser files|content\n");
        }
    }
    const case_b = o.case_b;
    const no_rec = o.no_rec;
    const glob_s = o.glob_s;
    const excl_s = o.excl_s;
    const regex_b = o.regex_b;
    const word_b = o.word_b;
    const pt = search_pat.?;
    if (pt.len == 0) return cli_util.cliErr(err, "Error: --search vacío\n");
    if (pt.len > fstool.MAX_PATRON) return cli_util.cliErr(err, "Error: pattern demasiado largo (max 500)\n");
    const p = path_s orelse ".";
    const max: usize = if (max_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --max debe ser entero 1-500\n") else 50;
    if (max < 1 or max > fstool.MAX_MATCH) return cli_util.cliErr(err, "Error: --max debe ser entero 1-500\n");
    const cx: usize = if (ctx_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --context debe ser entero 0-5\n") else 0;
    if (cx > fstool.MAX_CTX) return cli_util.cliErr(err, "Error: --context debe ser entero 0-5\n");
    if (files_b) {
        var n = fstool.buscarNombres(gpa, io, .{
            .raiz = p,
            .patron = pt,
            .sensible = case_b,
            .recursivo = !no_rec,
            .glob = glob_s orelse "",
            .max = max,
            .excluir = excl_s orelse "",
            .regex = regex_b,
        }) catch |e| {
            var mbuf: [256]u8 = undefined;
            var mw: Io.Writer = .fixed(&mbuf);
            mw.writeAll("Error: ") catch {};
            mw.writeAll(fstool.msgDe(e)) catch {};
            mw.writeAll("\n") catch {};
            return cli_util.cliErr(err, mw.buffered());
        };
        defer fstool.freeNombres(gpa, &n);
        var incl = n.entradas.len;
        var usado: usize = 0;
        for (n.entradas, 0..) |e, idx| {
            const costo = 64 + e.nombre.len * 2;
            if (usado + costo > 7168) {
                incl = idx;
                break;
            }
            usado += costo;
        }
        const tr = n.truncado or incl < n.entradas.len;
        jw.writeAll("{\"path\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(jw, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.writeAll(",\"pattern\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(jw, pt) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.writeAll(",\"mode\":\"files\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.print(",\"regex\":{s}", .{if (regex_b) "true" else "false"}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.print(",\"total\":{d},\"skipped\":{d},\"truncated\":", .{ n.total, n.omitidos }) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.writeAll(if (tr) "true,\"entries\":[" else "false,\"entries\":[") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        for (n.entradas[0..incl], 0..) |e, idx| {
            if (idx > 0) jw.writeAll(",") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jw.writeAll("{\"name\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(jw, e.nombre) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jw.writeAll(",\"kind\":\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jw.writeAll(jsonw.kindStr(e.kind)) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jw.writeAll("\",\"size\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            if (e.tam) |sz| {
                jw.print("{d}", .{sz}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            } else {
                jw.writeAll("null") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            }
            jw.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
        jw.writeAll("]}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        return 0;
    }
    var s = fstool.buscar(gpa, io, .{
        .raiz = p,
        .patron = pt,
        .sensible = case_b,
        .recursivo = !no_rec,
        .glob = glob_s orelse "",
        .max = max,
        .contexto = cx,
        .palabra = word_b,
        .excluir = excl_s orelse "",
        .regex = regex_b,
    }) catch |e| {
        var mbuf: [256]u8 = undefined;
        var mw: Io.Writer = .fixed(&mbuf);
        mw.writeAll("Error: ") catch {};
        mw.writeAll(fstool.msgDe(e)) catch {};
        mw.writeAll("\n") catch {};
        return cli_util.cliErr(err, mw.buffered());
    };
    defer fstool.freeSearch(gpa, &s);
    var incl = s.matches.len;
    var usado: usize = 0;
    for (s.matches, 0..) |e, idx| {
        const costo = 64 + e.archivo.len * 2 + @min(e.texto.len, 320) + e.antes.len + e.despues.len;
        if (usado + costo > 7168) {
            incl = idx;
            break;
        }
        usado += costo;
    }
    const trunc = s.truncado or incl < s.matches.len;
    const con_ctx = cx > 0;
    jw.writeAll("{\"path\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    jsonw.writeJsonStr(jw, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    jw.writeAll(",\"pattern\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    jsonw.writeJsonStr(jw, pt) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    jw.print(",\"regex\":{s}", .{if (regex_b) "true" else "false"}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    jw.print(",\"total\":{d},\"skipped\":{d},\"truncated\":", .{ s.total, s.omitidos }) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    jw.writeAll(if (trunc) "true,\"matches\":[" else "false,\"matches\":[") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    for (s.matches[0..incl], 0..) |e, idx| {
        if (idx > 0) jw.writeAll(",") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.writeAll("{\"file\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(jw, e.archivo) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.print(",\"line\":{d},\"col\":{d},\"text\":", .{ e.linea, e.col }) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(jw, e.texto) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jw.writeAll(",\"match\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(jw, e.matched) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        if (con_ctx) {
            jw.writeAll(",\"before\":[") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeStrLines(jw, e.antes) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jw.writeAll("],\"after\":[") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeStrLines(jw, e.despues) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jw.writeAll("]") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
        jw.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    }
    jw.writeAll("]}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    return 0;
}

pub fn doJob(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const job_op = o.job_op;
    const exec_cmd = o.exec_cmd;
    const timeout_s = o.timeout_s;
    const cwd = o.cwd;
    const force_b = o.force_b;
    const job_id = o.job_id;
    const max_s = o.max_s;
    const enc_s = o.enc_s;
    const lines_s = o.lines_s;
    const b64_b = o.b64_b;
    const op = job_op.?;
    var sbuf: [12288]u8 = undefined;
    var sw: Io.Writer = .fixed(&sbuf);
    const sj: *Io.Writer = &sw;
    if (std.mem.eql(u8, op, "start")) {
        const c = exec_cmd orelse return cli_util.cliErr(err, "Error: falta --exec (comando a lanzar)\n");
        const timeout: u32 = if (timeout_s) |s| std.fmt.parseInt(u32, s, 10) catch return cli_util.cliErr(err, "Error: --timeout debe ser entero 1000-3600000\n") else job.DEF_BG_TIMEOUT;
        if (timeout < job.MIN_BG_TIMEOUT or timeout > job.MAX_BG_TIMEOUT) return cli_util.cliErr(err, "Error: --timeout debe ser entero 1000-3600000\n");
        const cw: ?[]const u8 = if (cwd) |d| (if (d.len == 0) null else d) else null;
        fstool.checkCwd(io, cw) catch |e| {
            return cli_util.cliErrMsg(err, fstool.msgDe(e));
        };
        if (!force_b and exectool.esPeligroso(c)) return cli_util.cliErr(err, "Error: comando potencialmente destructivo bloqueado. Tip: agrega --force\n");
        const t0 = jsonw.ahoraMs(io);
        const r = job.lanzar(gpa, io, c, cw, timeout) catch |e| {
            return cli_util.cliErrJob(err, e);
        };
        defer gpa.free(r.id);
        defer gpa.free(r.dir);
        systool.auditar(gpa, io, "job-start", c, cw, -1, jsonw.ahoraMs(io) - t0);
        sj.writeAll("{\"job\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, r.id) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.print(",\"pid\":{d},\"timeout_ms\":{d},\"dir\":", .{ r.pid, timeout }) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, r.dir) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "poll")) {
        const jd = job_id orelse return cli_util.cliErr(err, "Error: falta --job-id\n");
        const max: usize = if (max_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --max debe ser entero 512-4096\n") else exectool.DEF_MAX_BYTES;
        if (max < exectool.MIN_MAX_BYTES or max > exectool.MAX_MAX_BYTES) return cli_util.cliErr(err, "Error: --max debe ser entero 512-4096\n");
        const e = job.sondear(gpa, io, jd) catch |er| {
            return cli_util.cliErrJob(err, er);
        };
        const sco = job.colaLog(gpa, io, jd, "out.log", max) catch |er| {
            return cli_util.cliErrJob(err, er);
        };
        defer gpa.free(sco);
        const sce = job.colaLog(gpa, io, jd, "err.log", max) catch |er| {
            return cli_util.cliErrJob(err, er);
        };
        defer gpa.free(sce);
        const enc = exectool.parseCodif(enc_s) orelse return cli_util.cliErr(err, "Error: --encoding debe ser auto|utf8|oem|raw\n");
        const nl_cli: usize = if (lines_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --lines debe ser entero 0-200\n") else 0;
        if (nl_cli > job.MAX_TAIL_LINES) return cli_util.cliErr(err, "Error: --lines debe ser entero 0-200\n");
        const do_ = exectool.decodificar(gpa, sco, enc, b64_b) catch |er| {
            return cli_util.cliErrMsg(err, exectool.msgDe(er));
        };
        defer gpa.free(do_.texto);
        const de_ = exectool.decodificar(gpa, sce, enc, b64_b) catch |er| {
            return cli_util.cliErrMsg(err, exectool.msgDe(er));
        };
        defer gpa.free(de_.texto);
        const so = do_.texto;
        const se = de_.texto;
        const enc_out: []const u8 = if (de_.texto.len == 0) do_.encoding else if (do_.texto.len == 0) de_.encoding else if (std.mem.eql(u8, do_.encoding, de_.encoding)) do_.encoding else "mixed";
        sj.writeAll("{\"job\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, jd) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(if (e.running) ",\"running\":true" else ",\"running\":false") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        if (e.exit) |x| {
            sj.print(",\"exit\":{d}", .{x}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        } else {
            sj.writeAll(",\"exit\":null") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
        sj.print(",\"elapsed_ms\":{d}", .{e.elapsed_ms}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(if (e.timed_out) ",\"timed_out\":true" else ",\"timed_out\":false") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(if (e.killed) ",\"killed\":true" else ",\"killed\":false") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        if (e.nota.len > 0) {
            sj.writeAll(",\"note\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, e.nota) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
        sj.writeAll(",\"out\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, job.ultimasLineas(so, nl_cli)) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(",\"err\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, job.ultimasLineas(se, nl_cli)) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(",\"encoding\":\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(enc_out) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("\"}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "kill")) {
        const jd = job_id orelse return cli_util.cliErr(err, "Error: falta --job-id\n");
        const k = job.detener(gpa, io, jd) catch |e| {
            return cli_util.cliErrJob(err, e);
        };
        sj.writeAll("{\"job\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, jd) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(if (k) ",\"killed\":true}" else ",\"killed\":false}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "list")) {
        var l = job.listar(gpa, io) catch |e| {
            return cli_util.cliErrJob(err, e);
        };
        defer job.freeLista(gpa, &l);
        sj.print("{{\"total\":{d},\"truncated\":", .{l.total}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(if (l.truncado) "true,\"jobs\":[" else "false,\"jobs\":[") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        for (l.items, 0..) |it, idx| {
            if (idx > 0) sj.writeAll(",") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.writeAll("{\"job\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, it.id) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.print(",\"pid\":{d},\"cmd\":", .{it.pid}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, it.cmd) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.writeAll(if (it.running) ",\"running\":true" else ",\"running\":false") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.print(",\"elapsed_ms\":{d}}}", .{it.elapsed_ms}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
        sj.writeAll("]}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "forget")) {
        const jd = job_id orelse return cli_util.cliErr(err, "Error: falta --job-id\n");
        job.olvidar(gpa, io, jd) catch |e| {
            return cli_util.cliErrJob(err, e);
        };
        sj.writeAll("{\"job\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, jd) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(",\"forgotten\":true}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else {
        return cli_util.cliErr(err, "Error: --job debe ser start|poll|kill|list|forget\n");
    }
    jw.writeAll(sw.buffered()) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    return 0;
}

pub fn doSys(gpa: std.mem.Allocator, io: Io, err: *Io.Writer, jw: *Io.Writer, o: *const Opts) !u8 {
    const sys_op = o.sys_op;
    const name_s = o.name_s;
    const filter = o.filter;
    const path_s = o.path_s;
    const dest = o.dest;
    const op = sys_op.?;
    var sbuf: [12288]u8 = undefined;
    var sw: Io.Writer = .fixed(&sbuf);
    const sj: *Io.Writer = &sw;
    if (std.mem.eql(u8, op, "info")) {
        sj.writeAll("{\"os\":\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(systool.osName()) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("\",\"arch\":\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(systool.archName()) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("\",\"zig\":\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(systool.zigVersion()) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("\"}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "env_get")) {
        const nm = name_s orelse return cli_util.cliErr(err, "Error: falta --name\n");
        const v = systool.envGet(nm) catch return cli_util.cliErr(err, "Error: no existe esa variable\n");
        if (!fstool.esUtf8(v)) return cli_util.cliErr(err, "Error: la variable no es UTF-8 válido\n");
        sj.writeAll("{\"name\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, nm) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(",\"value\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, v) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "env_list")) {
        const el = systool.envList(gpa, filter orelse "") catch return cli_util.cliErr(err, "Error: sin entorno\n");
        defer gpa.free(el.pares);
        sj.writeAll("{\"filter\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, filter orelse "") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.print(",\"count\":{d},\"truncated\":", .{el.total}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(if (el.truncado) "true,\"vars\":{" else "false,\"vars\":{") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        var coma = false;
        for (el.pares) |kv| {
            if (!fstool.esUtf8(kv.k) or !fstool.esUtf8(kv.v)) continue;
            if (coma) sj.writeAll(",") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            coma = true;
            jsonw.writeJsonStr(sj, kv.k) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.writeAll(":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, kv.v) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
        sj.writeAll("}}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "stat")) {
        const p = path_s orelse return cli_util.cliErr(err, "Error: falta --path\n");
        const st = fstool.statUno(io, p) catch |e| {
            var mbuf: [256]u8 = undefined;
            var mw: Io.Writer = .fixed(&mbuf);
            mw.writeAll("Error: ") catch {};
            mw.writeAll(fstool.msgDe(e)) catch {};
            mw.writeAll("\n") catch {};
            return cli_util.cliErr(err, mw.buffered());
        };
        sj.writeAll("{\"path\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(",\"kind\":\"") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(jsonw.kindStr(st.kind)) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.print("\",\"size\":{d}}}", .{st.size}) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "mkdir")) {
        const p = path_s orelse return cli_util.cliErr(err, "Error: falta --path\n");
        fstool.mkdirTodo(io, p) catch |e| {
            var mbuf: [256]u8 = undefined;
            var mw: Io.Writer = .fixed(&mbuf);
            mw.writeAll("Error: ") catch {};
            mw.writeAll(fstool.msgDe(e)) catch {};
            mw.writeAll("\n") catch {};
            return cli_util.cliErr(err, mw.buffered());
        };
        sj.writeAll("{\"op\":\"mkdir\",\"path\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else if (std.mem.eql(u8, op, "rm")) {
        const p = path_s orelse return cli_util.cliErr(err, "Error: falta --path\n");
        const pat_s = o.pattern;
        const glob_s = o.glob_s;
        if (pat_s != null and glob_s != null)
            return cli_util.cliErr(err, "Error: usa --pattern o --glob, no ambos\n");
        if (glob_s != null and o.regex_b)
            return cli_util.cliErr(err, "Error: --glob no se combina con --regex; usa --pattern\n");
        const patron = pat_s orelse glob_s orelse "";
        const max: usize = if (o.max_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --max debe ser entero 1-1000\n") else 200;
        if (max < 1 or max > fstool.MAX_LIST) return cli_util.cliErr(err, "Error: --max debe ser entero 1-1000\n");
        if (patron.len > 0 or o.regex_b) {
            var lote = fstool.borrarCoincidentes(gpa, io, .{
                .raiz = p,
                .patron = patron,
                .regex = o.regex_b,
                .max = max,
                .dry_run = o.dry_run,
            }) catch |e| return cli_util.cliErr2(err, e);
            defer fstool.freeLote(gpa, &lote);
            escribirLoteCli(sj, "rm", p, &lote) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        } else {
            if (o.dry_run) {
                _ = fstool.statUno(io, p) catch |e| return cli_util.cliErr2(err, e);
            } else {
                fstool.borrarTodo(io, p) catch |e| return cli_util.cliErr2(err, e);
            }
            sj.writeAll("{\"op\":\"rm\",\"path\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            if (o.dry_run) sj.writeAll(",\"dry_run\":true") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
    } else if (std.mem.eql(u8, op, "mv")) {
        const p = path_s orelse return cli_util.cliErr(err, "Error: falta --path (origen)\n");
        const pat_s = o.pattern;
        const glob_s = o.glob_s;
        if (pat_s != null and glob_s != null)
            return cli_util.cliErr(err, "Error: usa --pattern o --glob, no ambos\n");
        if (glob_s != null and o.regex_b)
            return cli_util.cliErr(err, "Error: --glob no se combina con --regex; usa --pattern\n");
        const patron = pat_s orelse glob_s orelse "";
        const subst = o.subst orelse "";
        const max: usize = if (o.max_s) |s| cli_util.parseU(s) orelse return cli_util.cliErr(err, "Error: --max debe ser entero 1-1000\n") else 200;
        if (max < 1 or max > fstool.MAX_LIST) return cli_util.cliErr(err, "Error: --max debe ser entero 1-1000\n");
        if (patron.len > 0 or subst.len > 0) {
            var lote = fstool.renombrarCoincidentes(gpa, io, .{
                .raiz = p,
                .patron = patron,
                .regex = o.regex_b,
                .max = max,
                .dry_run = o.dry_run,
                .force = o.force_b,
                .destino = dest orelse "",
                .subst = subst,
            }) catch |e| return cli_util.cliErr2(err, e);
            defer fstool.freeLote(gpa, &lote);
            escribirLoteCli(sj, "mv", p, &lote) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        } else {
            const d = dest orelse return cli_util.cliErr(err, "Error: falta --dest\n");
            if (o.dry_run) {
                fstool.verificarMover(io, p, d, o.force_b) catch |e| return cli_util.cliErr2(err, e);
            } else {
                fstool.mover(io, p, d, o.force_b) catch |e| return cli_util.cliErr2(err, e);
            }
            sj.writeAll("{\"op\":\"mv\",\"from\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.writeAll(",\"to\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            jsonw.writeJsonStr(sj, d) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            if (o.dry_run) sj.writeAll(",\"dry_run\":true") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
            sj.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        }
    } else if (std.mem.eql(u8, op, "cp")) {
        const p = path_s orelse return cli_util.cliErr(err, "Error: falta --path (origen)\n");
        const d = dest orelse return cli_util.cliErr(err, "Error: falta --dest\n");
        fstool.copiar(io, p, d) catch |e| {
            var mbuf: [256]u8 = undefined;
            var mw: Io.Writer = .fixed(&mbuf);
            mw.writeAll("Error: ") catch {};
            mw.writeAll(fstool.msgDe(e)) catch {};
            mw.writeAll("\n") catch {};
            return cli_util.cliErr(err, mw.buffered());
        };
        sj.writeAll("{\"op\":\"cp\",\"from\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, p) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll(",\"to\":") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        jsonw.writeJsonStr(sj, d) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
        sj.writeAll("}") catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    } else {
        return cli_util.cliErr(err, "Error: --sys debe ser info|env_get|env_list|stat|mkdir|rm|mv|cp\n");
    }
    jw.writeAll(sw.buffered()) catch return cli_util.cliErr(err, "Error: respuesta demasiado larga\n");
    return 0;
}

// JSON de respuesta para rm/mv en lote (con tope de ~9 KB de items).
fn escribirLoteCli(j: *Io.Writer, op: []const u8, dir: []const u8, l: *const fstool.LoteOut) !void {
    try j.writeAll("{\"op\":\"");
    try j.writeAll(op);
    try j.writeAll("\",\"dir\":");
    try jsonw.writeJsonStr(j, dir);
    try j.print(",\"matched\":{d},\"done\":{d},\"skipped\":{d},\"dry_run\":{s}", .{
        l.total, l.hechos, l.omitidos, if (l.dry_run) "true" else "false",
    });
    var incl: usize = 0;
    var usado: usize = 0;
    for (l.items) |it| {
        const costo = 64 + it.nombre.len * 2 + (if (it.destino) |d| d.len * 2 else 0);
        if (usado + costo > 9000) break;
        usado += costo;
        incl += 1;
    }
    const trunc = l.truncado or incl < l.items.len;
    try j.writeAll(if (trunc) ",\"truncated\":true,\"items\":[" else ",\"truncated\":false,\"items\":[");
    for (l.items[0..incl], 0..) |it, i| {
        if (i > 0) try j.writeAll(",");
        try j.writeAll("{\"name\":");
        try jsonw.writeJsonStr(j, it.nombre);
        try j.writeAll(",\"action\":");
        try jsonw.writeJsonStr(j, it.accion);
        if (it.destino) |d| {
            try j.writeAll(",\"to\":");
            try jsonw.writeJsonStr(j, d);
        }
        try j.writeAll("}");
    }
    try j.writeAll("]}");
}
