// Transporte stdio + respuestas JSON-RPC 2.0 (sin logica de tiempo).
// Lo usan `mcp/tools.zig` (dispatch) y `core/jsonw.zig` (resultados).

const std = @import("std");
const Io = std.Io;

pub const Ctx = struct {
    io: Io,
    out: *Io.Writer,
    id: std.json.Value, // siempre presente aqui (los calls sin id se ignoran)
    args: ?std.json.Value, // objeto "arguments" o null
};

pub fn bracesBalanced(s: []const u8) bool {
    var depth: i32 = 0;
    var in_str = false;
    var esc = false;
    for (s) |c| {
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == '"') {
                in_str = false;
            }
            continue;
        }
        if (c == '"') {
            in_str = true;
        } else if (c == '{' or c == '[') {
            depth += 1;
        } else if (c == '}' or c == ']') {
            depth -= 1;
            if (depth < 0) return false;
        }
    }
    return depth == 0 and !in_str;
}

/// ¿La linea sola ya es un mensaje JSON completo? Se usa para rescatar
/// la sesion cuando lo acumulado previo era basura (ver bucle principal).
pub fn parsesAsObject(raw: []const u8, gpa: std.mem.Allocator) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    return parsed.value == .object;
}

pub fn argStr(args: ?std.json.Value, key: []const u8, dflt: []const u8) []const u8 {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| {
                if (v == .string) return v.string;
            }
        }
    }
    return dflt;
}

/// Devuelve el string si `key` existe y es string; null si no.
pub fn argStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| {
                if (v == .string) return v.string;
            }
        }
    }
    return null;
}

pub fn argBool(args: ?std.json.Value, key: []const u8, dflt: bool) bool {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| {
                if (v == .bool) return v.bool;
            }
        }
    }
    return dflt;
}

pub fn has(args: ?std.json.Value, key: []const u8) bool {
    if (args) |a| {
        if (a == .object) return a.object.get(key) != null;
    }
    return false;
}

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
    try out.writeAll(",\"message\":");
    var js: std.json.Stringify = .{ .writer = out, .options = .{} };
    try js.write(msg);
    try out.writeAll("}}\n");
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
