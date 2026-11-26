// Trabajos en segundo plano (sin bloquear al worker efímero).
// Cada job vive en TEMP/sys-jobs/<id>/ con: input.txt (guion),
// out.log, err.log, done (código al terminar), meta.txt
// (pid/started/timeout) y cmd.txt. Sin registro global (la carpeta
// ES el registro: `list` la recorre; `forget` la borra).
// Límites honestos: el timeout se aplica en `poll` (perezoso);
// un `exit` del usuario omite el tráiler → exit:null + nota.

const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const fstool = @import("../fs/fstool.zig");
const exectool = @import("exectool.zig");
const systool = @import("../core/systool.zig");
const proc = @import("proc.zig");

pub const DEF_BG_TIMEOUT: u32 = 300000; // 5 min
pub const MIN_BG_TIMEOUT: u32 = 1000;
pub const MAX_BG_TIMEOUT: u32 = 3600000; // 1 h
pub const MAX_JOBS_LIST: usize = 100;

var g_env: ?*const std.process.Environ.Map = null;

pub fn setEnvSrc(m: *const std.process.Environ.Map) void {
    g_env = m;
}

pub fn msgDe(err: anyerror) []const u8 {
    return switch (err) {
        error.JobDesconocido => "Job desconocido. Tip: usa job list.",
        error.IdMal => "Invalid params: job debe ser texto del job.",
        error.SinTemporal => "Sin carpeta temporal (falta TEMP).",
        error.SinEntorno => "Sin entorno (interno).",
        error.NoPid => "No se pudo obtener el pid del hijo.",
        error.TimeoutValor => "Invalid params: timeout_ms debe ser entero 1000-3600000.",
        else => fstool.msgDe(err),
    };
}

// Solo [A-Za-z0-9_-], 1..64 (sin puntos ni barras: no escapa del dir).
fn idValido(id: []const u8) bool {
    if (id.len == 0 or id.len > 64) return false;
    for (id) |c| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or c == '-' or c == '_';
        if (!ok) return false;
    }
    return true;
}

fn dirBase(gpa: std.mem.Allocator, io: Io) ![]u8 {
    const tmp = systool.tempDir(io) orelse return error.SinTemporal;
    return try std.fmt.allocPrint(gpa, "{s}/sys-jobs", .{tmp});
}

fn dirJob(gpa: std.mem.Allocator, io: Io, id: []const u8) ![]u8 {
    if (!idValido(id)) return error.IdMal;
    const base = try dirBase(gpa, io);
    defer gpa.free(base);
    return try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base, id });
}

fn ahoraMs(io: Io) i64 {
    return Io.Timestamp.now(io, .awake).toMilliseconds();
}

// Trunca en borde de carácter UTF-8 (para mostrar cmd en list).
fn recortaUtf8(s: []const u8, n: usize) []const u8 {
    if (s.len <= n) return s;
    var c = n;
    while (c > 0 and (s[c] & 0xC0) == 0x80) c -= 1;
    return s[0..c];
}

pub const Meta = struct { pid: i64, started: i64, timeout: u32 };

fn leeMeta(gpa: std.mem.Allocator, io: Io, id: []const u8) !Meta {
    const dj = try dirJob(gpa, io, id);
    defer gpa.free(dj);
    const mp = try std.fmt.allocPrint(gpa, "{s}/meta.txt", .{dj});
    defer gpa.free(mp);
    const txt = Io.Dir.cwd().readFileAlloc(io, mp, gpa, .limited(256)) catch return error.JobDesconocido;
    defer gpa.free(txt);
    var it = std.mem.splitScalar(u8, txt, '\n');
    const p = std.fmt.parseInt(i64, it.next() orelse return error.JobDesconocido, 10) catch return error.JobDesconocido;
    const s = std.fmt.parseInt(i64, it.next() orelse return error.JobDesconocido, 10) catch return error.JobDesconocido;
    const t = std.fmt.parseInt(u32, std.mem.trim(u8, it.next() orelse return error.JobDesconocido, " \t\r"), 10) catch return error.JobDesconocido;
    return .{ .pid = p, .started = s, .timeout = t };
}

