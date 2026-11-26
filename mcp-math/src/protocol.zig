const std = @import("std");
const Io = std.Io;

// Contexto de una llamada a herramienta. Lo crea el dispatcher,
// lo consumen los handlers de main.zig.
pub const Ctx = struct {
    io: Io,
    out: *Io.Writer,
    id: std.json.Value,
    args: ?std.json.Value,
};

// ---------- Transporte: framing NDJSON ----------

pub fn bracesBalanced(s: []const u8) bool {
    var depth: i32 = 0;
    var in_str = false;
    var esc = false;
    for (s) |c| {
        if (in_str) {
            if (esc) esc = false else if (c == '\\') esc = true else if (c == '"') in_str = false;
            continue;
        }
        if (c == '"') in_str = true else if (c == '{' or c == '[') depth += 1 else if (c == '}' or c == ']') {
            depth -= 1;
            if (depth < 0) return true;
        }
    }
    return depth == 0 and !in_str;
}

// ¿La linea sola ya es un mensaje JSON completo? Rescate de sesion
// cuando lo acumulado previo era basura (ver bucle principal).
pub fn parsesAsObject(raw: []const u8, gpa: std.mem.Allocator) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    return parsed.value == .object;
}

// ---------- Argumentos JSON (helpers) ----------

pub fn argStr(args: ?std.json.Value, key: []const u8, dflt: []const u8) []const u8 {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| if (v == .string) return v.string;
        }
    }
    return dflt;
}

pub fn argDigits(args: ?std.json.Value) ?u8 {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("digits")) |v| {
                if (v == .integer and v.integer >= 0 and v.integer <= 15) return @intCast(v.integer);
            }
        }
    }
    return null;
}

pub fn argBool(args: ?std.json.Value, key: []const u8) bool {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| if (v == .bool) return v.bool;
        }
    }
    return false;
}

// ---------- Respuestas JSON-RPC ----------

pub fn writeId(out: *Io.Writer, id: ?std.json.Value) !void {
    if (id) |v| {
        var js: std.json.Stringify = .{ .writer = out, .options = .{} };
        try js.write(v);
    } else {
        try out.writeAll("null");
    }
}

pub fn sendResult(out: *Io.Writer, id: ?std.json.Value, result_raw: []const u8) !void {
    if (id == null) return;
    try out.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(out, id);
    try out.writeAll(",\"result\":");
    try out.writeAll(result_raw);
    try out.writeAll("}\n");
    try out.flush();
}

pub fn sendJsonError(out: *Io.Writer, id: ?std.json.Value, code: i32, msg: []const u8) !void {
    try out.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(out, id);
    try out.writeAll(",\"error\":{\"code\":");
    try out.print("{d}", .{code});
    try out.writeAll(",\"message\":\"");
    try out.writeAll(msg);
    try out.writeAll("\"}}\n");
    try out.flush();
}

pub fn sendToolText(out: *Io.Writer, id: std.json.Value, text: []const u8) !void {
    var js: std.json.Stringify = .{ .writer = out, .options = .{} };
    try js.beginObject();
    try js.objectField("jsonrpc");
    try js.write("2.0");
    try js.objectField("id");
    try js.write(id);
    try js.objectField("result");
    try js.beginObject();
    try js.objectField("content");
    try js.beginArray();
    try js.beginObject();
    try js.objectField("type");
    try js.write("text");
    try js.objectField("text");
    try js.write(text);
    try js.endObject();
    try js.endArray();
    try js.endObject();
    try js.endObject();
    try out.writeAll("\n");
    try out.flush();
}

pub fn sendToolError(out: *Io.Writer, id: std.json.Value, msg: []const u8) !void {
    var js: std.json.Stringify = .{ .writer = out, .options = .{} };
    try js.beginObject();
    try js.objectField("jsonrpc");
    try js.write("2.0");
    try js.objectField("id");
    try js.write(id);
    try js.objectField("result");
    try js.beginObject();
    try js.objectField("content");
    try js.beginArray();
    try js.beginObject();
    try js.objectField("type");
    try js.write("text");
    try js.objectField("text");
    try js.write(msg);
    try js.endObject();
    try js.endArray();
    try js.objectField("isError");
    try js.write(true);
    try js.endObject();
    try js.endObject();
    try out.writeAll("\n");
    try out.flush();
}
