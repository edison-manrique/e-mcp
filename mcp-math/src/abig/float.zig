const std = @import("std");
const abi = @import("int.zig");
const Big = abi.Big;

// Flotante decimal exacto: valor = m x 10^e, m entero arbitrario.
// Sin inf/nan: todo es exacto o redondeado a `sig` digitos significativos
// (half-up sobre magnitud). Por defecto sig=30, maximo 500.
// Limites: |e| <= 100000, digitos de entrada <= 8192 (viene de int.zig).

pub const MAX_SIG: u16 = 500;
pub const MAX_EXP: i32 = 100000;

pub const Dec = struct {
    m: Big,
    e: i32,

    pub fn deinit(self: *Dec) void {
        self.m.deinit();
        self.* = undefined;
    }
};

fn digitsOf(m: *const Big, alloc: std.mem.Allocator) !usize {
    var t = m.*;
    const s = try t.toString(alloc, 10, .lower);
    defer alloc.free(s);
    const is_neg: usize = if (!t.isPositive() and !t.eqlZero()) 1 else 0;
    return s.len - is_neg;
}

fn pow10(alloc: std.mem.Allocator, k: u32) !Big {
    var base = try Big.initSet(alloc, 10);
    defer base.deinit();
    var r = try Big.init(alloc);
    errdefer r.deinit();
    var b = base;
    try r.pow(&b, k);
    return r;
}

/// Redondea el Dec a `sig` digitos significativos (half-up en magnitud).
fn roundSig(alloc: std.mem.Allocator, d: *Dec, sig: u16) !void {
    if (sig < 1) return error.Invalid;
    if (d.m.eqlZero()) {
        d.e = 0;
        return;
    }
    const n = try digitsOf(&d.m, alloc);
    if (n <= sig) return;
    const k: u32 = @intCast(n - sig);
    const p = try pow10(alloc, k);
    defer {
        var x = p;
        x.deinit();
    }
    var q = try Big.init(alloc);
    errdefer q.deinit();
    var r = try Big.init(alloc);
    defer r.deinit();
    var mm = d.m;
    try q.divTrunc(&r, &mm, &p);
    // Half-up sobre magnitud: si 2*|r| >= p, |q| += 1.
    var ar = r;
    if (!ar.isPositive()) ar.abs();
    var two = try Big.initSet(alloc, 2);
    defer two.deinit();
    const twice = try abi.mul(alloc, &ar, &two);
    defer {
        var x = twice;
        x.deinit();
    }
    const pp = p; // alias de lectura
    if (Big.order(twice, pp) != .lt) {
        var one = try Big.initSet(alloc, 1);
        defer one.deinit();
        var qq = q; // alias: q se reemplaza abajo
        if (!d.m.isPositive()) {
            const t = try abi.sub(alloc, &qq, &one);
            q.deinit();
            q = t;
        } else {
            const t = try abi.add(alloc, &qq, &one);
            q.deinit();
            q = t;
        }
    }
    d.m.deinit();
    d.m = q;
    d.e += @intCast(k);
}

