//! Fuente UNICA de identidad y herramientas de mcp-time.
//!
//! Lo consumen:
//!   * `--registro` (el manifiesto del que sale el sha256 + la firma),
//!   * `tools/list` (los schemas JSON de cada herramienta),
//!   * la ayuda (`ayuda.zig`) y los mensajes "usa la herramienta ...".
//!
//! Actualizar version, descripcion o herramientas = editar SOLO este archivo;
//! el manifiesto y la lista de `comandos` se derivan en comptime.

// ---------- Identidad ----------
pub const NOMBRE = "mcp-time"; // nombre firmado (manifiesto)
pub const SERVIDOR = "mcp-time"; // serverInfo.name
pub const VERSION = "3.1.0";
pub const DESCRIPCION = "Hora y fecha en espanol (32 zonas, DST, laborables).";
pub const PROTOCOLO = "2024-11-05";

// ---------- Herramientas (nombre + schema para `tools/list`) ----------
pub const TIME = "time";
pub const FECHA = "fecha";
pub const DIF = "dif";
pub const LABORABLE = "laborable";
pub const DETALLE = "detalle";
pub const EPOCA = "epoca";
pub const FORMATO = "formato";
pub const AYUDA = "time_help";
pub const LIMA = "get_lima_time";

pub const JSON_TIME =
    "{\"name\":\"time\",\"description\":\"Hora y fecha exactas en cualquier zona horaria (con horario de verano). Parametros: zone (Lima, Tokyo, UTC-5, America/New_York), format (all|iso|human|unix), patron (formato strftime opcional, ej. '%A %d de %B').\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"zone\":{\"type\":\"string\",\"default\":\"Lima\",\"description\":\"Ciudad, IANA o offset UTC. Por defecto Lima.\"},\"format\":{\"type\":\"string\",\"enum\":[\"all\",\"iso\",\"human\",\"unix\"],\"default\":\"all\"},\"patron\":{\"type\":\"string\",\"description\":\"Formato personalizado tipo strftime: %Y %m %d %H %M %S %A %B %j %V %z ...\"}},\"examples\":[{\"zone\":\"Tokyo\",\"format\":\"iso\"},{\"zone\":\"UTC-5\"}],\"additionalProperties\":false}}";

pub const JSON_FECHA =
    "{\"name\":\"fecha\",\"description\":\"Convierte y desplaza fechas en español (años 1-9999). Acepta ISO, D/M/A, 'D de mes de A', unix, eventos, y lenguaje natural ('próximo viernes', 'en 3 semanas', 'hace 2 meses', 'último lunes de mayo', 'fin de mes'). Parametros: fecha (def. ahora), suma (ej. '-100 dias', 'P1Y2M3D'), zone, format, patron.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"fecha\":{\"type\":\"string\",\"default\":\"ahora\",\"description\":\"Base: ahora|ayer|ISO|D/M/A|D de mes de A|unix|evento|lenguaje natural\"},\"suma\":{\"type\":\"string\",\"description\":\"Desplazamiento español o ISO-8601 (P1Y2M3D)\"},\"zone\":{\"type\":\"string\",\"default\":\"Lima\"},\"format\":{\"type\":\"string\",\"enum\":[\"all\",\"iso\",\"human\",\"unix\"],\"default\":\"all\"},\"patron\":{\"type\":\"string\"}},\"examples\":[{\"fecha\":\"próximo viernes\",\"patron\":\"%A %d/%m/%Y\"},{\"fecha\":\"2026-01-01\",\"suma\":\"-100 dias\"}],\"additionalProperties\":false}}";

pub const JSON_DIF =
    "{\"name\":\"dif\",\"description\":\"Diferencia entre dos fechas (pasado/presente/futuro). Parametros: desde (obligatorio), hasta (def. ahora), en (segundos|minutos|horas|dias|semanas, def. dias), zone.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"desde\":{\"type\":\"string\"},\"hasta\":{\"type\":\"string\",\"default\":\"ahora\"},\"en\":{\"type\":\"string\",\"enum\":[\"segundos\",\"minutos\",\"horas\",\"dias\",\"semanas\"],\"default\":\"dias\"},\"zone\":{\"type\":\"string\",\"default\":\"Lima\"}},\"examples\":[{\"desde\":\"2026-01-01\",\"hasta\":\"2026-02-01\",\"en\":\"dias\"}],\"required\":[\"desde\"],\"additionalProperties\":false}}";

