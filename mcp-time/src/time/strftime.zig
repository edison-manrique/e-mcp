// Formato personalizado estilo strftime, en español.
// Soporta los especificadores mas usados por IAs y humanos. Escribe directo a
// un Writer (no aloca). Devuelve error.PatronInvalido si hay un % desconocido.

const std = @import("std");
const Io = std.Io;
const civil = @import("civil.zig");
const epoca = @import("epoca.zig");
const zona = @import("zona.zig");

pub const Error = error{PatronInvalido};

pub fn weekdayEs(w: u8) []const u8 {
    return switch (w) {
        0 => "domingo",
        1 => "lunes",
        2 => "martes",
        3 => "miércoles",
        4 => "jueves",
        5 => "viernes",
        else => "sábado",
    };
}

pub fn monthEs(m: u8) []const u8 {
    return switch (m) {
        1 => "enero",
        2 => "febrero",
        3 => "marzo",
        4 => "abril",
        5 => "mayo",
        6 => "junio",
        7 => "julio",
        8 => "agosto",
        9 => "septiembre",
        10 => "octubre",
        11 => "noviembre",
        else => "diciembre",
    };
}

fn wd3(w: u8) []const u8 {
    return switch (w) {
        0 => "dom",
        1 => "lun",
        2 => "mar",
        3 => "mié",
        4 => "jue",
        5 => "vie",
        else => "sáb",
    };
}

fn mon3(m: u8) []const u8 {
    return switch (m) {
        1 => "ene",
        2 => "feb",
        3 => "mar",
        4 => "abr",
        5 => "may",
        6 => "jun",
        7 => "jul",
        8 => "ago",
        9 => "sep",
        10 => "oct",
        11 => "nov",
        else => "dic",
    };
}

fn p2(w: *Io.Writer, v: u8) !void {
    try w.writeAll(&.{ '0' + v / 10, '0' + v % 10 });
}

fn offsetDe(out: *Io.Writer, off_min: i16) !void {
    const sign: u8 = if (off_min < 0) '-' else '+';
    const a: i32 = if (off_min < 0) -@as(i32, off_min) else @as(i32, off_min);
    try out.writeByte(sign);
    try p2(out, @intCast(@divTrunc(a, 60)));
    try out.writeByte(':');
    try p2(out, @intCast(@mod(a, 60)));
}