/// Parsea "[-]d[.ddd][e[+-]d]" o "0x..." entero. Error.Invalid si mal.
pub fn parse(alloc: std.mem.Allocator, s: []const u8) !Dec {
    const t = std.mem.trim(u8, s, " \t\r\n");
    if (t.len == 0 or t.len > abi.MAX_STR) return error.Invalid;
    // Hex entero directo.
    if (t.len >= 2 and t[0] == '0' and (t[1] == 'x' or t[1] == 'X')) {
        const m = try abi.parse(alloc, t);
        return .{ .m = m, .e = 0 };
    }
    var is_neg = false;
    var u = t;
    if (u[0] == '-' or u[0] == '+') {
        is_neg = u[0] == '-';
        u = u[1..];
    }
    if (u.len == 0) return error.Invalid;
    // Parte exponente.
    var exp: i32 = 0;
    if (std.mem.indexOfAny(u8, u, "eE")) |ei| {
        const es = u[ei + 1 ..];
        if (es.len == 0) return error.Invalid;
        exp = std.fmt.parseInt(i32, es, 10) catch return error.Invalid;
        u = u[0..ei];
    }
    // Parte mantisa: solo digitos y un punto.
    var intpart: usize = 0;
    var fracpart: usize = 0;
    var seen_dot = false;
    var ndig: usize = 0;
    for (u) |c| {
        if (c == '.') {
            if (seen_dot) return error.Invalid;
            seen_dot = true;
            continue;
        }
        if (c == '_') continue;
        if (c < '0' or c > '9') return error.Invalid;
        ndig += 1;
        if (!seen_dot) intpart += 1 else fracpart += 1;
    }
    if (ndig == 0) return error.Invalid;
    // Digitos planos sin punto.
    var buf = try alloc.alloc(u8, ndig);
    defer alloc.free(buf);
    var o: usize = 0;
    for (u) |c| {
        if (c == '.' or c == '_') continue;
        buf[o] = c;
        o += 1;
    }
    var m = try Big.init(alloc);
    errdefer m.deinit();
    m.setString(10, buf) catch return error.Invalid;
    if (is_neg and !m.eqlZero()) m.negate();
    const e64: i64 = @as(i64, exp) - @as(i64, @intCast(fracpart));
    if (e64 > MAX_EXP or e64 < -MAX_EXP) return error.Invalid;
    return .{ .m = m, .e = @intCast(e64) };
}

/// -x (clona; usa el allocator del valor).
pub fn negate(a: *const Dec) !Dec {
    var m = try a.m.clone();
    errdefer m.deinit();
    if (!m.eqlZero()) m.negate();
    return .{ .m = m, .e = a.e };
}

/// Suma/resta con `sig` digitos. Si los exponentes difieren en mas de
/// sig+10, el menor es despreciable y se devuelve el mayor.
fn addSub(alloc: std.mem.Allocator, a: *const Dec, b: *const Dec, sig: u16, is_sub: bool) !Dec {
    var bb = try negate(b);
    defer bb.deinit();
    const x = a;
    const y = if (is_sub) &bb else b;
    if (x.e == y.e) {
        const m = try abi.add(alloc, &x.m, &y.m);
        var d = Dec{ .m = m, .e = x.e };
        try roundSig(alloc, &d, sig);
        return d;
    }
    const diff: i64 = @as(i64, x.e) - @as(i64, y.e);
    const adiff: usize = @intCast(if (diff < 0) -diff else diff);
    if (adiff > @as(usize, sig) + 10) {
        // El de exponente menor (mas pequeno) es despreciable.
        const keep = if (diff < 0) y else x;
        const m = try keep.m.clone();
        var d = Dec{ .m = m, .e = keep.e };
        try roundSig(alloc, &d, sig);
        return d;
    }
    const k: u32 = @intCast(adiff);
    const p = try pow10(alloc, k);
    defer {
        var t = p;
        t.deinit();
    }
    var scaled: Big = undefined;
    var e: i32 = undefined;
    if (diff > 0) {
        // x.e mayor: escalar x.
        scaled = try abi.mul(alloc, &x.m, &p);
        e = y.e;
        const m = try abi.add(alloc, &scaled, &y.m);
        scaled.deinit();
        var d = Dec{ .m = m, .e = e };
        try roundSig(alloc, &d, sig);
        return d;
    } else {
        scaled = try abi.mul(alloc, &y.m, &p);
        e = x.e;
        const m = try abi.add(alloc, &x.m, &scaled);
        scaled.deinit();
        var d = Dec{ .m = m, .e = e };
        try roundSig(alloc, &d, sig);
        return d;
    }
}

pub fn add(alloc: std.mem.Allocator, a: *const Dec, b: *const Dec, sig: u16) !Dec {
    return addSub(alloc, a, b, sig, false);
}
pub fn sub(alloc: std.mem.Allocator, a: *const Dec, b: *const Dec, sig: u16) !Dec {
    return addSub(alloc, a, b, sig, true);
}

pub fn mul(alloc: std.mem.Allocator, a: *const Dec, b: *const Dec, sig: u16) !Dec {
    const m = try abi.mul(alloc, &a.m, &b.m);
    const e64 = @as(i64, a.e) + @as(i64, b.e);
    if (e64 > MAX_EXP or e64 < -MAX_EXP) {
        var t = m;
        t.deinit();
        return error.Invalid;
    }
    var d = Dec{ .m = m, .e = @intCast(e64) };
    errdefer d.deinit();
    try roundSig(alloc, &d, sig);
    return d;
}

