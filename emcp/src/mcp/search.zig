//! Busqueda de herramientas disponibles en emcp (`emcp.search` / `--search`).
//! Filtra por nombre, descripcion o nombre del MCP de forma insensible a mayusculas.

const std = @import("std");

pub const ToolEntry = struct {
    mcp_name: []const u8,
    tool_name: []const u8,
    description: []const u8,
};

/// Comprueba si `haystack` contiene `needle` ignorando mayusculas/minusculas ASCII.
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
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
pub fn searchTools(
    allocator: std.mem.Allocator,
    entries: []const ToolEntry,
    query: []const u8,
    mcp_filter: ?[]const u8,
    limit: usize,
) ![]ToolEntry {
    const cap = if (limit == 0) 20 else limit;
    var out = std.ArrayList(ToolEntry).empty;
    errdefer out.deinit(allocator);

    for (entries) |entry| {
        if (mcp_filter) |f| {
            if (f.len > 0 and !std.ascii.eqlIgnoreCase(entry.mcp_name, f)) continue;
        }
        if (matchesQuery(entry, query)) {
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
}