pub const JSON_LABORABLE =
    "{\"name\":\"laborable\",\"description\":\"Dias laborables (L-V menos feriados). modo=contar (desde,hasta), modo=sumar (fecha,dias) o modo=es (fecha). Parametros extra: pais (pe|us|mx|es|cl|ar), feriados (lista de 'MM-DD' anuales o fechas exactas), zone.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"modo\":{\"type\":\"string\",\"enum\":[\"contar\",\"sumar\",\"es\"]},\"desde\":{\"type\":\"string\"},\"hasta\":{\"type\":\"string\",\"default\":\"ahora\"},\"fecha\":{\"type\":\"string\",\"default\":\"ahora\"},\"dias\":{\"type\":\"integer\",\"description\":\"Entero; negativo retrocede (modo=sumar)\"},\"pais\":{\"type\":\"string\",\"enum\":[\"pe\",\"us\",\"mx\",\"es\",\"cl\",\"ar\"]},\"feriados\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"zone\":{\"type\":\"string\",\"default\":\"Lima\"}},\"examples\":[{\"modo\":\"contar\",\"desde\":\"2026-01-01\",\"hasta\":\"2026-02-01\",\"pais\":\"pe\"},{\"modo\":\"sumar\",\"fecha\":\"2026-01-01\",\"dias\":5}],\"additionalProperties\":false}}";

pub const JSON_DETALLE =
    "{\"name\":\"detalle\",\"description\":\"Desglose de una fecha: día de la semana, día del año, semana ISO-8601, trimestre, mes, días del mes, ¿bisiesto?, ¿fin de semana?. Parametros: fecha (def. ahora), zone.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"fecha\":{\"type\":\"string\",\"default\":\"ahora\"},\"zone\":{\"type\":\"string\",\"default\":\"Lima\"}},\"examples\":[{\"fecha\":\"2026-10-16\"}],\"additionalProperties\":false}}";

pub const JSON_EPOCA =
    "{\"name\":\"epoca\",\"description\":\"Estandares de una fecha: Unix (s/ms/us/ns), Julian Day, MJD, serial de Excel, RFC3339, ISO ordinal (YYYY-DDD) y semana ISO. Parametros: fecha (def. ahora), zone.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"fecha\":{\"type\":\"string\",\"default\":\"ahora\"},\"zone\":{\"type\":\"string\",\"default\":\"Lima\"}},\"examples\":[{\"fecha\":\"2026-10-16\"}],\"additionalProperties\":false}}";

pub const JSON_FORMATO =
    "{\"name\":\"formato\",\"description\":\"Formatea una fecha con un patron strftime en español. Specs: %Y %y %m %d %e %H %M %S %j %V %G %u %w %A %a %B %b %p %z %s %q %F %T %% . Parametros: patron (obligatorio), fecha (def. ahora), zone.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"patron\":{\"type\":\"string\"},\"fecha\":{\"type\":\"string\",\"default\":\"ahora\"},\"zone\":{\"type\":\"string\",\"default\":\"Lima\"}},\"examples\":[{\"patron\":\"%A %d de %B\",\"fecha\":\"2026-10-16\"}],\"required\":[\"patron\"],\"additionalProperties\":false}}";

pub const JSON_AYUDA =
    "{\"name\":\"time_help\",\"description\":\"Ayuda en Markdown. Parametro topic: all|time|fecha|dif|laborable|detalle|epoca|formato|zones.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"topic\":{\"type\":\"string\",\"enum\":[\"all\",\"time\",\"fecha\",\"dif\",\"laborable\",\"detalle\",\"epoca\",\"formato\",\"zones\"]}},\"examples\":[{\"topic\":\"laborable\"}],\"additionalProperties\":false}}";

pub const JSON_LIMA =
    "{\"name\":\"get_lima_time\",\"description\":\"Alias de time con zone=Lima (compatibilidad v1). Parametros: format, patron.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"format\":{\"type\":\"string\",\"enum\":[\"all\",\"iso\",\"human\",\"unix\"],\"default\":\"all\"},\"patron\":{\"type\":\"string\"}},\"examples\":[{\"format\":\"human\"}],\"additionalProperties\":false}}";

pub const Herramienta = struct {
    nombre: []const u8,
    json: []const u8,
};

/// Orden canonico de `tools/list` y del manifiesto.
pub const HERRAMIENTAS = [_]Herramienta{
    .{ .nombre = TIME, .json = JSON_TIME },
    .{ .nombre = FECHA, .json = JSON_FECHA },
    .{ .nombre = DIF, .json = JSON_DIF },
    .{ .nombre = LABORABLE, .json = JSON_LABORABLE },
    .{ .nombre = DETALLE, .json = JSON_DETALLE },
    .{ .nombre = EPOCA, .json = JSON_EPOCA },
    .{ .nombre = FORMATO, .json = JSON_FORMATO },
    .{ .nombre = AYUDA, .json = JSON_AYUDA },
    .{ .nombre = LIMA, .json = JSON_LIMA },
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
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"nombre\":\"mcp-time\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"comandos\":[\"time\",\"fecha\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"time_help\"") != null);
    try std.testing.expectEqual(HERRAMIENTAS.len, COMANDOS.len);
}
