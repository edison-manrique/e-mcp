// CLI efímero: 1 llamada = 1 proceso, imprime JSON y termina.
// Sin argumentos el binario es servidor MCP (ver main.zig). Con argumentos
// ejecuta una vez (ideal para orquestadores). Errores -> stderr, código != 0.

const std = @import("std");
const Io = std.Io;
const jsonw = @import("../core/jsonw.zig");
const tm = @import("../time/tmtool.zig");
const ayuda = @import("../ayuda.zig");
const registro = @import("../registro.zig");

const zona = tm.zona;
const fecha = tm.fecha;
const dur = tm.dur;

const MAX_H = 128;

const FLAGS = [_][]const u8{
    "--help",     "--help-topic", "--version", "--zone",   "-z",
    "--format",   "-f",           "--patron",  "--fecha",  "--suma",
    "--desde",    "--hasta",      "--en",      "--modo",   "--dias",
    "--pais",     "--feriados",   "--detalle", "--epoca",  "--formato",
};

fn cliErr(err: *Io.Writer, msg: []const u8) u8 {
    err.writeAll(msg) catch {};
    err.flush() catch {};
    return 2;
}

fn isValidFormat(f: []const u8) bool {
    return std.mem.eql(u8, f, "all") or std.mem.eql(u8, f, "iso") or std.mem.eql(u8, f, "human") or std.mem.eql(u8, f, "unix");
}

const Opts = struct {
    zone: []const u8 = "Lima",
    format: []const u8 = "all",
    patron: ?[]const u8 = null,
    fecha: ?[]const u8 = null,
    suma: []const u8 = "",
    desde: ?[]const u8 = null,
    hasta: []const u8 = "ahora",
    en: []const u8 = "dias",
    modo: ?[]const u8 = null,
    dias: ?[]const u8 = null,
    pais: []const u8 = "",
    feriados: ?[]const u8 = null,
    detalle: bool = false,
    epoca: bool = false,
    formato: bool = false,
    help_topic: ?[]const u8 = null,
    bad_arg: ?[]const u8 = null,
};

fn parseArgs(args: []const [:0]const u8, o: *Opts) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a: []const u8 = args[i];
        if (eqAny(a, &.{ "--help", "-h", "help" })) {
            if (i + 1 < args.len and args[i + 1].len > 0 and args[i + 1][0] != '-') {
                if (ayuda.topicMd(args[i + 1]) != null) {
                    o.help_topic = args[i + 1];
                    i += 1;
                    continue;
                }
            }
            return "HELP";
        }
        if (eqAny(a, &.{ "--version", "-V" })) return "VERSION";
        if (std.mem.eql(u8, a, "--detalle")) {
            o.detalle = true;
            continue;
        }
        if (std.mem.eql(u8, a, "--epoca")) {
            o.epoca = true;
            continue;
        }
        if (std.mem.eql(u8, a, "--formato")) {
            o.formato = true;
            continue;
        }
        // Flags con valor (--k v o --k=v).
        const names = [_][]const u8{ "--zone", "-z", "--format", "-f", "--patron", "--fecha", "--suma", "--desde", "--hasta", "--en", "--modo", "--dias", "--pais", "--feriados", "--help-topic" };
        var matched: ?[]const u8 = null;
        for (names) |nm| {
            if (std.mem.eql(u8, a, nm)) {
                matched = a;
                break;
            }
            if (std.mem.startsWith(u8, a, nm) and a.len > nm.len and a[nm.len] == '=') {
                matched = a;
                break;
            }
        }
        const nm = matched orelse {
            o.bad_arg = a;
            return "ARG";
        };
        const val: []const u8 = if (std.mem.indexOfScalar(u8, nm, '=')) |eq|
            a[eq + 1 ..]
        else blk: {
            i += 1;
            if (i >= args.len) {
                o.bad_arg = nm;
                return "MISSING";
            }
            break :blk args[i];
        };
        if (eqAny(nm, &.{ "--zone", "-z" })) {
            o.zone = val;
        } else if (eqAny(nm, &.{ "--format", "-f" })) {
            o.format = val;
        } else if (std.mem.eql(u8, nm, "--patron")) {
            o.patron = val;
        } else if (std.mem.eql(u8, nm, "--fecha")) {
            o.fecha = val;
        } else if (std.mem.eql(u8, nm, "--suma")) {
            o.suma = val;
        } else if (std.mem.eql(u8, nm, "--desde")) {
            o.desde = val;
        } else if (std.mem.eql(u8, nm, "--hasta")) {
            o.hasta = val;
        } else if (std.mem.eql(u8, nm, "--en")) {
            o.en = val;
        } else if (std.mem.eql(u8, nm, "--modo")) {
            o.modo = val;
        } else if (std.mem.eql(u8, nm, "--dias")) {
            o.dias = val;
        } else if (std.mem.eql(u8, nm, "--pais")) {
            o.pais = val;
        } else if (std.mem.eql(u8, nm, "--feriados")) {
            o.feriados = val;
        } else if (std.mem.eql(u8, nm, "--help-topic")) {
            o.help_topic = val;
        }
    }
    return null;
}