fn existeArchivo(io: Io, path: []const u8) bool {
    var f = Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    f.close(io);
    return true;
}

// ---------- SO: pid, vida, muerte (externs propios, sin dependencias) ----------

const win = if (builtin.os.tag == .windows) struct {
    const HANDLE = std.os.windows.HANDLE;
    const DWORD = u32;
    const BOOL = c_int;
    const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;
    const PROCESS_TERMINATE: DWORD = 0x0001;
    const STILL_ACTIVE: DWORD = 259;
    extern "kernel32" fn GetProcessId(hProcess: HANDLE) callconv(.winapi) DWORD;
    extern "kernel32" fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwProcessId: DWORD) callconv(.winapi) ?HANDLE;
    extern "kernel32" fn GetExitCodeProcess(hProcess: HANDLE, lpExitCode: *DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: c_uint) callconv(.winapi) BOOL;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
    extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.winapi) ?HANDLE;
    extern "kernel32" fn SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD) callconv(.winapi) BOOL;
    const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
    const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
    const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));
    const HANDLE_FLAG_INHERIT: DWORD = 1;
} else struct {};

fn pidHijo(child: *std.process.Child) ?u32 {
    if (builtin.os.tag == .windows) {
        const h = child.id orelse return null;
        const pid = win.GetProcessId(h);
        if (pid == 0) return null;
        return pid;
    }
    const pid: std.posix.pid_t = child.id orelse return null;
    if (pid <= 0) return null;
    return @intCast(pid);
}

// ¿Sigue vivo? (Windows: ExitCode==STILL_ACTIVE; Unix: kill(pid,0)).
fn vivo(pid: u32) bool {
    if (builtin.os.tag == .windows) {
        const h = win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) orelse return false;
        defer _ = win.CloseHandle(h);
        var code: win.DWORD = 0;
        if (win.GetExitCodeProcess(h, &code) == 0) return false;
        return code == win.STILL_ACTIVE;
    }
    std.posix.kill(@intCast(pid), @enumFromInt(0)) catch |e| switch (e) {
        error.ProcessNotFound => return false,
        else => return true, // sin permiso pero existe
    };
    return true;
}

// Código de salida si ya terminó (Windows; Unix: null, sin waitpid).
fn codigo(pid: u32) ?u8 {
    if (builtin.os.tag != .windows) return null;
    const h = win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) orelse return null;
    defer _ = win.CloseHandle(h);
    var code: win.DWORD = 0;
    if (win.GetExitCodeProcess(h, &code) == 0) return null;
    if (code == win.STILL_ACTIVE) return null;
    return @intCast(code & 0xFF);
}

// Mata el proceso y sus descendientes (Windows: Job/Toolhelp; Unix:
// grupo de procesos vía kill(-pid)). Si no se mata el árbol quedan
// huérfanos vivos (node/python/powershell del script). Delegado en el
// módulo compartido para que exec y job usen el mismo tree-kill.
fn matarArbol(pid: u32, prof: u8) bool {
    return proc.matarArbol(pid, prof);
}

// ---------- Operaciones ----------

var seq_job = std.atomic.Value(u32).init(0);

pub const Lanzado = struct { id: []u8, pid: u32, dir: []u8 };

