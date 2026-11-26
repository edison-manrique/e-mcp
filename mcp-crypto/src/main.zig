// Entrada delgada. Sin argumentos: servidor MCP por stdio (persistente).
// Con argumentos: CLI efímero (ver cli/cli.zig). El transporte y el dispatch
// viven aquí; el registro de tools en mcp/tools.zig y el cálculo en bc/.
//
// CÓMO ESCALAR (nueva herramienta):
//   1. Nombre + schema en `registro.zig` (fuente unica).
//   2. Handler en `mcp/handlers.zig` + 1 línea en `mcp/tools.zig`.
//   Listo: `tools/list` y `tools/call` funcionan solos (aunque el servidor
//   externo (emcp) mantiene su propia tabla de mapeo al CLI).

const std = @import("std");
const Io = std.Io;
const pkg = @import("mcp_crypto");
const proto = pkg.proto;
const registro = pkg.registro;
const tools = pkg.tools;
const cli = pkg.cli;

const INIT_JSON = std.fmt.comptimePrint("{{\"protocolVersion\":\"{s}\",\"capabilities\":{{\"tools\":{{}}}},\"serverInfo\":{{\"name\":\"{s}\",\"version\":\"{s}\"}}}}", .{ registro.PROTOCOLO, registro.SERVIDOR, registro.VERSION });

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
        const code = cli.run(io, gpa, args[1..]) catch 1;
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
    // Arena por petición: toda la memoria temporal (JSON de salida, tablas de
    // vanity/kangaroo, etc.) se libera al terminar el request.
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const req_arena = arena_state.allocator();

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
    if (method.len >= 7 and std.mem.eql(u8, method[0..@min(method.len, 7)], "notify")) return;

    if (std.mem.eql(u8, method, "initialize")) {
        try proto.sendResult(out, id_opt, INIT_JSON);
        return;
    }
    if (std.mem.eql(u8, method, "ping")) {
        try proto.sendResult(out, id_opt, "{}");
        return;
    }
    if (std.mem.eql(u8, method, "tools/list")) {
        try tools.sendToolsList(out, id_opt);
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
        for (tools.TOOLS) |t| {
            if (std.mem.eql(u8, tool_name, t.name)) {
                try t.run(.{ .io = io, .out = out, .id = id, .args = args, .arena = req_arena });
                return;
            }
        }
        try proto.sendToolError(out, id, "Herramienta desconocida. Usa 'crypto_help' para ver la lista.");
        return;
    }
    try proto.sendJsonError(out, id_opt, -32601, "Method not found");
}
