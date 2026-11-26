// Estandares de fecha: semana ISO-8601, dia del año, trimestre y epocas
// (Unix, Julian Day / MJD, serial de Excel). Puro.

const std = @import("std");
const civil = @import("civil.zig");

pub const IsoWeek = struct {
    year: i64, // año ISO (puede diferir del año civil)
    week: u8, // 1..53
    weekday: u8, // 1=lunes .. 7=domingo
};

/// 1=lunes .. 7=domingo.
pub fn isoWeekday(y: i64, mo: u8, d: u8) u8 {
    const wd = civil.weekdayYmd(y, mo, d); // 0=domingo
    return if (wd == 0) 7 else wd;
}

fn semanasEnAnioIso(y: i64) u8 {
    const j1 = isoWeekday(y, 1, 1);
    if (j1 == 4) return 53;
    if (j1 == 3 and civil.isLeap(y)) return 53;
    return 52;
}

/// Semana ISO-8601 de una fecha civil.
pub fn isoWeek(y: i64, mo: u8, d: u8) IsoWeek {
    const wd = isoWeekday(y, mo, d);
    const doy = civil.dayOfYear(y, mo, d);
    const w: i64 = @divTrunc(@as(i64, doy) - wd + 10, 7);
    if (w < 1) {
        const py = y - 1;
        return .{ .year = py, .week = semanasEnAnioIso(py), .weekday = wd };
    }
    if (w > semanasEnAnioIso(y)) {
        return .{ .year = y + 1, .week = 1, .weekday = wd };
    }
    return .{ .year = y, .week = @intCast(w), .weekday = wd };
}

pub fn trimestre(mo: u8) u8 {
    return (mo - 1) / 3 + 1;
}

/// Julian Day (astronomico) a las 00:00 UT. 1970-01-01 = 2440587.5.
pub fn julianDay(y: i64, mo: u8, d: u8) f64 {
    return @as(f64, @floatFromInt(civil.daysFromCivil(y, mo, d))) + 2440587.5;
}

/// Julian Day con fraccion de dia (h,mi,s en UT).
pub fn julianDayFrac(y: i64, mo: u8, d: u8, h: u8, mi: u8, s: u8) f64 {
    const frac = (@as(f64, @floatFromInt(h)) + @as(f64, @floatFromInt(mi)) / 60.0 + @as(f64, @floatFromInt(s)) / 3600.0) / 24.0;
    return julianDay(y, mo, d) + frac;
}

/// Modified Julian Date = JD - 2400000.5 (1858-11-17 00:00 = 0).
pub fn mjd(y: i64, mo: u8, d: u8) f64 {
    return julianDay(y, mo, d) - 2400000.5;
}

/// Serial de Excel (sistema 1900). Exacto para fechas >= 1900-03-01.
pub fn excelSerial(y: i64, mo: u8, d: u8) f64 {
    return @as(f64, @floatFromInt(civil.daysFromCivil(y, mo, d))) + 25569.0;
}

// ---------- Tests ----------

test "epoca: semana ISO" {
    // 2026-01-01 es jueves -> semana ISO 1 de 2026.
    const a = isoWeek(2026, 1, 1);
    try std.testing.expect(a.year == 2026 and a.week == 1 and a.weekday == 4);
    // 2027-01-01 es viernes -> semana ISO 53 de 2026.
    const b = isoWeek(2027, 1, 1);
    try std.testing.expect(b.year == 2026 and b.week == 53);
    // 2024-12-30 (lunes) -> semana 1 de 2025.
    const c = isoWeek(2024, 12, 30);
    try std.testing.expect(c.year == 2025 and c.week == 1 and c.weekday == 1);
    // 2026-10-16 es viernes -> semana 42.
    const e = isoWeek(2026, 10, 16);
    try std.testing.expect(e.week == 42 and e.weekday == 5);
}

test "epoca: julian, mjd, excel" {
    try std.testing.expect(@abs(julianDay(1970, 1, 1) - 2440587.5) < 1e-9);
    try std.testing.expect(@abs(mjd(1858, 11, 17) - 0.0) < 1e-9);
    try std.testing.expect(@abs(excelSerial(1970, 1, 1) - 25569.0) < 1e-9);
    try std.testing.expectEqual(@as(u8, 4), trimestre(10));
    try std.testing.expectEqual(@as(u8, 1), trimestre(1));
}