// Lanza el comando en fondo. El dueño libera id y dir.
pub fn lanzar(gpa: std.mem.Allocator, io: Io, cmd: []const u8, cwd: ?[]const u8, timeout_ms: u32) !Lanzado {
    try exectool.checkCmd(cmd);
    if (timeout_ms < MIN_BG_TIMEOUT or timeout_ms > MAX_BG_TIMEOUT) return error.TimeoutValor;
    const base = try dirBase(gpa, io);
    defer gpa.free(base);
    Io.Dir.cwd().createDirPath(io, base) catch {};
    // Reclamo atómico del id (createDir falla si existe → otro n).
    var n: u32 = seq_job.fetchAdd(1, .monotonic);
    const dj: []u8 = while (true) {
        const ms = ahoraMs(io);
        const dd = try std.fmt.allocPrint(gpa, "{s}/{d}-{d}", .{ base, ms, n });
        errdefer gpa.free(dd);
        Io.Dir.cwd().createDir(io, dd, .default_dir) catch |e| {
            gpa.free(dd);
            if (e == error.PathAlreadyExists) {
                n += 1;
                continue;
            }
            return e;
        };
        break dd;
    };
    errdefer Io.Dir.cwd().deleteTree(io, dj) catch {};
    const id_dup = try gpa.dupe(u8, std.fs.path.basename(dj));
    errdefer gpa.free(id_dup);
    // Guion por stdin (igual que exec: comillas y % intactos).
    // OJO: espacio antes de `>` (`echo 0>file` fusiona el dígito como
    // descriptor y deja a echo sin args; vale para cmd y sh).
    const is_win = builtin.os.tag == .windows;
    const guion = if (is_win)
        try std.fmt.allocPrint(gpa, "@echo off\r\n{s}\r\n\r\necho %errorlevel% > \"{s}/done\"\r\n", .{ cmd, dj })
    else
        try std.fmt.allocPrint(gpa, "{s}\n\necho $? > '{s}/done'\n", .{ cmd, dj });
    defer gpa.free(guion);
    const pin = try std.fmt.allocPrint(gpa, "{s}/input.txt", .{dj});
    defer gpa.free(pin);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = pin, .data = guion }) catch |e| return e;
    // PROMPT=$H como en exec (prompts de 1 byte, fáciles de quitar).
    const env = g_env orelse return error.SinEntorno;
    var em: std.process.Environ.Map = .{ .array_hash_map = try env.array_hash_map.clone(gpa), .allocator = gpa };
    defer em.array_hash_map.deinit(gpa);
    if (is_win) try em.array_hash_map.put(gpa, "PROMPT", "$H");
    var fin = try Io.Dir.cwd().openFile(io, pin, .{});
    errdefer fin.close(io);
    const pout = try std.fmt.allocPrint(gpa, "{s}/out.log", .{dj});
    defer gpa.free(pout);
    var fout = try Io.Dir.cwd().createFile(io, pout, .{});
    errdefer fout.close(io);
    const perr = try std.fmt.allocPrint(gpa, "{s}/err.log", .{dj});
    defer gpa.free(perr);
    var ferr = try Io.Dir.cwd().createFile(io, perr, .{});
    errdefer ferr.close(io);
    const argv: []const []const u8 = if (is_win) &.{ "cmd.exe", "/D", "/Q" } else &.{ "sh" };
    if (is_win) {
        // El nieto NO debe heredar nuestros pipes de stdio: si los
        // hereda, quien nos llamó espera EOF hasta que el nieto muera
        // (el `start` bloquearía lo que dure el job). Se quita el flag
        // heredable (nuestro uso no se afecta; el worker es efímero).
        const stds = [_]win.DWORD{ win.STD_INPUT_HANDLE, win.STD_OUTPUT_HANDLE, win.STD_ERROR_HANDLE };
        for (stds) |s| {
            if (win.GetStdHandle(s)) |h| _ = win.SetHandleInformation(h, win.HANDLE_FLAG_INHERIT, 0);
        }
    }
    var child = try std.process.spawn(io, .{
        .argv = argv,
        // Unix: nuevo grupo (líder = hijo) para el tree-kill de matarArbol.
        .pgid = if (is_win) null else 0,
        .cwd = if (cwd) |d| .{ .path = d } else .inherit,
        .environ_map = &em,
        .stdin = .{ .file = fin },
        .stdout = .{ .file = fout },
        .stderr = .{ .file = ferr },
    });
    // El hijo sigue solo: cierro mis copias, sin wait ni kill.
    fin.close(io);
    fout.close(io);
    ferr.close(io);
    const pid = pidHijo(&child) orelse return error.NoPid;
    const meta = try std.fmt.allocPrint(gpa, "{d}\n{d}\n{d}\n", .{ pid, ahoraMs(io), timeout_ms });
    defer gpa.free(meta);
    const pmeta = try std.fmt.allocPrint(gpa, "{s}/meta.txt", .{dj});
    defer gpa.free(pmeta);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = pmeta, .data = meta }) catch |e| return e;
    const pcmd = try std.fmt.allocPrint(gpa, "{s}/cmd.txt", .{dj});
    defer gpa.free(pcmd);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = pcmd, .data = cmd }) catch |e| return e;
    return .{ .id = id_dup, .pid = pid, .dir = dj };
}

