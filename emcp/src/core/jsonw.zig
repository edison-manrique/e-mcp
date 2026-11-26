// Escritura JSON sin dependencias: escape propio (UTF-8 estricto).
// Solo se usa para el eco de `initialize`; el resto de respuestas se
// emiten con std.json.Stringify (proto.zig).

const std = @import("std");
const Io = std.Io;

pub fn writeJsonStr(out: *Io.Writer, s: []const u8) !void {
    try out.writeAll("\"");
    // Jamas emitir UTF-8 invalido: secuencia mala -> U+FFFD.
    var k: usize = 0;
    while (k < s.len) {
        const c = s[k];
        switch (c) {
            '"' => {
                try out.writeAll("\\\"");
                k += 1;
            },
            '\\' => {
                try out.writeAll("\\\\");
                k += 1;
            },
            '\n' => {
                try out.writeAll("\\n");
                k += 1;
            },
            '\r' => {
                try out.writeAll("\\r");
                k += 1;
            },
            '\t' => {
                try out.writeAll("\\t");
                k += 1;
            },
            0x08 => {
                try out.writeAll("\\b");
                k += 1;
            },
            0x0C => {
                try out.writeAll("\\f");
                k += 1;
            },
            else => {
                if (c < 0x20) {
                    try out.writeAll("\\u00");
                    const hi: u8 = c >> 4;
                    const lo: u8 = c & 0xF;
                    try out.writeAll(&[_]u8{ hexDe(hi), hexDe(lo) });
                    k += 1;
                } else if (c < 0x80) {
                    try out.writeAll(&[_]u8{c});
                    k += 1;
                } else {
                    const n = secUtf8(s[k..]);
                    if (n == 0) {
                        try out.writeAll("\\ufffd");
                        k += 1;
                    } else {
                        try out.writeAll(s[k .. k + n]);
                        k += n;
                    }
                }
            },
        }
    }
    try out.writeAll("\"");
}

fn hexDe(n: u8) u8 {
    return if (n < 10) '0' + n else 'a' + (n - 10);
}

// Longitud de la secuencia UTF-8 en s[0] (0 = invalida). Estricto:
// sin overlongs, sin subrogados, <= U+10FFFF.
fn secUtf8(s: []const u8) usize {
    if (s.len == 0) return 0;
    const c = s[0];
    if (c < 0x80) return 1;
    if (c < 0xC2) return 0;
    const cont = struct {
        fn ok(x: u8) bool {
            return (x & 0xC0) == 0x80;
        }
    }.ok;
    if (c < 0xE0) {
        if (s.len < 2 or !cont(s[1])) return 0;
        return 2;
    }
    if (c < 0xF0) {
        if (s.len < 3 or !cont(s[1]) or !cont(s[2])) return 0;
        if (c == 0xE0 and s[1] < 0xA0) return 0;
        if (c == 0xED and s[1] > 0x9F) return 0;
        return 3;
    }
    if (c < 0xF5) {
        if (s.len < 4 or !cont(s[1]) or !cont(s[2]) or !cont(s[3])) return 0;
        if (c == 0xF0 and s[1] < 0x90) return 0;
        if (c == 0xF4 and s[1] > 0x8F) return 0;
        return 4;
    }
    return 0;
}

test "writeJsonStr escapa control y comillas" {
    const t = std.testing;
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeJsonStr(&w, "a\"b\n\tc");
    try t.expectEqualStrings("\"a\\\"b\\n\\tc\"", w.buffered());
}

test "writeJsonStr escapa caracteres de control adicionales" {
    const t = std.testing;
    // \x01 (SOH), \x0B (VT), \x1F (US) deben quedar como \u00XX
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeJsonStr(&w, "\x01");
    try t.expectEqualStrings("\"\\u0001\"", w.buffered());

    var buf2: [64]u8 = undefined;
    var w2: Io.Writer = .fixed(&buf2);
    try writeJsonStr(&w2, "\x0B");
    try t.expectEqualStrings("\"\\u000b\"", w2.buffered());

    var buf3: [64]u8 = undefined;
    var w3: Io.Writer = .fixed(&buf3);
    try writeJsonStr(&w3, "\x1F");
    try t.expectEqualStrings("\"\\u001f\"", w3.buffered());
}

test "writeJsonStr UTF-8 invalido reemplazado con U+FFFD" {
    const t = std.testing;
    var buf: [32]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    // 0xFF es secuencia UTF-8 invalida -> debe emitir \ufffd
    try writeJsonStr(&w, "\xFF");
    try t.expectEqualStrings("\"\\ufffd\"", w.buffered());
}
