// Dias laborables: fin de semana (sabado/domingo) + feriados de `feriados.Cfg`.
// Puro. Todo el recorrido es por dias civiles en la zona pedida.

const std = @import("std");
const civil = @import("civil.zig");
const feriados = @import("feriados.zig");
const zona = @import("zona.zig");

/// ¿Es dia laborable (L-V y no feriado)?
pub fn esLaborable(y: i64, mo: u8, d: u8, cfg: feriados.Cfg) bool {
    const wd = civil.weekdayYmd(y, mo, d);
    if (wd == 0 or wd == 6) return false;
    return !feriados.esFeriado(y, mo, d, cfg);
}

pub fn esLaborableMs(ms: i64, z: zona.Z, cfg: feriados.Cfg) bool {
    const p = z.msToCivil(ms);
    return esLaborable(p.y, p.mo, p.d, cfg);
}

/// Laborables en [desde, hasta) por dias civiles locales. Negativo si hasta < desde.
pub fn contar(desde_ms: i64, hasta_ms: i64, z: zona.Z, cfg: feriados.Cfg) i64 {
    const a = z.msToCivil(desde_ms);
    const b = z.msToCivil(hasta_ms);
    var d0 = civil.daysFromCivil(a.y, a.mo, a.d);
    var d1 = civil.daysFromCivil(b.y, b.mo, b.d);
    var sign: i64 = 1;
    if (d1 < d0) {
        const t = d0;
        d0 = d1;
        d1 = t;
        sign = -1;
    }
    var count: i64 = 0;
    var day = d0;
    while (day < d1) : (day += 1) {
        const p = civil.civilFromDays(day);
        if (esLaborable(p.y, p.mo, p.d, cfg)) count += 1;
    }
    return count * sign;
}

/// Suma `n` dias laborables a `start_ms` conservando la hora local.
/// n puede ser negativo (retrocede). Devuelve el ms del dia resultante.
pub fn sumar(start_ms: i64, n: i64, z: zona.Z, cfg: feriados.Cfg) !i64 {
    const a = z.msToCivil(start_ms);
    var day = civil.daysFromCivil(a.y, a.mo, a.d);
    if (n == 0) {
        // Normaliza al mismo instante (sin mover).
        return start_ms;
    }
    const step: i64 = if (n > 0) 1 else -1;
    var remaining: i64 = if (n < 0) -n else n;
    while (remaining > 0) {
        day += step;
        const p = civil.civilFromDays(day);
        if (esLaborable(p.y, p.mo, p.d, cfg)) remaining -= 1;
    }
    const r = civil.civilFromDays(day);
    return z.wallToMs(r.y, r.mo, r.d, a.h, a.mi, a.s);
}

// ---------- Tests ----------

test "laborable: contar con fin de semana" {
    const z = (zona.resolveZone("UTC")).?;
    // Lunes 2026-01-05 a viernes 2026-01-09 -> 4 laborables ([lun..jue)).
    const a = try z.wallToMs(2026, 1, 5, 9, 0, 0);
    const b = try z.wallToMs(2026, 1, 9, 9, 0, 0);
    const cfg = feriados.Cfg{};
    try std.testing.expectEqual(@as(i64, 4), contar(a, b, z, cfg));
    // Invertido -> negativo.
    try std.testing.expectEqual(@as(i64, -4), contar(b, a, z, cfg));
}

test "laborable: feriado descuenta" {
    const z = (zona.resolveZone("UTC")).?;
    const a = try z.wallToMs(2026, 12, 24, 9, 0, 0); // jue
    const b = try z.wallToMs(2026, 12, 26, 9, 0, 0); // sab
    const pe = feriados.Cfg{ .pais = .pe };
    // 24 (jue, laborable), 25 (feriado) -> 1.
    try std.testing.expectEqual(@as(i64, 1), contar(a, b, z, pe));
}

test "laborable: sumar dias laborables" {
    const z = (zona.resolveZone("UTC")).?;
    // Viernes 2026-01-02 + 1 laborable = lunes 2026-01-05.
    const v = try z.wallToMs(2026, 1, 2, 10, 0, 0);
    const r = try sumar(v, 1, z, feriados.Cfg{});
    const p = z.msToCivil(r);
    try std.testing.expect(p.y == 2026 and p.mo == 1 and p.d == 5 and p.h == 10);
    // Retrocede: lunes 2026-01-05 - 1 laborable = viernes 2026-01-02.
    const l = try z.wallToMs(2026, 1, 5, 10, 0, 0);
    const r2 = try sumar(l, -1, z, feriados.Cfg{});
    try std.testing.expect(z.msToCivil(r2).d == 2);
}