pub const Estado = struct {
    running: bool,
    exit: ?u8,
    elapsed_ms: i64,
    timed_out: bool,
    killed: bool,
    nota: []const u8, // "" si no aplica (no liberar)
};

// Cola de un job: done? → código; vivo? → (timeout? mata) ; si no → nota.
pub fn sondear(gpa: std.mem.Allocator, io: Io, id: []const u8) !Estado {
    const mt = try leeMeta(gpa, io, id);
    const dj = try dirJob(gpa, io, id);
    defer gpa.free(dj);
    const elap = @max(0, ahoraMs(io) - mt.started);
    const pk = try std.fmt.allocPrint(gpa, "{s}/killed", .{dj});
    defer gpa.free(pk);
    if (existeArchivo(io, pk)) return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = true, .nota = "" };
    const pd = try std.fmt.allocPrint(gpa, "{s}/done", .{dj});
    defer gpa.free(pd);
    if (existeArchivo(io, pd)) {
        const txt = Io.Dir.cwd().readFileAlloc(io, pd, gpa, .limited(32)) catch
            return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "código ilegible en done" };
        defer gpa.free(txt);
        const limpio = std.mem.trim(u8, txt, " \t\r\n");
        if (limpio.len != 0) {
            const code = std.fmt.parseInt(i64, limpio, 10) catch
                return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "código ilegible en done" };
            const ec: u8 = @intCast(@mod(code, 256));
            return .{ .running = false, .exit = ec, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "" };
        }
        // El shell redirige (crea) `done` antes de escribir el código. Si
        // el archivo está vacío pero el proceso vive, todavía está
        // cerrando: reportar `running` evita el transitorio "terminó pero
        // sin código"; el siguiente poll ya lee el código real.
        const pid_done: u32 = @intCast(@max(0, mt.pid));
        if (pid_done != 0 and vivo(pid_done))
            return .{ .running = true, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "" };
        return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "done sin contenido" };
    }
    const pid: u32 = @intCast(@max(0, mt.pid));
    if (pid == 0) return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "pid inválido en meta" };
    if (vivo(pid)) {
        if (elap > mt.timeout) {
            _ = matarArbol(pid, 0);
            return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = true, .killed = false, .nota = "" };
        }
        return .{ .running = true, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "" };
    }
    // Muerto sin done (exit/crash): sin código disponible.
    if (codigo(pid)) |c| return .{ .running = false, .exit = c, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "" };
    return .{ .running = false, .exit = null, .elapsed_ms = elap, .timed_out = false, .killed = false, .nota = "terminó sin dejar código (¿exit/crash?)" };
}

