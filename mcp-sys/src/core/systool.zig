// Info del SO y entorno (sin JSON: datos puros; main serializa).
// Procesos (ps/kill) van por `exec` con comandos nativos: evita
// duplicar APIs por SO y mantiene el binario chico.

const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

// Versión del servidor: fuente unica en `registro.zig` (de ahi salen el
// handshake MCP, la ayuda y el manifiesto firmado).
const registro = @import("../registro.zig");
pub const VERSION = registro.VERSION;

var g_env: ?*const std.process.Environ.Map = null;

pub fn setEnv(m: *const std.process.Environ.Map) void {
    g_env = m;
}

pub fn osName() []const u8 {
    return @tagName(builtin.os.tag);
}

pub fn archName() []const u8 {
    return @tagName(builtin.cpu.arch);
}

pub fn zigVersion() []const u8 {
    return builtin.zig_version_string;
}

// Auditoría por sesión (best-effort, nunca falla): 1 línea JSON por
// llamada en TEMP/sys-audit.log (rota a .old al pasar 1MB).
// exit=-1 significa sin código (timeout). cmd recortado a 200.
pub fn auditar(gpa: std.mem.Allocator, io: Io, herramienta: []const u8, cmd: []const u8, cwd: ?[]const u8, exit: i64, ms: i64) void {
    if (!auditoriaOn()) return;
    const tmp = tempDir(io) orelse return;
    Io.Dir.cwd().createDirPath(io, tmp) catch {};
    const plog = std.fmt.allocPrint(gpa, "{s}/sys-audit.log", .{tmp}) catch return;
    defer gpa.free(plog);
    const pold = std.fmt.allocPrint(gpa, "{s}/sys-audit.old.log", .{tmp}) catch return;
    defer gpa.free(pold);
    const cwd0 = Io.Dir.cwd();
    if (cwd0.statFile(io, plog, .{})) |st| {
        if (st.size > 1048576) {
            cwd0.deleteFile(io, pold) catch {};
            cwd0.rename(plog, cwd0, pold, io) catch {};
        }
    } else |_| {}
    var lbuf: [2048]u8 = undefined;
    var lw: Io.Writer = .fixed(&lbuf);
    var js: std.json.Stringify = .{ .writer = &lw, .options = .{} };
    js.beginObject() catch return;
    js.objectField("t") catch return;
    js.write(Io.Timestamp.now(io, .real).toMilliseconds()) catch return;
    js.objectField("tool") catch return;
    js.write(herramienta) catch return;
    js.objectField("cmd") catch return;
    js.write(recortaUtf8(cmd, 200)) catch return;
    js.objectField("cwd") catch return;
    js.write(cwd orelse "") catch return;
    js.objectField("exit") catch return;
    js.write(exit) catch return;
    js.objectField("ms") catch return;
    js.write(ms) catch return;
    js.endObject() catch return;
    // Append con lock exclusivo + escritura POSICIONAL en el offset
    // actual (no se relee el archivo): el read-modify-write anterior
    // perdía entradas con varios procesos a la vez.
    // OJO: el handle va con read=true; sin él, length() da AccessDenied
    // y escribiríamos en offset 0, corrompiendo el log.
    var linea: [2049]u8 = undefined;
    const jtxt = lw.buffered();
    @memcpy(linea[0..jtxt.len], jtxt);
    linea[jtxt.len] = '\n';
    const nueva = linea[0 .. jtxt.len + 1];
    const f = cwd0.createFile(io, plog, .{ .truncate = false, .read = true }) catch return;
    defer f.close(io);
    f.lock(io, .exclusive) catch {};
    const len = f.length(io) catch return; // sin tamaño, no arriesgamos corromper
    if (len + nueva.len > 1048577) return; // no crece sin control
    f.writePositionalAll(io, nueva, len) catch {};
}

fn recortaUtf8(s: []const u8, n: usize) []const u8 {
    if (s.len <= n) return s;
    var c = n;
    while (c > 0 and (s[c] & 0xC0) == 0x80) c -= 1;
    return s[0..c];
}

pub fn envGet(name: []const u8) ![]const u8 {
    const m = g_env orelse return error.SinEntorno;
    return m.array_hash_map.get(name) orelse error.SinVariable;
}

