//! Transporte stdio + framing NDJSON + respuestas JSON-RPC 2.0 compartido.
//! Fuente única para todos los servidores MCP del repositorio (`emcp`,
//! `mcp-crypto`, `mcp-math`, `mcp-sys`, `mcp-time`).

const std = @import("std");
const Io = std.Io;

/// Contexto de una llamada a herramienta MCP (`tools/call`).
pub const Ctx = struct {
    io: Io,
    out: *Io.Writer,
    id: std.json.Value,
    args: ?std.json.Value,
    arena: std.mem.Allocator = undefined,
};

// ---------- Transporte: framing NDJSON ----------

/// Comprueba si el buffer acumulado tiene llaves y corchetes balanceados fuera de strings.
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

/// Comprueba si `raw` por sí solo es un objeto JSON válido (rescate de sesión).
pub fn parsesAsObject(raw: []const u8, gpa: std.mem.Allocator) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    return parsed.value == .object;
}

// ---------- Lectura tolerante de argumentos ----------

fn getField(args: ?std.json.Value, key: []const u8) ?std.json.Value {
    const a = args orelse return null;
    if (a != .object) return null;
    return a.object.get(key);
}

pub fn has(args: ?std.json.Value, key: []const u8) bool {
    return getField(args, key) != null;
}

pub fn argStr(args: ?std.json.Value, key: []const u8, dflt: []const u8) []const u8 {
    return argStrOpt(args, key) orelse dflt;
}

pub fn argStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    const v = getField(args, key) orelse return null;
    return if (v == .string) v.string else null;
}

pub fn argBool(args: ?std.json.Value, key: []const u8, dflt: bool) bool {
    const v = getField(args, key) orelse return dflt;
    return if (v == .bool) v.bool else dflt;
}

pub fn argInt(args: ?std.json.Value, key: []const u8) ?i64 {
    const v = getField(args, key) orelse return null;
    return if (v == .integer) v.integer else null;
}

pub fn argDigits(args: ?std.json.Value) ?u8 {
    const n = argInt(args, "digits") orelse return null;
    if (n >= 0 and n <= 15) return @intCast(n);
    return null;
}

pub fn argArray(args: ?std.json.Value, key: []const u8) ?std.json.Array {
    const v = getField(args, key) orelse return null;
    return if (v == .array) v.array else null;
}

// ---------- Respuestas JSON-RPC 2.0 ----------

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

fn sendToolResponse(out: *Io.Writer, id: std.json.Value, text: []const u8, is_error: bool) !void {
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
    if (is_error) {
        try js.objectField("isError");
        try js.write(true);
    }
    try js.endObject();
    try js.endObject();
    try out.writeAll("\n");
    try out.flush();
}

pub fn sendToolText(out: *Io.Writer, id: std.json.Value, text: []const u8) !void {
    try sendToolResponse(out, id, text, false);
}

pub fn sendToolError(out: *Io.Writer, id: std.json.Value, msg: []const u8) !void {
    try sendToolResponse(out, id, msg, true);
}

// ---------- Tests ----------

test "bracesBalanced junta JSON partido y rechaza incompleto o malformado" {
    const t = std.testing;
    try t.expect(bracesBalanced("{\"a\":1}"));
    try t.expect(bracesBalanced("{\"a\":{\"b\":[1,2]}}"));
    try t.expect(!bracesBalanced("{\"a\":{"));
    try t.expect(bracesBalanced("{\"a\":\"}\"}"));
    try t.expect(!bracesBalanced("}"));
    try t.expect(!bracesBalanced("{\"a\":1}}"));
    try t.expect(bracesBalanced("[1,2,3]"));
    try t.expect(!bracesBalanced("[1,2"));
}

test "arg helpers tolerantes" {
    const t = std.testing;
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator,
        \\{"s":"ok","b":true,"n":42,"digits":8,"arr":[1,2]}
    , .{});
    defer parsed.deinit();
    const v = parsed.value;

    try t.expect(has(v, "s"));
    try t.expect(!has(v, "missing"));
    try t.expectEqualStrings("ok", argStr(v, "s", "d"));
    try t.expectEqualStrings("d", argStr(v, "missing", "d"));
    try t.expectEqualStrings("ok", argStrOpt(v, "s").?);
    try t.expect(argStrOpt(v, "n") == null);
    try t.expectEqual(true, argBool(v, "b", false));
    try t.expectEqual(false, argBool(v, "missing", false));
    try t.expectEqual(@as(i64, 42), argInt(v, "n").?);
    try t.expectEqual(@as(u8, 8), argDigits(v).?);
    try t.expectEqual(@as(usize, 2), argArray(v, "arr").?.items.len);
}

test "sendJsonError escapa comillas y sendToolText/Error producen JSON valido" {
    const t = std.testing;
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try sendJsonError(&w, .{ .integer = 1 }, -32602, "bad \"param\"\nline2");
    try t.expect(std.mem.indexOf(u8, w.buffered(), "\\\"param\\\"\\nline2") != null);

    var buf2: [512]u8 = undefined;
    var w2: Io.Writer = .fixed(&buf2);
    try sendToolError(&w2, .{ .integer = 2 }, "fallo");
    try t.expect(std.mem.indexOf(u8, w2.buffered(), "\"isError\":true") != null);
}