// Mata el proceso (+árbol en Windows) y deja marca `killed`.
pub fn detener(gpa: std.mem.Allocator, io: Io, id: []const u8) !bool {
    const mt = try leeMeta(gpa, io, id);
    const pid: u32 = @intCast(@max(0, mt.pid));
    if (pid == 0) return false;
    const ok = matarArbol(pid, 0);
    if (!ok) return false; // ya muerto: poll dirá muerte natural
    const dj = try dirJob(gpa, io, id);
    defer gpa.free(dj);
    const pk = try std.fmt.allocPrint(gpa, "{s}/killed", .{dj});
    defer gpa.free(pk);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = pk, .data = "" }) catch {};
    return ok;
}

pub fn olvidar(gpa: std.mem.Allocator, io: Io, id: []const u8) !void {
    const dj = try dirJob(gpa, io, id);
    defer gpa.free(dj);
    // Existe? (deleteTree traga FileNotFound: verificar antes).
    var d = Io.Dir.cwd().openDir(io, dj, .{}) catch return error.JobDesconocido;
    d.close(io);
    try Io.Dir.cwd().deleteTree(io, dj);
}

// Cola de un log (out/err): últimos max_bytes, limpio de banner/prompts.
pub fn colaLog(gpa: std.mem.Allocator, io: Io, id: []const u8, cual: []const u8, max_bytes: usize) ![]u8 {
    const dj = try dirJob(gpa, io, id);
    defer gpa.free(dj);
    const pl = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dj, cual });
    defer gpa.free(pl);
    var f = Io.Dir.cwd().openFile(io, pl, .{}) catch return try gpa.dupe(u8, "");
    defer f.close(io);
    const st = try f.stat(io);
    const tope: usize = @min(@as(usize, @intCast(@max(0, st.size))), max_bytes + 512);
    var rbuf: [4096]u8 = undefined;
    var r = f.reader(io, &rbuf);
    if (st.size > max_bytes + 512) {
        const desde: u64 = @intCast(st.size - (max_bytes + 512));
        r.seekTo(desde) catch {};
    }
    const crudo = r.interface.allocRemaining(gpa, Io.Limit.limited(tope + 1)) catch |e| {
        if (e == error.StreamTooLong) return try gpa.dupe(u8, "");
        return e;
    };
    defer gpa.free(crudo);
    // Empieza en línea completa (salta resto parcial inicial).
    var s = crudo;
    if (st.size > max_bytes + 512) {
        if (std.mem.indexOfScalar(u8, s, '\n')) |i| s = s[i + 1 ..] else s = s[s.len..];
    }
    if (s.len > max_bytes) s = s[s.len - max_bytes ..];
    // Limpieza cmd (banner/prompts) igual que exec.
    const limpio = try exectool.limpiarSalida(gpa, s);
    errdefer gpa.free(limpio);
    return limpio;
}

pub const MAX_TAIL_LINES: usize = 200;

// Últimas `n` líneas de un texto (slice, sin alloc). n==0 → todo.
pub fn ultimasLineas(texto: []const u8, n: usize) []const u8 {
    if (n == 0) return texto;
    var lineas: usize = 0;
    var i: usize = texto.len;
    // Recorta un \n final para no contar línea fantasma.
    var fin = texto.len;
    while (fin > 0 and (texto[fin - 1] == '\n' or texto[fin - 1] == '\r')) fin -= 1;
    i = fin;
    while (i > 0) {
        if (texto[i - 1] == '\n') {
            lineas += 1;
            if (lineas >= n) return texto[i..];
        }
        i -= 1;
    }
    return texto;
}

pub const ItemLista = struct { id: []u8, pid: i64, cmd: []u8, running: bool, elapsed_ms: i64 };

pub const ListaOut = struct { items: []ItemLista, total: usize, truncado: bool };

pub fn freeLista(gpa: std.mem.Allocator, l: *ListaOut) void {
    for (l.items) |it| {
        gpa.free(it.id);
        gpa.free(it.cmd);
    }
    gpa.free(l.items);
    l.items = &.{};
}