// ¿Se puede abrir `path` como directorio? (para detectar el RAM disk).
fn esDir(io: Io, path: []const u8) bool {
    var d = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

// Quita separadores finales (prestado) para poder unir con "/" sin doblar.
fn sinCola(p: []const u8) []const u8 {
    var n = p.len;
    while (n > 1 and (p[n - 1] == '/' or p[n - 1] == '\\')) n -= 1;
    return p[0..n];
}

// Carpeta temporal base (prestada, no liberar). Orden:
//   1. SYS_TMPDIR (override explicito).
//   2. RAM disk por defecto: Windows "R:\"; Unix "/dev/shm" (tmpfs).
//   3. Windows: TEMP o TMP. Unix: TMPDIR o /tmp.
pub fn tempDir(io: Io) ?[]const u8 {
    const raw: []const u8 = blk: {
        if (envGet("SYS_TMPDIR")) |d| {
            if (d.len != 0) break :blk d;
        } else |_| {}
        const ram = if (builtin.os.tag == .windows) "R:\\" else "/dev/shm";
        if (esDir(io, ram)) break :blk ram;
        if (builtin.os.tag == .windows)
            break :blk (envGet("TEMP") catch envGet("TMP") catch return null);
        break :blk (envGet("TMPDIR") catch "/tmp");
    };
    return sinCola(raw);
}

// Variable "activada": vacio=no; 0/false/no/off=no; cualquier otra cosa=si.
pub fn activado(v: []const u8) bool {
    if (v.len == 0) return false;
    const apagados = [_][]const u8{ "0", "false", "no", "off" };
    for (apagados) |o| if (std.ascii.eqlIgnoreCase(v, o)) return false;
    return true;
}

// Auditoria en disco: OFF por defecto (no escribir en cada llamada).
// Se activa con SYS_AUDIT=1/true/yes/on.
pub fn auditoriaOn() bool {
    return activado(envGet("SYS_AUDIT") catch return false);
}

pub const Par = struct { k: []const u8, v: []const u8 }; // prestados del mapa (no liberar)

pub const EnvList = struct {
    pares: []Par, // dueño: gpa
    total: usize, // matches totales (antes del tope)
    truncado: bool,
};

pub const MAX_ENV: usize = 200;

// Lista variables cuyo nombre contiene `filter` (insensible a
// mayúsculas; filtro vacío = todas). Libera con gpa.free(.pares).
pub fn envList(gpa: std.mem.Allocator, filter: []const u8) !EnvList {
    const m = g_env orelse return error.SinEntorno;
    var tmp: std.ArrayList(Par) = .empty;
    errdefer tmp.deinit(gpa);
    var total: usize = 0;
    var it = m.array_hash_map.iterator();
    while (it.next()) |kv| {
        const k = kv.key_ptr.*;
        const v = kv.value_ptr.*;
        if (filter.len > 0 and !contieneInsensible(k, filter)) continue;
        total += 1;
        if (tmp.items.len < MAX_ENV)
            try tmp.append(gpa, .{ .k = k, .v = v });
    }
    const truncado = total > tmp.items.len;
    return .{ .pares = try tmp.toOwnedSlice(gpa), .total = total, .truncado = truncado };
}

fn baja(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn contieneInsensible(hay: []const u8, aguja: []const u8) bool {
    if (aguja.len == 0) return true;
    if (aguja.len > hay.len) return false;
    var i: usize = 0;
    while (i + aguja.len <= hay.len) : (i += 1) {
        var ok = true;
        for (aguja, 0..) |c, j| {
            if (baja(hay[i + j]) != baja(c)) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

test "contieneInsensible" {
    const t = std.testing;
    try t.expect(contieneInsensible("PATH", "pat"));
    try t.expect(contieneInsensible("Path", "ATH"));
    try t.expect(!contieneInsensible("HOME", "pat"));
    try t.expect(contieneInsensible("A", ""));
}

test "activado reconoce on/off" {
    const t = std.testing;
    try t.expect(!activado(""));
    try t.expect(!activado("0"));
    try t.expect(!activado("false"));
    try t.expect(!activado("OFF"));
    try t.expect(!activado("No"));
    try t.expect(activado("1"));
    try t.expect(activado("yes"));
    try t.expect(activado("true"));
}
