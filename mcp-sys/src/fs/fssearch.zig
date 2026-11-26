// Busqueda de texto por contenido y por nombre (grep chico).
// Fase 3 (modularizacion): extraido de fstool.zig.

const std = @import("std");
const Io = std.Io;
const regex = @import("../regex/regex.zig");
const fstool = @import("fstool.zig");

// Compartido con el nucleo (fstool.zig).
const readAll = fstool.readAll;
const esUtf8 = fstool.esUtf8;
const checkPath = fstool.checkPath;
const globMatch = fstool.globMatch;
const baja = fstool.baja;
const statUno = fstool.statUno;

// ---------- Búsqueda de texto (grep chico) ----------

pub const MAX_PATRON: usize = 500;
pub const MAX_MATCH: usize = 500;
pub const MAX_SCAN_BYTES: usize = 1048576; // archivos mayores se omiten
pub const MAX_TEXTO_MATCH: usize = 300;
pub const MAX_PROF: u8 = 32;

// Carpetas que siempre se omiten al caminar (además de ocultos `.x`).
pub fn esSaltoDir(nombre: []const u8) bool {
    for ([_][]const u8{ "zig-out", "node_modules", "target", "__pycache__" }) |s| {
        if (std.mem.eql(u8, nombre, s)) return true;
    }
    return false;
}

pub const MAX_CTX: usize = 5;

pub const Match = struct {
    archivo: []u8, // dueño: gpa (relativo a la raíz buscada)
    linea: usize, // 1-based
    col: usize, // 1-based: byte donde empieza el match dentro de la línea
    texto: []u8, // dueño: gpa (recortado a 300)
    matched: []u8, // dueño: gpa: texto EXACTO del match (substring o regex)
    antes: []u8, // dueño: gpa (contexto previo unido con \n)
    despues: []u8, // dueño: gpa (contexto posterior; completo al cerrar archivo)
    falta: usize, // interno: líneas 'after' pendientes (no se serializa)
};

pub const SearchOut = struct {
    matches: []Match,
    total: usize, // coincidencias contadas (todas)
    omitidos: usize, // archivos/carpetas saltados
    truncado: bool, // total > matches.len
};

fn freeOwned(gpa: std.mem.Allocator, s: []u8) void {
    if (s.len > 0) gpa.free(s);
}

pub fn freeSearch(gpa: std.mem.Allocator, s: *SearchOut) void {
    for (s.matches) |m| {
        freeOwned(gpa, m.archivo);
        freeOwned(gpa, m.texto);
        freeOwned(gpa, m.matched);
        freeOwned(gpa, m.antes);
        freeOwned(gpa, m.despues);
    }
    gpa.free(s.matches);
    s.matches = &.{};
}

const Span = struct { ini: usize, fin: usize };

// Span de la primera ocurrencia desde `desde` (null si no hay). Insensible = ASCII.
fn encuentraDesde(hay: []const u8, aguja: []const u8, sensible: bool, desde: usize) ?Span {
    if (aguja.len == 0 or aguja.len > hay.len) return null;
    if (desde > hay.len - aguja.len) return null;
    if (sensible) {
        if (std.mem.indexOfPos(u8, hay, desde, aguja)) |i| return .{ .ini = i, .fin = i + aguja.len };
        return null;
    }
    var i: usize = desde;
    while (i + aguja.len <= hay.len) : (i += 1) {
        var ok = true;
        for (aguja, 0..) |c, j| {
            if (baja(hay[i + j]) != baja(c)) {
                ok = false;
                break;
            }
        }
        if (ok) return .{ .ini = i, .fin = i + aguja.len };
    }
    return null;
}

pub fn encuentra(hay: []const u8, aguja: []const u8, sensible: bool) ?Span {
    return encuentraDesde(hay, aguja, sensible, 0);
}

