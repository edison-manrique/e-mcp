// Zonas horarias: tabla + resolucion tolerante + offsets con DST (reglas).
// Puro (sin IO). Acepta ciudad, nombre IANA o offset UTC generico.
//
// Los offsets con nombre aplican REGLAS de horario de verano (ver dst.zig) para
// las zonas que lo observan; fuera de los años modelados se usa hora estandar.
// Los offsets genericos (UTC±N) son siempre exactos (nunca tienen DST).

const std = @import("std");
const civil = @import("civil.zig");
const dst = @import("dst.zig");

const SIN = [_]dst.Regla{};

// Regla de Mexico (1996-2021): 1er domingo de abril -> ultimo domingo de octubre.
// Desde 2022 Mexico abolitio el DST. Aqui solo se modela el periodo con DST.
const MEX_RULES = [_]dst.Regla{.{
    .from_year = 1996,
    .to_year = 2021,
    .delta_min = 60,
    .start = .{ .month = 4, .weekday = 0, .nth = .first, .sec_of_day = 2 * 3600, .ref = .local_std },
    .end = .{ .month = 10, .weekday = 0, .nth = .last, .sec_of_day = 2 * 3600, .ref = .local_std },
}};

const Zona = struct {
    id: []const u8,
    city: []const u8,
    std_min: i16, // minutos al este de UTC en hora estandar
    rules: []const dst.Regla,
    aliases: []const []const u8,
};

const ZONAS = [_]Zona{
    .{ .id = "UTC", .city = "UTC", .std_min = 0, .rules = &SIN, .aliases = &.{ "utc", "gmt", "z", "uct", "universal", "london winter" } },
    .{ .id = "America/Lima", .city = "Lima", .std_min = -300, .rules = &SIN, .aliases = &.{ "lima", "america lima", "peru", "pe" } },
    .{ .id = "America/Bogota", .city = "Bogota", .std_min = -300, .rules = &SIN, .aliases = &.{ "bogota", "america bogota", "colombia" } },
    .{ .id = "America/Mexico_City", .city = "Ciudad de Mexico", .std_min = -360, .rules = &MEX_RULES, .aliases = &.{ "mexico city", "america mexico city", "mexico", "cdmx", "ciudad de mexico" } },
    .{ .id = "America/New_York", .city = "Nueva York", .std_min = -300, .rules = dst.usRules(), .aliases = &.{ "new york", "america new york", "nyc", "ny", "este eeuu", "eastern" } },
    .{ .id = "America/Chicago", .city = "Chicago", .std_min = -360, .rules = dst.usRules(), .aliases = &.{ "chicago", "america chicago", "central eeuu" } },
    .{ .id = "America/Denver", .city = "Denver", .std_min = -420, .rules = dst.usRules(), .aliases = &.{ "denver", "america denver", "mountain" } },
    .{ .id = "America/Los_Angeles", .city = "Los Angeles", .std_min = -480, .rules = dst.usRules(), .aliases = &.{ "los angeles", "america los angeles", "la", "california", "pacific", "pacifico eeuu" } },
    .{ .id = "America/Sao_Paulo", .city = "Sao Paulo", .std_min = -180, .rules = &SIN, .aliases = &.{ "sao paulo", "america sao paulo", "brasil", "brazil" } },
    .{ .id = "America/Buenos_Aires", .city = "Buenos Aires", .std_min = -180, .rules = &SIN, .aliases = &.{ "buenos aires", "america buenos aires", "argentina" } },
    .{ .id = "America/Santiago", .city = "Santiago", .std_min = -240, .rules = dst.clRules(), .aliases = &.{ "santiago", "america santiago", "chile" } },
    .{ .id = "America/Caracas", .city = "Caracas", .std_min = -240, .rules = &SIN, .aliases = &.{ "caracas", "america caracas", "venezuela" } },
    .{ .id = "Pacific/Honolulu", .city = "Honolulu", .std_min = -600, .rules = &SIN, .aliases = &.{ "honolulu", "pacific honolulu", "hawaii" } },
    .{ .id = "Europe/London", .city = "Londres", .std_min = 0, .rules = dst.euRules(), .aliases = &.{ "london", "europe london", "londres", "uk", "reino unido", "bst winter" } },
    .{ .id = "Europe/Madrid", .city = "Madrid", .std_min = 60, .rules = dst.euRules(), .aliases = &.{ "madrid", "europe madrid", "espana", "españa" } },
    .{ .id = "Europe/Paris", .city = "Paris", .std_min = 60, .rules = dst.euRules(), .aliases = &.{ "paris", "europe paris", "francia" } },
    .{ .id = "Europe/Berlin", .city = "Berlin", .std_min = 60, .rules = dst.euRules(), .aliases = &.{ "berlin", "europe berlin", "alemania" } },
    .{ .id = "Europe/Moscow", .city = "Moscu", .std_min = 180, .rules = &SIN, .aliases = &.{ "moscow", "europe moscow", "moscu", "rusia" } },
    .{ .id = "Africa/Cairo", .city = "El Cairo", .std_min = 120, .rules = dst.egRules(), .aliases = &.{ "cairo", "africa cairo", "el cairo", "egipto" } },
    .{ .id = "Africa/Lagos", .city = "Lagos", .std_min = 60, .rules = &SIN, .aliases = &.{ "lagos", "africa lagos", "nigeria" } },
    .{ .id = "Africa/Johannesburg", .city = "Johannesburgo", .std_min = 120, .rules = &SIN, .aliases = &.{ "johannesburg", "africa johannesburg", "johannesburgo", "sudafrica" } },
    .{ .id = "Asia/Dubai", .city = "Dubai", .std_min = 240, .rules = &SIN, .aliases = &.{ "dubai", "asia dubai", "emiratos" } },
    .{ .id = "Asia/Karachi", .city = "Karachi", .std_min = 300, .rules = &SIN, .aliases = &.{ "karachi", "asia karachi", "pakistan" } },
    .{ .id = "Asia/Kolkata", .city = "Nueva Delhi", .std_min = 330, .rules = &SIN, .aliases = &.{ "kolkata", "asia kolkata", "delhi", "nueva delhi", "india", "mumbai", "bombay" } },
    .{ .id = "Asia/Dhaka", .city = "Daca", .std_min = 360, .rules = &SIN, .aliases = &.{ "dhaka", "asia dhaka", "daca", "bangladesh" } },
    .{ .id = "Asia/Bangkok", .city = "Bangkok", .std_min = 420, .rules = &SIN, .aliases = &.{ "bangkok", "asia bangkok", "tailandia" } },
    .{ .id = "Asia/Singapore", .city = "Singapur", .std_min = 480, .rules = &SIN, .aliases = &.{ "singapore", "asia singapore", "singapur" } },
    .{ .id = "Asia/Shanghai", .city = "Shanghai", .std_min = 480, .rules = &SIN, .aliases = &.{ "shanghai", "asia shanghai", "beijing", "china", "hong kong", "asia hong kong" } },
    .{ .id = "Asia/Tokyo", .city = "Tokio", .std_min = 540, .rules = &SIN, .aliases = &.{ "tokyo", "asia tokyo", "tokio", "japon", "japan" } },
    .{ .id = "Asia/Seoul", .city = "Seul", .std_min = 540, .rules = &SIN, .aliases = &.{ "seoul", "asia seoul", "seul", "corea del sur" } },
    .{ .id = "Australia/Sydney", .city = "Sidney", .std_min = 600, .rules = dst.auRules(), .aliases = &.{ "sydney", "australia sydney", "sidney", "australia" } },
    .{ .id = "Pacific/Auckland", .city = "Auckland", .std_min = 720, .rules = dst.nzRules(), .aliases = &.{ "auckland", "pacific auckland", "nueva zelanda", "new zealand" } },
};

