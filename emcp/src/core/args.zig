// Lectura tolerante de `arguments` en `tools/call` (JSON-RPC).
//
// Los getters devuelven null si la clave falta o si el tipo no coincide, para
// que una entrada inesperada nunca cause un panic. La validacion funcional la
// hace cada MCP: emcp ya no conoce el esquema de ninguna herramienta
// (los schemas y sus argumentos llegan al registrar, desde `tools/list`).

const std = @import("std");
const Value = std.json.Value;

/// Valor de una clave (null si ausente, o si `args` no es objeto).
pub fn get(args: ?Value, key: []const u8) ?Value {
    const a = args orelse return null;
    if (a != .object) return null;
    const v = a.object.get(key) orelse return null;
    if (v == .null) return null;
    return v;
}

pub fn str(args: ?Value, key: []const u8) ?[]const u8 {
    const v = get(args, key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

pub fn integer(args: ?Value, key: []const u8) ?i64 {
    const v = get(args, key) orelse return null;
    if (v != .integer) return null;
    return v.integer;
}

pub fn boolean(args: ?Value, key: []const u8) ?bool {
    const v = get(args, key) orelse return null;
    if (v != .bool) return null;
    return v.bool;
}

pub fn array(args: ?Value, key: []const u8) ?[]const Value {
    const v = get(args, key) orelse return null;
    if (v != .array) return null;
    return v.array.items;
}

pub fn strOr(args: ?Value, key: []const u8, dflt: []const u8) []const u8 {
    return str(args, key) orelse dflt;
}

test "getters tolerantes" {
    var parsed = try std.json.parseFromSlice(Value, std.testing.allocator,
        \\{"s":"x","i":3,"b":true,"arr":["a","b"],"n":2.5,"nul":null}
    , .{});
    defer parsed.deinit();
    const v = parsed.value;
    try std.testing.expectEqualStrings("x", str(v, "s").?);
    try std.testing.expectEqual(@as(i64, 3), integer(v, "i").?);
    try std.testing.expectEqual(true, boolean(v, "b").?);
    try std.testing.expectEqual(@as(usize, 2), array(v, "arr").?.len);
    try std.testing.expect(str(v, "i") == null);
    try std.testing.expect(get(v, "nul") == null);
    try std.testing.expectEqualStrings("d", strOr(v, "falta", "d"));
}