fn esBorde(c: u8) bool {
    return !((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_');
}

// ¿El span [ini,fin) cae en bordes de palabra? (para `word`).
fn bordeOk(linea: []const u8, ini: usize, fin: usize) bool {
    const izq = ini == 0 or esBorde(linea[ini - 1]);
    const der = fin >= linea.len or esBorde(linea[fin]);
    return izq and der;
}

// ¿`nombre` cae en la lista de exclusión (globs separados por coma)?
pub fn excluido(lista: []const u8, nombre: []const u8) bool {
    var it = std.mem.splitScalar(u8, lista, ',');
    while (it.next()) |g| {
        const t = std.mem.trim(u8, g, " \t");
        if (t.len > 0 and globMatch(t, nombre)) return true;
    }
    return false;
}

// Une líneas con \n (para contexto). Siempre owned (liberar con freeOwned).
fn uneLineas(gpa: std.mem.Allocator, lineas: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (lineas, 0..) |l, i| {
        if (i > 0) try out.append(gpa, '\n');
        try out.appendSlice(gpa, l);
    }
    return out.toOwnedSlice(gpa);
}

// Agrega 1 línea a un bloque unido con \n (owned → owned).
fn agregaLinea(gpa: std.mem.Allocator, cur: []u8, linea: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, cur);
    if (cur.len > 0) try out.append(gpa, '\n');
    try out.appendSlice(gpa, linea);
    if (cur.len > 0) gpa.free(cur); // len 0 nunca se libera (quizá estático)
    return out.toOwnedSlice(gpa);
}

const Busca = struct {
    gpa: std.mem.Allocator,
    io: Io,
    patron: []const u8,
    sensible: bool,
    recursivo: bool,
    glob: []const u8,
    max: usize,
    contexto: usize, // 0..MAX_CTX
    palabra: bool, // palabra completa
    excluir: []const u8, // globs coma-separados
    rx: ?regex.Regex, // si no es null, se usa el motor regex
    tmp: std.ArrayList(Match),
    total: usize,
    omitidos: usize,
};

// Siguiente match aceptable en la linea a partir de `desde` (regex o
// substring), respetando `word` (si un candidato no cae en borde de palabra,
// se prueba el siguiente). Devuelve null si no hay más.
fn siguienteValido(b: *Busca, linea: []const u8, desde: usize) ?Span {
    if (b.rx) |*r| {
        var pos: usize = desde;
        while (r.findFrom(linea, pos)) |sp| {
            if (!b.palabra or bordeOk(linea, sp.ini, sp.fin)) return .{ .ini = sp.ini, .fin = sp.fin };
            pos = if (sp.fin > sp.ini) sp.fin else sp.fin + 1;
            if (pos > linea.len) break;
        }
        return null;
    }
    var pos: usize = desde;
    while (encuentraDesde(linea, b.patron, b.sensible, pos)) |sp| {
        if (!b.palabra or bordeOk(linea, sp.ini, sp.fin)) return sp;
        pos = sp.ini + 1;
        if (pos > linea.len) break;
    }
    return null;
}

fn buscaArchivo(b: *Busca, dir: Io.Dir, nombre: []const u8, rel: []const u8) void {
    // Congela pendientes de archivos anteriores al salir (todas las
    // vías): el `after` nunca fuga líneas de otro archivo (B1).
    const desde: usize = b.tmp.items.len;
    defer {
        for (b.tmp.items[desde..]) |*m| m.falta = 0;
    }
    const st = dir.statFile(b.io, nombre, .{}) catch {
        b.omitidos += 1;
        return;
    };
    if (st.size > MAX_SCAN_BYTES) {
        b.omitidos += 1;
        return;
    }
    var f = dir.openFile(b.io, nombre, .{}) catch {
        b.omitidos += 1;
        return;
    };
    defer f.close(b.io);
    const K: usize = @min(b.contexto, MAX_CTX);
    // Anillo de últimas K líneas limpias (dups recortados) para `before`.
    var anillo: [MAX_CTX][]const u8 = undefined;
    var n_anillo: usize = 0;
    defer {
        for (anillo[0..n_anillo]) |l| b.gpa.free(l);
    }
    var rbuf: [65536]u8 = undefined;
    var r = f.reader(b.io, &rbuf);
    var in: *Io.Reader = &r.interface;
    var lin: usize = 1;
    var lineas_malas = false; // líneas ilegibles (no-UTF8): se cuentan 1 vez
    while (true) {
        const chunk: ?[]u8 = in.takeDelimiter('\n') catch |e| {
            if (e == error.StreamTooLong) {
                _ = in.discardDelimiterInclusive('\n') catch break;
                lin += 1;
                continue; // línea gigante: se salta, el archivo sigue
            }
            if (lineas_malas) b.omitidos += 1;
            b.omitidos += 1;
            return;
        };
        if (chunk == null) break;
        var linea = chunk.?;
        defer lin += 1;
        if (linea.len > 0 and linea[linea.len - 1] == '\r') linea = linea[0 .. linea.len - 1];
        if (std.mem.indexOfScalar(u8, linea, 0) != null) {
            lineas_malas = true; // binario parcial también se señala
            continue;
        }
        if (!esUtf8(linea)) {
            lineas_malas = true;
            continue;
        }
        // 1. Esta línea completa el `after` de matches pendientes.
        const np = b.tmp.items.len;
        for (b.tmp.items[0..np]) |*m| {
            if (m.falta == 0) continue;
            const corte = @min(linea.len, MAX_TEXTO_MATCH);
            if (agregaLinea(b.gpa, m.despues, linea[0..corte])) |nd| {
                m.despues = nd;
                m.falta -= 1;
            } else |_| {}
        }
        // 2. ¿Matches nuevos? (regex o substring; +palabra completa si se pide).
        // Se recorren TODAS las ocurrencias de la línea (multi-match).
        {
            var pos: usize = 0;
            while (siguienteValido(b, linea, pos)) |sp| {
                if (sp.fin == sp.ini) { // match vacío (regex): avanza 1, no se reporta
                    pos = sp.fin + 1;
                    if (pos > linea.len) break;
                    continue;
                }
                b.total += 1;
                if (b.tmp.items.len < b.max) {
                    const corte = @min(linea.len, MAX_TEXTO_MATCH);
                    const ta = b.gpa.dupe(u8, rel) catch null;
                    const tt = b.gpa.dupe(u8, linea[0..corte]) catch null;
                    const ma = b.gpa.dupe(u8, linea[sp.ini..sp.fin]) catch null;
                    const ba = uneLineas(b.gpa, anillo[0..n_anillo]) catch null;
                    const vacio = b.gpa.dupe(u8, "") catch null;
                    if (ta != null and tt != null and ma != null and ba != null and vacio != null) {
                        b.tmp.append(b.gpa, .{ .archivo = ta.?, .linea = lin, .col = sp.ini + 1, .texto = tt.?, .matched = ma.?, .antes = ba.?, .despues = vacio.?, .falta = K }) catch {
                            b.gpa.free(ta.?);
                            b.gpa.free(tt.?);
                            b.gpa.free(ma.?);
                            b.gpa.free(ba.?);
                            b.gpa.free(vacio.?);
                        };
                    } else {
                        if (ta) |x| b.gpa.free(x);
                        if (tt) |x| b.gpa.free(x);
                        if (ma) |x| b.gpa.free(x);
                        if (ba) |x| b.gpa.free(x);
                        if (vacio) |x| b.gpa.free(x);
                    }
                }
                pos = sp.fin;
                if (pos > linea.len) break;
            }
        }
        // 3. La línea entra al anillo (contexto de futuras).
        if (K > 0) {
            const dl = b.gpa.dupe(u8, linea[0..@min(linea.len, MAX_TEXTO_MATCH)]) catch continue;
            if (n_anillo == K) {
                b.gpa.free(anillo[0]);
                std.mem.copyForwards([]const u8, anillo[0 .. K - 1], anillo[1..K]);
                n_anillo = K - 1;
            }
            anillo[n_anillo] = dl;
            n_anillo += 1;
        }
    }
    if (lineas_malas) b.omitidos += 1; // 1 vez por archivo con líneas ilegibles
}

// `rel` = ruta mostrada (relativa a la raíz); `dir` = handle abierto.
fn camina(b: *Busca, dir: Io.Dir, rel: []const u8, prof: u8) void {
    if (prof > MAX_PROF) {
        b.omitidos += 1;
        return;
    }
    var it = dir.iterate();
    while (it.next(b.io) catch {
        b.omitidos += 1;
        return;
    }) |e| {
        if (e.name.len == 0 or e.name[0] == '.') continue;
        if (b.excluir.len > 0 and excluido(b.excluir, e.name)) continue;
        const es_dir = e.kind == .directory or
            (e.kind == .sym_link and esDirEnlace(dir, b.io, e.name));
        if (es_dir) {
            if (esSaltoDir(e.name)) continue;
            if (!b.recursivo) continue;
            var sub = dir.openDir(b.io, e.name, .{ .iterate = true }) catch {
                b.omitidos += 1;
                continue;
            };
            defer sub.close(b.io);
            const rel2 = std.fmt.allocPrint(b.gpa, "{s}{s}{s}", .{ rel, if (rel.len == 0) "" else "/", e.name }) catch continue;
            defer b.gpa.free(rel2);
            camina(b, sub, rel2, prof + 1);
            continue;
        }
        if (b.glob.len > 0 and !globMatch(b.glob, e.name)) continue;
        const rel2 = std.fmt.allocPrint(b.gpa, "{s}{s}{s}", .{ rel, if (rel.len == 0) "" else "/", e.name }) catch continue;
        defer b.gpa.free(rel2);
        buscaArchivo(b, dir, e.name, rel2);
    }
}

// Un enlace a carpeta se omite (evita ciclos); a archivo se lee.
pub fn esDirEnlace(dir: Io.Dir, io: Io, nombre: []const u8) bool {
    const st = dir.statFile(io, nombre, .{}) catch return false;
    return st.kind == .directory;
}

// Opciones de busqueda (struct para crecer sin romper llamadas).
pub const BuscarOpts = struct {
    raiz: []const u8,
    patron: []const u8,
    sensible: bool = false, // true = distingue mayusculas
    recursivo: bool = true,
    glob: []const u8 = "",
    max: usize = 50,
    contexto: usize = 0,
    palabra: bool = false,
    excluir: []const u8 = "",
    regex: bool = false, // true = patron es expresion regular
};

pub fn buscar(gpa: std.mem.Allocator, io: Io, o: BuscarOpts) !SearchOut {
    if (o.patron.len == 0) return error.PatronVacio;
    if (o.patron.len > MAX_PATRON) return error.PatronLargo;
    try checkPath(o.raiz);
    // Si es regex, compilar una vez (case-insensitive salvo `sensible`).
    var rx: ?regex.Regex = null;
    if (o.regex) rx = try regex.compile(gpa, o.patron, .{ .ci = !o.sensible });
    defer if (rx) |*r| r.deinit();
    var b: Busca = .{
        .gpa = gpa,
        .io = io,
        .patron = o.patron,
        .sensible = o.sensible,
        .recursivo = o.recursivo,
        .glob = o.glob,
        .max = o.max,
        .contexto = o.contexto,
        .palabra = o.palabra,
        .excluir = o.excluir,
        .rx = rx,
        .tmp = .empty,
        .total = 0,
        .omitidos = 0,
    };
    errdefer {
        for (b.tmp.items) |m| {
            freeOwned(gpa, m.archivo);
            freeOwned(gpa, m.texto);
            freeOwned(gpa, m.matched);
            freeOwned(gpa, m.antes);
            freeOwned(gpa, m.despues);
        }
        b.tmp.deinit(gpa);
    }
    const raiz = o.raiz;
    const glob = o.glob;
    // ¿Archivo suelto o carpeta?
    const st = statUno(io, raiz) catch |e| return e;
    if (st.kind != .directory) {
        if (glob.len > 0) {
            const base = std.fs.path.basename(raiz);
            if (!globMatch(glob, base)) return .{ .matches = try b.tmp.toOwnedSlice(gpa), .total = 0, .omitidos = 0, .truncado = false };
        }
        // Abrir por carpeta padre para reutilizar buscaArchivo.
        if (std.fs.path.dirname(raiz)) |d| {
            if (d.len > 0 and !std.mem.eql(u8, d, ".")) {
                var dir = if (std.fs.path.isAbsolute(raiz))
                    Io.Dir.openDirAbsolute(io, d, .{}) catch |e| return e
                else
                    Io.Dir.cwd().openDir(io, d, .{}) catch |e| return e;
                defer dir.close(io);
                buscaArchivo(&b, dir, std.fs.path.basename(raiz), raiz);
            } else {
                buscaArchivo(&b, Io.Dir.cwd(), std.fs.path.basename(raiz), raiz);
            }
        } else {
            buscaArchivo(&b, Io.Dir.cwd(), raiz, raiz);
        }
    } else {
        var dir = if (std.fs.path.isAbsolute(raiz))
            try Io.Dir.openDirAbsolute(io, raiz, .{ .iterate = true })
        else
            try Io.Dir.cwd().openDir(io, raiz, .{ .iterate = true });
        defer dir.close(io);
        camina(&b, dir, "", 0);
    }
    std.mem.sort(Match, b.tmp.items, {}, struct {
        fn lt(_: void, a: Match, c: Match) bool {
            const ord = std.mem.order(u8, a.archivo, c.archivo);
            if (ord != .eq) return ord == .lt;
            if (a.linea != c.linea) return a.linea < c.linea;
            return a.col < c.col;
        }
    }.lt);
    const truncado = b.total > b.tmp.items.len;
    return .{ .matches = try b.tmp.toOwnedSlice(gpa), .total = b.total, .omitidos = b.omitidos, .truncado = truncado };
}

// ---------- Tests (los corre `zig build test`) ----------

test "encuentra: sensible e insensible a mayúsculas" {
    const t = std.testing;
    const a = encuentra("Hola Mundo", "mundo", false).?;
    try t.expectEqual(@as(usize, 5), a.ini);
    try t.expectEqual(@as(usize, 10), a.fin);
    try t.expect(encuentra("Hola Mundo", "mundo", true) == null);
    try t.expect(encuentra("Hola", "Hola", true) != null);
}

test "siguienteValido: varias ocurrencias por linea (substring y word)" {
    const t = std.testing;
    var b: Busca = .{
        .gpa = t.allocator,
        .io = undefined,
        .patron = "ab",
        .sensible = true,
        .recursivo = true,
        .glob = "",
        .max = 10,
        .contexto = 0,
        .palabra = false,
        .excluir = "",
        .rx = null,
        .tmp = .empty,
        .total = 0,
        .omitidos = 0,
    };
    // No solapado: "xababab" -> ab en cols 2,4,6.
    var cols: [4]usize = undefined;
    var n: usize = 0;
    var pos: usize = 0;
    while (siguienteValido(&b, "xababab", pos)) |sp| {
        cols[n] = sp.ini + 1;
        n += 1;
        pos = sp.fin;
    }
    try t.expectEqual(@as(usize, 3), n);
    try t.expectEqual(@as(usize, 2), cols[0]);
    try t.expectEqual(@as(usize, 4), cols[1]);
    try t.expectEqual(@as(usize, 6), cols[2]);
    // `word`: "abx" no cuenta -> "ab abx ab" da cols 1 y 8.
    b.palabra = true;
    pos = 0;
    n = 0;
    while (siguienteValido(&b, "ab abx ab", pos)) |sp| {
        cols[n] = sp.ini + 1;
        n += 1;
        pos = sp.fin;
    }
    try t.expectEqual(@as(usize, 2), n);
    try t.expectEqual(@as(usize, 1), cols[0]);
    try t.expectEqual(@as(usize, 8), cols[1]);
}

test "esBorde y esSaltoDir" {
    const t = std.testing;
    try t.expect(esBorde(' '));
    try t.expect(!esBorde('a'));
    try t.expect(!esBorde('_')); // `_` es "palabra", no borde
    try t.expect(esSaltoDir("node_modules"));
    try t.expect(esSaltoDir("zig-out"));
    try t.expect(!esSaltoDir("src"));
}

test "excluido: globs separados por coma" {
    const t = std.testing;
    try t.expect(excluido("*.zig, *.md", "main.zig"));
    try t.expect(excluido("node_modules", "node_modules"));
    try t.expect(!excluido("*.zig", "main.txt"));
    try t.expect(!excluido("", "cualquiera"));
}