/// Zona resuelta (valor). `generic` = vino de un offset UTC±N (sin DST).
pub const Z = struct {
    id: []const u8,
    city: []const u8,
    std_min: i16,
    rules: []const dst.Regla = &SIN,
    generic: bool = false,

    /// Offset efectivo (min al este) en el instante `ms` (aplica DST).
    pub fn offsetAt(self: Z, ms: i64) i16 {
        return dst.offsetAt(self.rules, self.std_min, ms);
    }

    pub fn msToCivil(self: Z, ms: i64) civil.Parts {
        return civil.msToCivil(ms, self.offsetAt(ms));
    }

    pub fn weekday(self: Z, ms: i64) u8 {
        const sec: i64 = @divFloor(ms, 1000) + @as(i64, self.offsetAt(ms)) * 60;
        return @intCast(@mod(@divFloor(sec, 86400) + 4, 7));
    }

    /// Hora de pared local -> ms Unix, resolviendo el DST (dos pasadas).
    /// En la hora "inexistente" del salto adelante devuelve la interpretacion
    /// con el offset resultante; en la "ambigua" del salto atras, la primera.
    pub fn wallToMs(self: Z, y: i64, mo: u8, d: u8, h: u8, mi: u8, s: u8) !i64 {
        const g1 = try civil.wallToMs(y, mo, d, h, mi, s, self.std_min);
        const o1 = self.offsetAt(g1);
        const c1 = try civil.wallToMs(y, mo, d, h, mi, s, o1);
        if (self.offsetAt(c1) == o1) return c1;
        const o2 = self.offsetAt(c1);
        return civil.wallToMs(y, mo, d, h, mi, s, o2);
    }
};

// Normaliza: minusculas, '_' '/' '-' '.' -> ' ', recorta espacios.
// OJO: para offsets UTC se usa normalizeLight (preserva signo).
pub fn normalizeZone(input: []const u8, buf: []u8) []u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < input.len and (input[i] == ' ' or input[i] == '\t')) : (i += 1) {}
    var pending_space = false;
    while (i < input.len and n + 1 < buf.len) : (i += 1) {
        const c = input[i];
        if (c == ' ' or c == '\t' or c == '_' or c == '/' or c == '-' or c == '.') {
            pending_space = true;
            continue;
        }
        if (pending_space and n > 0) {
            buf[n] = ' ';
            n += 1;
        }
        pending_space = false;
        buf[n] = if (c >= 'A' and c <= 'Z') c + 32 else c;
        n += 1;
    }
    return buf[0..n];
}

