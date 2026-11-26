//! Fuente UNICA de identidad y herramientas meta de emcp (orquestador).
//!
//! OJO: `core/registro.zig` es OTRA cosa: es el *parser* del `registro.json`
//! de terceros (formato firmado). Este archivo es la identidad del propio
//! emcp: version, descripcion y las 3 meta-tools de registro.
//!
//! Lo consumen `--registro` (manifiesto), `initialize` (serverInfo) y
//! `tools/list` (schemas de las meta-tools). Actualizar = editar SOLO aqui.

// ---------- Identidad ----------
pub const NOMBRE = "emcp";
pub const SERVIDOR = "emcp";
pub const VERSION = "3.0.0";
pub const DESCRIPCION = "Orquestador MCP: expone las MCPs registradas (mcps/index.json).";
pub const PROTOCOLO = "2024-11-05";

// ---------- Meta-herramientas (nombre + schema para `tools/list`) ----------
// OJO: las DESCRIPCIONES son cortas a proposito. En Code Mode el catalogo
// lista primero las firmas mas baratas (coste = longitud/4) y corta al agotar
// el presupuesto inline; ademas, la firma incluye el `/** desc */` de cada
// parametro, asi que un schema verboso infla la linea. Por eso `desregistrar`
// deja `nombre` sin descripcion: el nombre del parametro ya lo dice.
pub const REGISTRAR = "registrar";
pub const DESREGISTRAR = "desregistrar";
pub const REGISTRADOS = "registrados";
pub const SEARCH = "emcp.search";

pub const JSON_REGISTRAR =
    "{\"name\":\"registrar\",\"description\":\"Registra o actualiza un MCP (firma Schnorr obligatoria).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"origen\":{\"type\":\"string\",\"description\":\"Ruta a un binario o URL https:// del binario MCP.\"},\"nombre\":{\"type\":\"string\",\"description\":\"Nombre corto (^[a-z0-9][a-z0-9-]{0,30}$); si se omite se toma del registro.json.\"},\"tipo\":{\"type\":\"string\",\"enum\":[\"auto\",\"mcp\"],\"description\":\"auto (por defecto) o mcp.\"},\"sha256\":{\"type\":\"string\",\"description\":\"Hash SHA-256 esperado del binario (hex). Ademas debe coincidir con el del registro.json.\"},\"forzar\":{\"type\":\"boolean\",\"description\":\"Compatibilidad: al registrar un nombre existente ya se reemplaza solo.\"}},\"required\":[\"origen\"]}}";

pub const JSON_DESREGISTRAR =
    "{\"name\":\"desregistrar\",\"description\":\"Quita un MCP registrado y su carpeta.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"nombre\":{\"type\":\"string\"}},\"required\":[\"nombre\"]}}";

pub const JSON_REGISTRADOS =
    "{\"name\":\"registrados\",\"description\":\"Lista los MCPs registrados y su estado (hash, firma, herramientas).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}}";

pub const JSON_SEARCH =
    "{\"name\":\"emcp.search\",\"description\":\"Busca herramientas disponibles por nombre, descripcion o MCP.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Texto o palabras clave a buscar (nombre o descripcion).\"},\"mcp\":{\"type\":\"string\",\"description\":\"Filtrar por nombre de MCP registrado.\"},\"limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100,\"default\":20}},\"required\":[\"query\"]}}";

pub const Herramienta = struct {
    nombre: []const u8,
    json: []const u8,
};

/// Orden canonico de `tools/list` y del manifiesto.
pub const HERRAMIENTAS = [_]Herramienta{
    .{ .nombre = REGISTRAR, .json = JSON_REGISTRAR },
    .{ .nombre = DESREGISTRAR, .json = JSON_DESREGISTRAR },
    .{ .nombre = REGISTRADOS, .json = JSON_REGISTRADOS },
    .{ .nombre = SEARCH, .json = JSON_SEARCH },
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
    break :blk s ++ "]}";
};

test "manifiesto y comandos derivados" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"nombre\":\"emcp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"registrar\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"emcp.search\"") != null);
    try std.testing.expectEqual(HERRAMIENTAS.len, COMANDOS.len);
}