fn eqAny(a: []const u8, opts: []const []const u8) bool {
    for (opts) |o| {
        if (std.mem.eql(u8, a, o)) return true;
    }
    return false;
}

pub fn run(io: Io, args: []const [:0]const u8) !u8 {
    var out_buf: [1024]u8 = undefined;
    var out_w: Io.File.Writer = .initStreaming(.stdout(), io, &out_buf);
    var out: *Io.Writer = &out_w.interface;
    var err_buf: [512]u8 = undefined;
    var err_w: Io.File.Writer = .initStreaming(.stderr(), io, &err_buf);
    var err: *Io.Writer = &err_w.interface;

    var o = Opts{};
    if (parseArgs(args, &o)) |bad| {
        if (std.mem.eql(u8, bad, "HELP")) {
            try out.writeAll(ayuda.USAGE_CLI);
            try out.writeAll("\n");
            try out.flush();
            return 0;
        }
        if (std.mem.eql(u8, bad, "VERSION")) {
            try out.print("{s} {s}\n", .{ registro.NOMBRE, registro.VERSION });
            try out.flush();
            return 0;
        }
        if (std.mem.eql(u8, bad, "MISSING")) {
            if (o.bad_arg) |x| {
                try err.print("Error: falta valor para {s}\n", .{x});
                try err.flush();
                return 2;
            }
            return cliErr(err, "Error: falta valor para una opción\n");
        }
        if (o.bad_arg) |x| {
            try err.print("Error: argumento desconocido: {s}\n", .{x});
            if (ayuda.sugerir(x, FLAGS[0..])) |s| try err.print("¿Quisiste decir {s}?\n", .{s});
            try err.print("Usa `world-time --help` para ver las opciones.\n", .{});
            try err.flush();
            return 2;
        }
        return cliErr(err, "Error: argumento desconocido\n");
    }

    if (o.help_topic) |t| {
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
    if (!isValidFormat(o.format)) return cliErr(err, "Error: --format debe ser all|iso|human|unix\n");
    if (o.fecha != null and o.fecha.?.len > tm.MAX_FECHA) return cliErr(err, "Error: fecha demasiado larga\n");
    if (o.suma.len > tm.MAX_SUMA) return cliErr(err, "Error: suma demasiado larga\n");

    const z = zona.resolveZone(o.zone) orelse {
        try err.print("Error: zona desconocida: {s}\n", .{o.zone});
        try err.flush();
        return 2;
    };
    const now = tm.nowMs(io);

    var jbuf: [4096]u8 = undefined;
    var jw: Io.Writer = .fixed(&jbuf);

    // ---- detalle ----
    if (o.detalle) {
        const m = fecha.parseFecha(o.fecha orelse "ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
        jsonw.writeDetalle(&jw, m, z) catch return cliErr(err, "Error: respuesta demasiado larga\n");
        return emit(out, &jw);
    }
    // ---- epoca ----
    if (o.epoca) {
        const m = fecha.parseFecha(o.fecha orelse "ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
        jsonw.writeEpoca(&jw, m, z) catch return cliErr(err, "Error: respuesta demasiado larga\n");
        return emit(out, &jw);
    }
    // ---- formato (patrón explícito) ----
    if (o.formato) {
        const p = o.patron orelse return cliErr(err, "Error: --formato requiere --patron\n");
        const m = fecha.parseFecha(o.fecha orelse "ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
        jsonw.writeFormato(&jw, p, m, z) catch |e| {
            if (e == error.PatronInvalido) return cliErr(err, "Error: patrón inválido\n");
            return cliErr(err, "Error: respuesta demasiado larga\n");
        };
        return emit(out, &jw);
    }
    // ---- laborable ----
    if (o.modo) |modo| {
        var exactas: [MAX_H][3]i32 = undefined;
        var anuales: [MAX_H][2]u8 = undefined;
        var ne: usize = 0;
        var na: usize = 0;
        const p = tm.feriados.parsePais(o.pais) orelse return cliErr(err, "Error: --pais inválido\n");
        if (o.feriados) |lst| {
            var it = std.mem.splitScalar(u8, lst, ',');
            while (it.next()) |tok| {
                const s = std.mem.trim(u8, tok, " ");
                if (s.len == 0) continue;
                if (s.len == 5 and s[2] == '-' and dig(s[0]) and dig(s[1]) and dig(s[3]) and dig(s[4])) {
                    if (na >= MAX_H) break;
                    anuales[na] = .{ @intCast((s[0] - '0') * 10 + (s[1] - '0')), @intCast((s[3] - '0') * 10 + (s[4] - '0')) };
                    na += 1;
                } else {
                    const ms = fecha.parseFecha(s, z, now) catch return cliErr(err, "Error: feriado inválido\n");
                    const cp = z.msToCivil(ms);
                    if (ne >= MAX_H) break;
                    exactas[ne] = .{ @intCast(cp.y), cp.mo, cp.d };
                    ne += 1;
                }
            }
        }
        const cfg = tm.feriados.Cfg{ .pais = p, .exactas = exactas[0..ne], .anuales = anuales[0..na] };
        const pais_out: []const u8 = if (o.pais.len == 0) "ninguno" else o.pais;
        if (std.mem.eql(u8, modo, "contar")) {
            const d_in = o.desde orelse return cliErr(err, "Error: falta --desde\n");
            const m_desde = fecha.parseFecha(d_in, z, now) catch return cliErr(err, "Error: fecha inválida en --desde\n");
            const m_hasta = fecha.parseFecha(o.hasta, z, now) catch return cliErr(err, "Error: fecha inválida en --hasta\n");
            const lab = tm.laborable.contar(m_desde, m_hasta, z, cfg);
            const a = z.msToCivil(m_desde);
            const b = z.msToCivil(m_hasta);
            var nat = tm.civil.daysFromCivil(b.y, b.mo, b.d) - tm.civil.daysFromCivil(a.y, a.mo, a.d);
            if (nat < 0) nat = -nat;
            jsonw.writeLabContar(&jw, m_desde, m_hasta, z, lab, nat, pais_out) catch return cliErr(err, "Error: respuesta demasiado larga\n");
            return emit(out, &jw);
        }
        if (std.mem.eql(u8, modo, "sumar")) {
            const dstr = o.dias orelse return cliErr(err, "Error: falta --dias\n");
            const n = std.fmt.parseInt(i64, std.mem.trim(u8, dstr, " "), 10) catch return cliErr(err, "Error: --dias debe ser entero\n");
            const m = fecha.parseFecha(o.fecha orelse "ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
            const res = tm.laborable.sumar(m, n, z, cfg) catch return cliErr(err, "Error: rango fuera de límite\n");
            jsonw.writeLabSumar(&jw, m, n, res, z, pais_out) catch return cliErr(err, "Error: respuesta demasiado larga\n");
            return emit(out, &jw);
        }
        if (std.mem.eql(u8, modo, "es")) {
            const m = fecha.parseFecha(o.fecha orelse "ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
            const cp = z.msToCivil(m);
            const wd = tm.civil.weekdayYmd(cp.y, cp.mo, cp.d);
            const es_lab = tm.laborable.esLaborableMs(m, z, cfg);
            const motivo: []const u8 = if (wd == 0 or wd == 6) "fin de semana" else if (tm.feriados.esFeriado(cp.y, cp.mo, cp.d, cfg)) "feriado" else "laborable";
            jsonw.writeLabEs(&jw, m, z, es_lab, motivo, pais_out) catch return cliErr(err, "Error: respuesta demasiado larga\n");
            return emit(out, &jw);
        }
        return cliErr(err, "Error: --modo debe ser contar|sumar|es\n");
    }
    // ---- dif ----
    if (o.desde) |d_in| {
        const en_sec: i64 = if (std.mem.eql(u8, o.en, "segundos"))
            1
        else if (std.mem.eql(u8, o.en, "minutos"))
            60
        else if (std.mem.eql(u8, o.en, "horas"))
            3600
        else if (std.mem.eql(u8, o.en, "dias"))
            86400
        else if (std.mem.eql(u8, o.en, "semanas"))
            604800
        else
            return cliErr(err, "Error: --en debe ser segundos|minutos|horas|dias|semanas\n");
        const m_desde = fecha.parseFecha(d_in, z, now) catch return cliErr(err, "Error: fecha inválida en --desde\n");
        const m_hasta = fecha.parseFecha(o.hasta, z, now) catch return cliErr(err, "Error: fecha inválida en --hasta\n");
        jsonw.writeDif(&jw, m_desde, m_hasta, z, o.en, en_sec, now) catch return cliErr(err, "Error: respuesta demasiado larga\n");
        return emit(out, &jw);
    }
    // ---- fecha ----
    if (o.fecha != null or o.suma.len > 0) {
        const base = fecha.parseFecha(o.fecha orelse "ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
        var target = base;
        if (o.suma.len > 0) {
            const d = dur.parse(o.suma) catch return cliErr(err, "Error: duración inválida\n");
            target = fecha.addDuracion(base, z, d) catch return cliErr(err, "Error: rango fuera de límite\n");
        }
        jsonw.writeFecha(&jw, target, base, z, o.format, o.suma, now, o.patron) catch |e| {
            if (e == error.PatronInvalido) return cliErr(err, "Error: patrón inválido\n");
            return cliErr(err, "Error: respuesta demasiado larga\n");
        };
        return emit(out, &jw);
    }
    // ---- formato (patrón sobre ahora) ----
    if (o.patron) |p| {
        const m = fecha.parseFecha("ahora", z, now) catch return cliErr(err, "Error: fecha inválida\n");
        jsonw.writeFormato(&jw, p, m, z) catch |e| {
            if (e == error.PatronInvalido) return cliErr(err, "Error: patrón inválido\n");
            return cliErr(err, "Error: respuesta demasiado larga\n");
        };
        return emit(out, &jw);
    }
    // ---- time ----
    const t = tm.dateTimeIn(io, z);
    jsonw.writeTime(&jw, t, z, o.format, o.patron) catch |e| {
        if (e == error.PatronInvalido) return cliErr(err, "Error: patrón inválido\n");
        return cliErr(err, "Error: respuesta demasiado larga\n");
    };
    return emit(out, &jw);
}

fn dig(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn emit(out: *Io.Writer, jw: *Io.Writer) !u8 {
    try out.writeAll(jw.buffered());
    try out.writeAll("\n");
    try out.flush();
    return 0;
}