/// Formatea `ms` en la zona `z` segun `patron`. buf debe ser holgado (>= 256).
pub fn format(patron: []const u8, z: zona.Z, ms: i64, buf: []u8) Error![]u8 {
    var w: Io.Writer = .fixed(buf);
    const off = z.offsetAt(ms);
    const p = civil.msToCivil(ms, off);
    const wday = z.weekday(ms);
    const doy = civil.dayOfYear(p.y, p.mo, p.d);
    const iw = epoca.isoWeek(p.y, p.mo, p.d);
    const sec: i64 = @divFloor(ms, 1000);
    var i: usize = 0;
    while (i < patron.len) : (i += 1) {
        const c = patron[i];
        if (c != '%') {
            w.writeByte(c) catch return buf[0..0];
            continue;
        }
        i += 1;
        if (i >= patron.len) return error.PatronInvalido;
        const s = patron[i];
        switch (s) {
            '%' => w.writeByte('%') catch return buf[0..0],
            'n' => w.writeByte('\n') catch return buf[0..0],
            't' => w.writeByte('\t') catch return buf[0..0],
            'Y' => w.print("{d}", .{p.y}) catch return buf[0..0],
            'y' => p2(&w, @intCast(@mod(p.y, 100))) catch return buf[0..0],
            'C' => w.print("{d}", .{@divTrunc(p.y, 100)}) catch return buf[0..0],
            'm' => p2(&w, p.mo) catch return buf[0..0],
            'd' => p2(&w, p.d) catch return buf[0..0],
            'e' => w.print("{d: >2}", .{p.d}) catch return buf[0..0],
            'H' => p2(&w, p.h) catch return buf[0..0],
            'M' => p2(&w, p.mi) catch return buf[0..0],
            'S' => p2(&w, p.s) catch return buf[0..0],
            'j' => w.print("{d:0>3}", .{doy}) catch return buf[0..0],
            'V' => p2(&w, iw.week) catch return buf[0..0],
            'G' => w.print("{d}", .{iw.year}) catch return buf[0..0],
            'g' => p2(&w, @intCast(@mod(iw.year, 100))) catch return buf[0..0],
            'u' => p2(&w, iw.weekday) catch return buf[0..0],
            'w' => w.print("{d}", .{wday}) catch return buf[0..0],
            'A' => w.writeAll(weekdayEs(wday)) catch return buf[0..0],
            'a' => w.writeAll(wd3(wday)) catch return buf[0..0],
            'B' => w.writeAll(monthEs(p.mo)) catch return buf[0..0],
            'b', 'h' => w.writeAll(mon3(p.mo)) catch return buf[0..0],
            'p' => w.writeAll(if (p.h < 12) "AM" else "PM") catch return buf[0..0],
            'P' => w.writeAll(if (p.h < 12) "am" else "pm") catch return buf[0..0],
            'I' => {
                const h12: u8 = blk: {
                    const hh = p.h % 12;
                    break :blk if (hh == 0) 12 else hh;
                };
                p2(&w, h12) catch return buf[0..0];
            },
            'Z' => w.writeAll(z.id) catch return buf[0..0],
            'z' => offsetDe(&w, off) catch return buf[0..0],
            's' => w.print("{d}", .{sec}) catch return buf[0..0],
            'q' => w.print("{d}", .{epoca.trimestre(p.mo)}) catch return buf[0..0],
            'F' => {
                w.print("{d}-", .{p.y}) catch return buf[0..0];
                p2(&w, p.mo) catch return buf[0..0];
                w.writeByte('-') catch return buf[0..0];
                p2(&w, p.d) catch return buf[0..0];
            },
            'T' => {
                p2(&w, p.h) catch return buf[0..0];
                w.writeByte(':') catch return buf[0..0];
                p2(&w, p.mi) catch return buf[0..0];
                w.writeByte(':') catch return buf[0..0];
                p2(&w, p.s) catch return buf[0..0];
            },
            'R' => {
                p2(&w, p.h) catch return buf[0..0];
                w.writeByte(':') catch return buf[0..0];
                p2(&w, p.mi) catch return buf[0..0];
            },
            'D' => {
                p2(&w, p.mo) catch return buf[0..0];
                w.writeByte('/') catch return buf[0..0];
                p2(&w, p.d) catch return buf[0..0];
                w.writeByte('/') catch return buf[0..0];
                p2(&w, @intCast(@mod(p.y, 100))) catch return buf[0..0];
            },
            else => return error.PatronInvalido,
        }
    }
    return w.buffered();
}

// ---------- Tests ----------

test "strftime: patrones comunes" {
    const z = (zona.resolveZone("UTC")).?;
    const ms = try z.wallToMs(2026, 10, 16, 14, 5, 9);
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings("2026-10-16", try format("%Y-%m-%d", z, ms, &buf));
    try std.testing.expectEqualStrings("16 de octubre de 2026", try format("%d de %B de %Y", z, ms, &buf));
    try std.testing.expectEqualStrings("viernes", try format("%A", z, ms, &buf));
    try std.testing.expectEqualStrings("14:05:09", try format("%H:%M:%S", z, ms, &buf));
    try std.testing.expectEqualStrings("289", try format("%j", z, ms, &buf));
    try std.testing.expectEqualStrings("42", try format("%V", z, ms, &buf));
    try std.testing.expectError(error.PatronInvalido, format("%X", z, ms, &buf));
}
