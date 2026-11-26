//! Fuente UNICA de identidad y herramientas de mcp-runner.
//!
//! Lo consumen `--registro` (manifiesto firmado), `tools/list` (schemas) y la
//! ayuda. Actualizar version, descripcion o herramientas = editar SOLO aqui;
//! `comandos` y el manifiesto se derivan en comptime.

// ---------- Identidad ----------
pub const NOMBRE = "mcp-runner";
pub const SERVIDOR = "mcp-runner";
pub const VERSION = "0.1.0";
pub const DESCRIPCION = "Runner de codigo multiplenguaje en disco RAM.";
pub const PROTOCOLO = "2024-11-05";

// ---------- Herramientas (nombre + schema para `tools/list`) ----------
pub const RUN_CODE = "run_code";
pub const AYUDA = "runner_help";

pub const JSON_RUN_CODE =
    "{\"name\":\"run_code\",\"description\":\"Compila y ejecuta codigo Rust/Zig/C/C++/Python/TS/JS en disco RAM. Params: code, file, lang, ramdisk, max_bytes (0=todos), timeout_ms.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\"},\"file\":{\"type\":\"string\"},\"lang\":{\"type\":\"string\",\"enum\":[\"rust\",\"zig\",\"c\",\"cpp\",\"python\",\"ts\",\"js\"],\"default\":\"rust\"},\"ramdisk\":{\"type\":\"string\",\"default\":\"R:\\\\runner\"},\"max_bytes\":{\"type\":\"integer\",\"default\":0},\"timeout_ms\":{\"type\":\"integer\",\"default\":0}},\"examples\":[{\"lang\":\"python\",\"code\":\"print(2+2)\"},{\"lang\":\"zig\",\"file\":\"C:/proj/main.zig\",\"timeout_ms\":30000}],\"additionalProperties\":false}}";

pub const JSON_AYUDA =
    "{\"name\":\"runner_help\",\"description\":\"Ayuda en Markdown. Parametro topic: all|run_code.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"topic\":{\"type\":\"string\",\"enum\":[\"all\",\"run_code\"]}},\"examples\":[{\"topic\":\"run_code\"}],\"additionalProperties\":false}}";

pub const Herramienta = struct {
    nombre: []const u8,
    json: []const u8,
};

/// Orden canonico de `tools/list` y del manifiesto.
pub const HERRAMIENTAS = [_]Herramienta{
    .{ .nombre = RUN_CODE, .json = JSON_RUN_CODE },
    .{ .nombre = AYUDA, .json = JSON_AYUDA },
};

/// Nombres de herramienta derivados (manifiesto). Sin duplicacion manual.
pub const COMANDOS = blk: {
    var out: [HERRAMIENTAS.len][]const u8 = undefined;
    for (HERRAMIENTAS, 0..) |h, i| out[i] = h.nombre;
    break :blk out;
};

/// Manifiesto de `--registro`, generado en comptime desde esta fuente unica.
pub const MANIFIESTO = blk: {
    var s: []const u8 = "{\"registro\":1,\"nombre\":\"" ++ NOMBRE ++
        "\",\"version\":\"" ++ VERSION ++ "\",\"descripcion\":\"" ++ DESCRIPCION ++
        "\",\"tipo\":\"mcp\",\"protocolo\":\"" ++ PROTOCOLO ++ "\",\"comandos\":[";
    for (COMANDOS, 0..) |c, i| {
        if (i > 0) s = s ++ ",";
        s = s ++ "\"" ++ c ++ "\"";
    }
    s = s ++ "],\"ayuda\":\"" ++ NOMBRE ++ " --help [tema]\",\"herramientas\":[";
    for (HERRAMIENTAS, 0..) |h, i| {
        if (i > 0) s = s ++ ",";
        s = s ++ h.json;
    }
    break :blk s ++ "]}";
};

test "manifiesto y comandos derivados" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"nombre\":\"mcp-runner\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"runner_help\"") != null);
    try std.testing.expectEqual(HERRAMIENTAS.len, COMANDOS.len);
}