/// a/b con `sig` digitos significativos. Error.DivZero si b == 0.
pub fn div(alloc: std.mem.Allocator, a: *const Dec, b: *const Dec, sig: u16) !Dec {
    if (b.m.eqlZero()) return error.DivZero;
    if (sig < 1 or sig > MAX_SIG) return error.Invalid;
    var bb = b.*;
    const da = try digitsOf(&a.m, alloc);
    const db = try digitsOf(&bb.m, alloc);
    var k: i64 = @as(i64, sig) - (@as(i64, @intCast(da)) - @as(i64, @intCast(db)));
    if (k < 0) k = 0;
    if (k > MAX_EXP) return error.Invalid;
    const p = try pow10(alloc, @intCast(k));
    defer {
        var x = p;
        x.deinit();
    }
    const num = try abi.mul(alloc, &a.m, &p);
    defer {
        var x = num;
        x.deinit();
    }
    const dq = try abi.divTrunc(alloc, &num, &bb.m);
    var q = dq.q;
    errdefer q.deinit();
    var r = dq.r;
    defer r.deinit();
    // Half-up con el resto (divTrunc trunca): si 2*|r| >= |b|, |q| += 1.
    var ar = r;
    if (!ar.isPositive()) ar.abs();
    var bm = bb.m;
    if (!bm.isPositive()) bm.abs();
    var two = try Big.initSet(alloc, 2);
    defer two.deinit();
    const twice = try abi.mul(alloc, &ar, &two);
    defer {
        var x = twice;
        x.deinit();
    }
    if (Big.order(twice, bm) != .lt) {
        // Signo del cociente exacto (no el de q truncado, que puede ser 0).
        const num_neg = !num.isPositive() and !num.eqlZero();
        const den_neg = !bb.m.isPositive() and !bb.m.eqlZero();
        var one = try Big.initSet(alloc, 1);
        defer one.deinit();
        var qq = q;
        if (num_neg != den_neg) {
            const t = try abi.sub(alloc, &qq, &one);
            q.deinit();
            q = t;
        } else {
            const t = try abi.add(alloc, &qq, &one);
            q.deinit();
            q = t;
        }
    }
    const e64 = @as(i64, a.e) - @as(i64, b.e) - k;
    if (e64 > MAX_EXP or e64 < -MAX_EXP) {
        q.deinit();
        return error.Invalid;
    }
    var d = Dec{ .m = q, .e = @intCast(e64) };
    try roundSig(alloc, &d, sig);
    return d;
}

/// sqrt(x) con `sig` digitos. Error.Domain si x < 0.
pub fn sqrt(alloc: std.mem.Allocator, x: *const Dec, sig: u16) !Dec {
    var xx = x.*;
    if (!xx.m.isPositive() and !xx.m.eqlZero()) return error.Domain;
    if (sig < 1 or sig > MAX_SIG) return error.Invalid;
    if (xx.m.eqlZero()) {
        const z = try Big.initSet(alloc, 0);
        return .{ .m = z, .e = 0 };
    }
    var m = try xx.m.clone();
    defer m.deinit();
    var e = x.e;
    if (@mod(e, 2) != 0) {
        // e impar: m *= 10, e -= 1.
        const t = try pow10(alloc, 1);
        defer {
            var y = t;
            y.deinit();
        }
        const n = try abi.mul(alloc, &m, &t);
        m.deinit();
        m = n;
        e -= 1;
    }
    const da = try digitsOf(&m, alloc);
    const half: usize = (da + 1) / 2;
    // +2 digitos de guarda para que roundSig redondee (no trunque).
    var k: usize = 0;
    if (half < sig + 2) k = sig + 2 - half;
    if (k > 0) {
        const p = try pow10(alloc, @intCast(2 * k));
        defer {
            var y = p;
            y.deinit();
        }
        const n = try abi.mul(alloc, &m, &p);
        m.deinit();
        m = n;
    }
    var s = try Big.init(alloc);
    errdefer s.deinit();
    var mm = m;
    try s.sqrt(&mm);
    const e2 = @divExact(e, 2) - @as(i32, @intCast(k));
    var d = Dec{ .m = s, .e = e2 };
    try roundSig(alloc, &d, sig);
    return d;
}