// Minusculas + trim, preserva +/-/: para offsets.
fn normalizeLight(input: []const u8, buf: []u8) []u8 {
    var s = std.mem.trim(u8, input, " \t");
    if (s.len >= buf.len) s = s[0 .. buf.len - 1];
    for (s, 0..) |c, i| buf[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    return buf[0..s.len];
}

// Acepta "utc", "utc+2", "gmt-5", "+5:30", "-3", "utc-03:30", "z".
fn parseUtcOffset(norm: []const u8) ?i16 {
    var s = norm;
    if (std.mem.eql(u8, s, "utc") or std.mem.eql(u8, s, "gmt") or std.mem.eql(u8, s, "z")) return 0;
    if (std.mem.startsWith(u8, s, "utc ")) s = s[4..];
    if (std.mem.startsWith(u8, s, "gmt ")) s = s[4..];
    if (std.mem.startsWith(u8, s, "utc")) s = s[3..];
    if (std.mem.startsWith(u8, s, "gmt")) s = s[3..];
    s = std.mem.trim(u8, s, " ");
    if (s.len < 2) return null;
    const sign: i16 = switch (s[0]) {
        '+' => 1,
        '-' => -1,
        else => return null,
    };
    const rest = s[1..];
    var h: i16 = 0;
    var m: i16 = 0;
    if (std.mem.indexOfScalar(u8, rest, ':')) |ci| {
        h = std.fmt.parseInt(i16, rest[0..ci], 10) catch return null;
        m = std.fmt.parseInt(i16, rest[ci + 1 ..], 10) catch return null;
    } else {
        h = std.fmt.parseInt(i16, rest, 10) catch return null;
    }
    if (h < 0 or h > 14 or m < 0 or m > 59) return null;
    if (!(m == 0 or m == 15 or m == 30 or m == 45)) return null;
    return sign * (h * 60 + m);
}

pub fn resolveZone(input: []const u8) ?Z {
    // 1. Offsets UTC primero (preserva +/-/:).
    {
        var lbuf: [64]u8 = undefined;
        const ln = normalizeLight(input, &lbuf);
        if (ln.len > 0) {
            if (parseUtcOffset(ln)) |off| {
                return .{ .id = "UTC", .city = "UTC", .std_min = off, .rules = &SIN, .generic = true };
            }
        }
    }
    // 2. Ciudades/IANA con normalizado completo.
    var nbuf: [64]u8 = undefined;
    const norm = normalizeZone(input, &nbuf);
    if (norm.len == 0) return null;
    for (ZONAS) |z| {
        var abuf: [64]u8 = undefined;
        const zid = normalizeZone(z.id, &abuf);
        if (std.mem.eql(u8, norm, zid)) return .{ .id = z.id, .city = z.city, .std_min = z.std_min, .rules = z.rules, .generic = false };
        for (z.aliases) |a| {
            if (std.mem.eql(u8, norm, a)) return .{ .id = z.id, .city = z.city, .std_min = z.std_min, .rules = z.rules, .generic = false };
        }
    }
    return null;
}

/// Lista de ids de zona (para help/errores).
pub fn ids(buf: [][]const u8) [][]const u8 {
    var n: usize = 0;
    for (ZONAS) |z| {
        if (n >= buf.len) break;
        buf[n] = z.id;
        n += 1;
    }
    return buf[0..n];
}

// ---------- Tests ----------

test "zona: resolver tolerante" {
    try std.testing.expect(resolveZone("Lima") != null);
    try std.testing.expect(resolveZone("new-york").?.std_min == -300);
    try std.testing.expect(resolveZone("America/New_York").?.id.len == 16);
    try std.testing.expect(resolveZone("tokyo").?.std_min == 540);
    try std.testing.expect(resolveZone("UTC+5:30").?.std_min == 330);
    try std.testing.expect(resolveZone("+9").?.std_min == 540);
    try std.testing.expect(resolveZone("-3:30").?.std_min == -210);
    try std.testing.expect(resolveZone("noexiste") == null);
    // El offset generico es exacto y sin DST.
    const g = resolveZone("UTC+2").?;
    try std.testing.expect(g.generic and g.offsetAt(0) == 120);
}

test "zona: DST aplica y normaliza hora de pared" {
    const ny = resolveZone("New York").?;
    // 15 de julio 2026 12:00 local (EDT, -04:00) -> 16:00 UTC.
    const ms = try ny.wallToMs(2026, 7, 15, 12, 0, 0);
    try std.testing.expectEqual(@as(i16, -240), ny.offsetAt(ms));
    const p = ny.msToCivil(ms);
    try std.testing.expect(p.h == 12 and p.mo == 7 and p.d == 15);
    // 15 de enero 2026 12:00 local (EST, -05:00) -> ida y vuelta estable.
    const ms2 = try ny.wallToMs(2026, 1, 15, 12, 0, 0);
    try std.testing.expectEqual(@as(i16, -300), ny.offsetAt(ms2));
    try std.testing.expect(ny.msToCivil(ms2).h == 12);
}
