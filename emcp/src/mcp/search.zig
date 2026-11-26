//! Busqueda de herramientas disponibles en emcp (`emcp.search` / `--search`).
//! Filtra por nombre, descripcion o nombre del MCP de forma insensible a mayusculas.
//!
//! Estrategia de rendimiento:
//! - `containsIgnoreCase`: convierte `needle` a lowercase en un buffer de stack
//!   (max 128 B) y luego busca con `std.mem.indexOf` nativo (apto para SIMD).
//!   Para needles mas largos cae al comparador byte a byte (caso raro).
//! - `searchTools`: pre-alloca `min(entries.len, cap)` slots → 0 reallocs en el
//!   caso tipico donde los resultados son menores o iguales al limite.

const std = @import("std");

pub const ToolEntry = struct {
    mcp_name: []const u8,
    tool_name: []const u8,
    description: []const u8,
};

/// Convierte un char ASCII a minuscula.
inline fn toLowerAscii(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

/// Comprueba si `haystack` contiene `needle` ignorando mayusculas/minusculas ASCII.
/// Usa busqueda en una sola pasada con `indexOfScalarPos` / `indexOfAnyPos` (SIMD-friendly).
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    const c0 = toLowerAscii(needle[0]);
    const is_alpha = c0 >= 'a' and c0 <= 'z';
    const pair = [2]u8{ c0, if (is_alpha) c0 - 32 else c0 };
    const limit = haystack.len - needle.len;

    var i: usize = 0;
    while (i <= limit) {
        const pos = if (is_alpha)
            std.mem.indexOfAnyPos(u8, haystack, i, &pair)
        else
            std.mem.indexOfScalarPos(u8, haystack, i, c0);
        const start = pos orelse return false;
        if (start > limit) return false;
        if (std.ascii.eqlIgnoreCase(haystack[start .. start + needle.len], needle)) return true;
        i = start + 1;
    }
    return false;
}

/// Comprueba si todos los `tokens` aparecen en mcp_name, tool_name o description.
fn matchesTokens(entry: ToolEntry, tokens: []const []const u8) bool {
    for (tokens) |token| {
        const hit = containsIgnoreCase(entry.mcp_name, token) or
            containsIgnoreCase(entry.tool_name, token) or
            containsIgnoreCase(entry.description, token);
        if (!hit) return false;
    }
    return true;
}

/// Devuelve true si todos los tokens de `query` aparecen en mcp_name, tool_name o description.
pub fn matchesQuery(entry: ToolEntry, query: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, query, " \t\r\n");
    while (it.next()) |token| {
        const hit = containsIgnoreCase(entry.mcp_name, token) or
            containsIgnoreCase(entry.tool_name, token) or
            containsIgnoreCase(entry.description, token);
        if (!hit) return false;
    }
    return true;
}

/// Filtra `entries` por `query` y opcionalmente `mcp_filter`, respetando `limit` (por defecto 20).
/// Pre-tokeniza `query` una sola vez y pre-alloca `min(entries.len, cap)` slots.
pub fn searchTools(
    allocator: std.mem.Allocator,
    entries: []const ToolEntry,
    query: []const u8,
    mcp_filter: ?[]const u8,
    limit: usize,
) ![]ToolEntry {
    const cap = if (limit == 0) 20 else limit;
    const pre = @min(entries.len, cap);
    var out = try std.ArrayListUnmanaged(ToolEntry).initCapacity(allocator, pre);
    errdefer out.deinit(allocator);

    // Pre-tokeniza en stack (hasta 16 tokens; si hay mas, usa matchesQuery).
    var tok_buf: [16][]const u8 = undefined;
    var tok_len: usize = 0;
    var overflow = false;
    var it = std.mem.tokenizeAny(u8, query, " \t\r\n");
    while (it.next()) |token| {
        if (tok_len < tok_buf.len) {
            tok_buf[tok_len] = token;
            tok_len += 1;
        } else {
            overflow = true;
            break;
        }
    }

    for (entries) |entry| {
        if (mcp_filter) |f| {
            if (f.len > 0 and !std.ascii.eqlIgnoreCase(entry.mcp_name, f)) continue;
        }
        const ok = if (overflow) matchesQuery(entry, query) else matchesTokens(entry, tok_buf[0..tok_len]);
        if (ok) {
            try out.append(allocator, entry);
            if (out.items.len >= cap) break;
        }
    }
    return out.toOwnedSlice(allocator);
}

test "emcp.search: filtra por nombre, descripcion, multi-token y mcp" {
    const t = std.testing;
    const entries = [_]ToolEntry{
        .{ .mcp_name = "mcp-time", .tool_name = "time", .description = "Hora y fecha en cualquier zona horaria" },
        .{ .mcp_name = "mcp-math", .tool_name = "calc", .description = "Calculo matematico avanzado" },
        .{ .mcp_name = "mcp-ml", .tool_name = "sindy", .description = "Descubrimiento simbolico desde CSV" },
        .{ .mcp_name = "mcp-runner", .tool_name = "run_code", .description = "Compila y ejecuta codigo Rust/Zig/C/Python/TS/JS" },
    };

    // busqueda multi-token insensible a mayusculas
    const r1 = try searchTools(t.allocator, &entries, "ZONA horaria", null, 10);
    defer t.allocator.free(r1);
    try t.expectEqual(@as(usize, 1), r1.len);
    try t.expectEqualStrings("time", r1[0].tool_name);

    // filtro por mcp + query
    const r2 = try searchTools(t.allocator, &entries, "codigo", "mcp-runner", 10);
    defer t.allocator.free(r2);
    try t.expectEqual(@as(usize, 1), r2.len);
    try t.expectEqualStrings("run_code", r2[0].tool_name);

    // limit: query vacia devuelve todos hasta el cap
    const r3 = try searchTools(t.allocator, &entries, "", null, 2);
    defer t.allocator.free(r3);
    try t.expectEqual(@as(usize, 2), r3.len);

    // sin resultados
    const r4 = try searchTools(t.allocator, &entries, "blender", null, 10);
    defer t.allocator.free(r4);
    try t.expectEqual(@as(usize, 0), r4.len);

    // busqueda por nombre de tool
    const r5 = try searchTools(t.allocator, &entries, "sindy", null, 10);
    defer t.allocator.free(r5);
    try t.expectEqual(@as(usize, 1), r5.len);
    try t.expectEqualStrings("mcp-ml", r5[0].mcp_name);

    // filtro mcp con casing mixto (insensible a mayusculas)
    const r6 = try searchTools(t.allocator, &entries, "", "MCP-TIME", 10);
    defer t.allocator.free(r6);
    try t.expectEqual(@as(usize, 1), r6.len);
    try t.expectEqualStrings("mcp-time", r6[0].mcp_name);

    // busqueda por nombre de mcp en query
    const r7 = try searchTools(t.allocator, &entries, "MCP-MATH", null, 10);
    defer t.allocator.free(r7);
    try t.expectEqual(@as(usize, 1), r7.len);
    try t.expectEqualStrings("calc", r7[0].tool_name);

    // limit=0 usa el cap por defecto (20), retorna todos
    const r8 = try searchTools(t.allocator, &entries, "", null, 0);
    defer t.allocator.free(r8);
    try t.expectEqual(@as(usize, 4), r8.len);
}