// Lista jobs (máx 100): estado best-effort por id.
pub fn listar(gpa: std.mem.Allocator, io: Io) !ListaOut {
    var out: std.ArrayList(ItemLista) = .empty;
    errdefer {
        for (out.items) |it| {
            gpa.free(it.id);
            gpa.free(it.cmd);
        }
        out.deinit(gpa);
    }
    const base = dirBase(gpa, io) catch return .{ .items = try out.toOwnedSlice(gpa), .total = 0, .truncado = false };
    defer gpa.free(base);
    var dir = Io.Dir.cwd().openDir(io, base, .{ .iterate = true }) catch
        return .{ .items = try out.toOwnedSlice(gpa), .total = 0, .truncado = false };
    defer dir.close(io);
    var it = dir.iterate();
    var total: usize = 0;
    while (true) {
        const en = it.next(io) catch break;
        if (en == null) break;
        const e = en.?;
        if (e.name.len == 0 or e.name[0] == '.' or e.kind == .file) continue;
        if (!idValido(e.name)) continue;
        total += 1;
        if (out.items.len >= MAX_JOBS_LIST) continue;
        const id = gpa.dupe(u8, e.name) catch continue;
        errdefer gpa.free(id);
        const mt = leeMeta(gpa, io, id) catch {
            gpa.free(id);
            continue;
        };
        const dj = dirJob(gpa, io, id) catch {
            gpa.free(id);
            continue;
        };
        defer gpa.free(dj);
        const pc = std.fmt.allocPrint(gpa, "{s}/cmd.txt", .{dj}) catch {
            gpa.free(id);
            continue;
        };
        defer gpa.free(pc);
        const cmd = Io.Dir.cwd().readFileAlloc(io, pc, gpa, .limited(4096)) catch {
            gpa.free(id);
            continue;
        };
        const elap = @max(0, ahoraMs(io) - mt.started);
        const pk = std.fmt.allocPrint(gpa, "{s}/killed", .{dj}) catch {
            gpa.free(id);
            gpa.free(cmd);
            continue;
        };
        defer gpa.free(pk);
        const pd = std.fmt.allocPrint(gpa, "{s}/done", .{dj}) catch {
            gpa.free(id);
            gpa.free(cmd);
            continue;
        };
        defer gpa.free(pd);
        const pid: u32 = @intCast(@max(0, mt.pid));
        const running = pid != 0 and !existeArchivo(io, pk) and !existeArchivo(io, pd) and vivo(pid);
        out.append(gpa, .{ .id = id, .pid = mt.pid, .cmd = cmd, .running = running, .elapsed_ms = elap }) catch {
            gpa.free(id);
            gpa.free(cmd);
            continue;
        };
    }
    const truncado = total > out.items.len;
    std.mem.sort(ItemLista, out.items, {}, struct {
        fn lt(_: void, a: ItemLista, b: ItemLista) bool {
            return std.mem.order(u8, a.id, b.id) == .lt;
        }
    }.lt);
    return .{ .items = try out.toOwnedSlice(gpa), .total = total, .truncado = truncado };
}

test "idValido" {
    const t = std.testing;
    try t.expect(idValido("123-4"));
    try t.expect(!idValido(""));
    try t.expect(!idValido("../x"));
    try t.expect(!idValido("a/b"));
    try t.expect(!idValido("a.b"));
}

test "ultimasLineas" {
    const t = std.testing;
    try t.expectEqualStrings("b\nc\n", ultimasLineas("a\nb\nc\n", 2));
    try t.expectEqualStrings("c\n", ultimasLineas("a\nb\nc\n", 1));
    try t.expectEqualStrings("a\nb\nc\n", ultimasLineas("a\nb\nc\n", 9));
    try t.expectEqualStrings("b", ultimasLineas("a\nb", 1));
    try t.expectEqualStrings("", ultimasLineas("", 3));
    try t.expectEqualStrings("a\nb", ultimasLineas("a\nb", 0));
}