/// Formato: plano si el punto cae en [-6, 40], cientifico si no.
pub fn format(alloc: std.mem.Allocator, d: *const Dec) ![]u8 {
    var mm = d.m;
    const is_neg = !mm.isPositive() and !mm.eqlZero();
    var mag = try mm.clone();
    defer mag.deinit();
    if (is_neg) mag.abs();
    const s = try mag.toString(alloc, 10, .lower);
    defer alloc.free(s);
    const ndig: i64 = @intCast(s.len);
    const point: i64 = ndig + @as(i64, d.e); // digitos enteros
    if (point > 40 or point < -6) {
        // Cientifico: d.ddd e±X.
        var out = try alloc.alloc(u8, s.len + 16);
        errdefer alloc.free(out);
        var o: usize = 0;
        if (is_neg) {
            out[0] = '-';
            o = 1;
        }
        out[o] = s[0];
        o += 1;
        if (s.len > 1) {
            out[o] = '.';
            o += 1;
            @memcpy(out[o .. o + s.len - 1], s[1..]);
            o += s.len - 1;
        }
        const ex = point - 1;
        o += (try std.fmt.bufPrint(out[o..], "e{d}", .{ex})).len;
        return out[0..o];
    }
    if (point <= 0) {
        // 0.00...digitos
        const zeros: usize = @intCast(-point);
        var out = try alloc.alloc(u8, @as(usize, if (is_neg) 1 else 0) + 2 + zeros + s.len);
        var o: usize = 0;
        if (is_neg) {
            out[0] = '-';
            o = 1;
        }
        out[o] = '0';
        out[o + 1] = '.';
        o += 2;
        @memset(out[o .. o + zeros], '0');
        o += zeros;
        @memcpy(out[o .. o + s.len], s);
        return out;
    }
    const ipart: usize = @intCast(point);
    if (ipart >= s.len) {
        // Entero con ceros.
        const zeros: usize = ipart - s.len;
        var out = try alloc.alloc(u8, @as(usize, if (is_neg) 1 else 0) + s.len + zeros);
        var o: usize = 0;
        if (is_neg) {
            out[0] = '-';
            o = 1;
        }
        @memcpy(out[o .. o + s.len], s);
        o += s.len;
        @memset(out[o .. o + zeros], '0');
        return out;
    }
    var out = try alloc.alloc(u8, @as(usize, if (is_neg) 1 else 0) + s.len + 1);
    var o: usize = 0;
    if (is_neg) {
        out[0] = '-';
        o = 1;
    }
    @memcpy(out[o .. o + ipart], s[0..ipart]);
    o += ipart;
    out[o] = '.';
    o += 1;
    @memcpy(out[o .. o + s.len - ipart], s[ipart..]);
    return out;
}

test "float: parse y formato" {
    const alloc = std.testing.allocator;
    var a = try parse(alloc, "1.5");
    defer a.deinit();
    try std.testing.expect(a.e == -1);
    const f = try format(alloc, &a);
    defer alloc.free(f);
    try std.testing.expectEqualStrings("1.5", f);
    var b = try parse(alloc, "-2.5e3");
    defer b.deinit();
    const g = try format(alloc, &b);
    defer alloc.free(g);
    try std.testing.expectEqualStrings("-2500", g);
}

test "float: ops con precision" {
    const alloc = std.testing.allocator;
    var a = try parse(alloc, "1");
    defer a.deinit();
    var b = try parse(alloc, "3");
    defer b.deinit();
    var q = try div(alloc, &a, &b, 10);
    defer q.deinit();
    const s = try format(alloc, &q);
    defer alloc.free(s);
    try std.testing.expectEqualStrings("0.3333333333", s);
    var c = try parse(alloc, "2");
    defer c.deinit();
    var r = try sqrt(alloc, &c, 10);
    defer r.deinit();
    const t = try format(alloc, &r);
    defer alloc.free(t);
    try std.testing.expect(std.mem.startsWith(u8, t, "1.414213562"));
}
