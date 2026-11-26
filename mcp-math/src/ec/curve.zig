const std = @import("std");
const abi = @import("../abig/int.zig");
const Big = abi.Big;
const Field = @import("field.zig").Field;

// Curva corta de Weierstrass y^2 = x^3 + a*x + b sobre Fp,
// longitud arbitraria (p, n de cualquier tamaño).
// Puntos afines + Jacobiano interno (una sola inversion por mul).
pub const Point = struct {
    x: Big,
    y: Big,
    inf: bool = false,

    pub fn deinit(self: *Point) void {
        self.x.deinit();
        self.y.deinit();
        self.* = undefined;
    }

    pub fn clone(self: *const Point) !Point {
        return .{ .x = try self.x.clone(), .y = try self.y.clone(), .inf = self.inf };
    }

    pub fn infinity(alloc: std.mem.Allocator) !Point {
        return .{ .x = try Big.initSet(alloc, 0), .y = try Big.initSet(alloc, 0), .inf = true };
    }
};

const Jac = struct {
    x: Big,
    y: Big,
    z: Big,

    fn deinit(self: *Jac) void {
        self.x.deinit();
        self.y.deinit();
        self.z.deinit();
    }
};

pub const Curve = struct {
    f: Field, // p
    a: Big,
    b: Big,
    n: Big, // orden del generador
    gx: Big,
    gy: Big,
    bytelen: usize, // bytes por coordenada = ceil(bitlen(p)/8)

    pub fn init(alloc: std.mem.Allocator, p: []const u8, a: []const u8, b: []const u8, n: []const u8, gx: []const u8, gy: []const u8) !Curve {
        var f = try Field.init(alloc, p);
        errdefer f.deinit();
        var aa = try abi.parse(alloc, a);
        errdefer aa.deinit();
        var bb = try abi.parse(alloc, b);
        errdefer bb.deinit();
        var nn = try abi.parse(alloc, n);
        errdefer nn.deinit();
        var xx = try abi.parse(alloc, gx);
        errdefer xx.deinit();
        var yy = try abi.parse(alloc, gy);
        errdefer yy.deinit();
        const bl = try byteLen(&f.p);
        var c = Curve{ .f = f, .a = aa, .b = bb, .n = nn, .gx = xx, .gy = yy, .bytelen = bl };
        try c.checkNonsingular(alloc);
        // Valida que G este en la curva.
        var g = try c.generator();
        defer g.deinit();
        if (!try c.isOnCurve(&g)) return error.Invalid;
        return c;
    }

    pub fn initSecp256k1(alloc: std.mem.Allocator) !Curve {
        return init(
            alloc,
            "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F",
            "0",
            "7",
            "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",
            "0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",
            "0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8",
        );
    }

    /// Curva personalizada y^2 = x^3 + a*x + b sobre Fp.
    /// `n` vacio o "0" = sin orden conocido (mul sin reduccion).
    /// No exige G: gx/gy quedan en 0. Valida discriminante != 0.
    pub fn initParams(alloc: std.mem.Allocator, p_str: []const u8, a_str: []const u8, b_str: []const u8, n_str: ?[]const u8) !Curve {
        var f = try Field.init(alloc, p_str);
        errdefer f.deinit();
        var aa = try abi.parse(alloc, if (a_str.len == 0) "0" else a_str);
        errdefer aa.deinit();
        var bb = try abi.parse(alloc, if (b_str.len == 0) "7" else b_str);
        errdefer bb.deinit();
        var nn: Big = undefined;
        var has_n = false;
        if (n_str) |ns| {
            if (ns.len > 0 and !std.mem.eql(u8, ns, "0")) {
                nn = try abi.parse(alloc, ns);
                has_n = true;
            }
        }
        if (!has_n) nn = try Big.initSet(alloc, 0);
        errdefer nn.deinit();
        var zx = try Big.initSet(alloc, 0);
        errdefer zx.deinit();
        var zy = try Big.initSet(alloc, 0);
        errdefer zy.deinit();
        const bl = try byteLen(&f.p);
        var c = Curve{ .f = f, .a = aa, .b = bb, .n = nn, .gx = zx, .gy = zy, .bytelen = bl };
        try c.checkNonsingular(alloc);
        return c;
    }

    fn checkNonsingular(self: *Curve, alloc: std.mem.Allocator) !void {
        // 4a^3 + 27b^2 != 0 (mod p)
        const a3 = try self.f.mul(alloc, &self.a, &self.a);
        defer {
            var t = a3;
            t.deinit();
        }
        const a33 = try self.f.mul(alloc, &a3, &self.a);
        defer {
            var t = a33;
            t.deinit();
        }
        var four = try Big.initSet(alloc, 4);
        defer four.deinit();
        const t1 = try self.f.mul(alloc, &four, &a33);
        defer {
            var t = t1;
            t.deinit();
        }
        const b2 = try self.f.mul(alloc, &self.b, &self.b);
        defer {
            var t = b2;
            t.deinit();
        }
        var t27 = try Big.initSet(alloc, 27);
        defer t27.deinit();
        const t2 = try self.f.mul(alloc, &t27, &b2);
        defer {
            var t = t2;
            t.deinit();
        }
        const d = try self.f.add(alloc, &t1, &t2);
        defer {
            var t = d;
            t.deinit();
        }
        if (d.eqlZero()) return error.Invalid;
    }

    pub fn deinit(self: *Curve) void {
        self.f.deinit();
        self.a.deinit();
        self.b.deinit();
        self.n.deinit();
        self.gx.deinit();
        self.gy.deinit();
        self.* = undefined;
    }

    fn byteLen(p: *const Big) !usize {
        var t = p.*;
        return (t.bitCountAbs() + 7) / 8;
    }

    pub fn generator(self: *Curve) !Point {
        return .{ .x = try self.gx.clone(), .y = try self.gy.clone(), .inf = false };
    }

    pub fn isOnCurve(self: *Curve, pt: *const Point) !bool {
        if (pt.inf) return true;
        const alloc = pt.x.allocator;
        // y^2 == x^3 + a*x + b (mod p)
        const y2 = try self.f.mul(alloc, &pt.y, &pt.y);
        defer {
            var t = y2;
            t.deinit();
        }
        const x2 = try self.f.mul(alloc, &pt.x, &pt.x);
        defer {
            var t = x2;
            t.deinit();
        }
        const x3 = try self.f.mul(alloc, &x2, &pt.x);
        defer {
            var t = x3;
            t.deinit();
        }
        const ax = try self.f.mul(alloc, &self.a, &pt.x);
        defer {
            var t = ax;
            t.deinit();
        }
        const rhs1 = try self.f.add(alloc, &x3, &ax);
        defer {
            var t = rhs1;
            t.deinit();
        }
        const rhs = try self.f.add(alloc, &rhs1, &self.b);
        defer {
            var t = rhs;
            t.deinit();
        }
        return y2.eql(rhs);
    }

    pub fn neg(self: *Curve, pt: *const Point) !Point {
        if (pt.inf) {
            const alloc = pt.x.allocator;
            return Point.infinity(alloc);
        }
        const alloc = pt.x.allocator;
        var x = try pt.x.clone();
        errdefer x.deinit();
        const y = try self.f.neg(alloc, &pt.y);
        return .{ .x = x, .y = y, .inf = false };
    }

    /// Jacobiano del infinito: (1, 1, 0).
    fn jacInf(alloc: std.mem.Allocator) !Jac {
        var z = try Big.initSet(alloc, 0);
        var x = Big.initSet(alloc, 1) catch |e| {
            z.deinit();
            return e;
        };
        const y = Big.initSet(alloc, 1) catch |e| {
            z.deinit();
            x.deinit();
            return e;
        };
        return .{ .x = x, .y = y, .z = z };
    }

    fn toJac(self: *Curve, alloc: std.mem.Allocator, pt: *const Point) !Jac {
        _ = self;
        if (pt.inf) return jacInf(alloc);
        return .{ .x = try pt.x.clone(), .y = try pt.y.clone(), .z = try Big.initSet(alloc, 1) };
    }

    fn fromJac(self: *Curve, alloc: std.mem.Allocator, j: *const Jac) !Point {
        var z = j.z;
        if (z.eqlZero()) return Point.infinity(alloc);
        const zi = try self.f.inv(alloc, &z);
        defer {
            var t = zi;
            t.deinit();
        }
        const zi2 = try self.f.mul(alloc, &zi, &zi);
        defer {
            var t = zi2;
            t.deinit();
        }
        const zi3 = try self.f.mul(alloc, &zi2, &zi);
        defer {
            var t = zi3;
            t.deinit();
        }
        const x = try self.f.mul(alloc, &j.x, &zi2);
        errdefer {
            var t = x;
            t.deinit();
        }
        const y = try self.f.mul(alloc, &j.y, &zi3);
        return .{ .x = x, .y = y, .inf = false };
    }

    // Duplicado Jacobiano generico (m = 3X^2 + aZ^4).
    fn dblJac(self: *Curve, alloc: std.mem.Allocator, p: *const Jac) !Jac {
        var pz = p.z;
        if (pz.eqlZero()) return jacInf(alloc);
        const f = &self.f;
        const x2 = try f.mul(alloc, &p.x, &p.x);
        defer {
            var t = x2;
            t.deinit();
        }
        var three = try Big.initSet(alloc, 3);
        defer three.deinit();
        const tx2 = try f.mul(alloc, &three, &x2);
        defer {
            var t = tx2;
            t.deinit();
        }
        const z2 = try f.mul(alloc, &p.z, &p.z);
        defer {
            var t = z2;
            t.deinit();
        }
        const z4 = try f.mul(alloc, &z2, &z2);
        defer {
            var t = z4;
            t.deinit();
        }
        const az4 = try f.mul(alloc, &self.a, &z4);
        defer {
            var t = az4;
            t.deinit();
        }
        const m = try f.add(alloc, &tx2, &az4);
        defer {
            var t = m;
            t.deinit();
        }
        const y2 = try f.mul(alloc, &p.y, &p.y);
        defer {
            var t = y2;
            t.deinit();
        }
        var four = try Big.initSet(alloc, 4);
        defer four.deinit();
        var two = try Big.initSet(alloc, 2);
        defer two.deinit();
        var eight = try Big.initSet(alloc, 8);
        defer eight.deinit();
        const xy2 = try f.mul(alloc, &p.x, &y2);
        defer {
            var t = xy2;
            t.deinit();
        }
        const s = try f.mul(alloc, &four, &xy2);
        defer {
            var t = s;
            t.deinit();
        }
        const m2 = try f.mul(alloc, &m, &m);
        defer {
            var t = m2;
            t.deinit();
        }
        const s2 = try f.mul(alloc, &two, &s);
        defer {
            var t = s2;
            t.deinit();
        }
        const x3 = try f.sub(alloc, &m2, &s2);
        errdefer {
            var t = x3;
            t.deinit();
        }
        const s_x3 = try f.sub(alloc, &s, &x3);
        defer {
            var t = s_x3;
            t.deinit();
        }
        const m_s = try f.mul(alloc, &m, &s_x3);
        defer {
            var t = m_s;
            t.deinit();
        }
        const y4 = try f.mul(alloc, &y2, &y2);
        defer {
            var t = y4;
            t.deinit();
        }
        const ey4 = try f.mul(alloc, &eight, &y4);
        defer {
            var t = ey4;
            t.deinit();
        }
        const y3 = try f.sub(alloc, &m_s, &ey4);
        errdefer {
            var t = y3;
            t.deinit();
        }
        const yz = try f.mul(alloc, &p.y, &p.z);
        defer {
            var t = yz;
            t.deinit();
        }
        const z3 = try f.mul(alloc, &two, &yz);
        return .{ .x = x3, .y = y3, .z = z3 };
    }

    // Suma Jacobiana completa + H==0 (doble o infinito).
    fn addJac(self: *Curve, alloc: std.mem.Allocator, p1: *const Jac, p2: *const Jac) !Jac {
        var z1 = p1.z;
        var z2 = p2.z;
        if (z1.eqlZero()) return .{ .x = try p2.x.clone(), .y = try p2.y.clone(), .z = try p2.z.clone() };
        if (z2.eqlZero()) return .{ .x = try p1.x.clone(), .y = try p1.y.clone(), .z = try p1.z.clone() };
        const f = &self.f;
        const z1z1 = try f.mul(alloc, &p1.z, &p1.z);
        defer {
            var t = z1z1;
            t.deinit();
        }
        const z2z2 = try f.mul(alloc, &p2.z, &p2.z);
        defer {
            var t = z2z2;
            t.deinit();
        }
        const uu1 = try f.mul(alloc, &p1.x, &z2z2);
        defer {
            var t = uu1;
            t.deinit();
        }
        const uu2 = try f.mul(alloc, &p2.x, &z1z1);
        defer {
            var t = uu2;
            t.deinit();
        }
        const z1c = try f.mul(alloc, &p1.z, &z1z1);
        defer {
            var t = z1c;
            t.deinit();
        }
        const z2c = try f.mul(alloc, &p2.z, &z2z2);
        defer {
            var t = z2c;
            t.deinit();
        }
        const s1 = try f.mul(alloc, &p1.y, &z2c);
        defer {
            var t = s1;
            t.deinit();
        }
        const s2 = try f.mul(alloc, &p2.y, &z1c);
        defer {
            var t = s2;
            t.deinit();
        }
        if (uu1.eql(uu2)) {
            if (!s1.eql(s2)) return jacInf(alloc);
            return self.dblJac(alloc, p1);
        }
        const h = try f.sub(alloc, &uu2, &uu1);
        defer {
            var t = h;
            t.deinit();
        }
        const r = try f.sub(alloc, &s2, &s1);
        defer {
            var t = r;
            t.deinit();
        }
        const h2 = try f.mul(alloc, &h, &h);
        defer {
            var t = h2;
            t.deinit();
        }
        const h3 = try f.mul(alloc, &h2, &h);
        defer {
            var t = h3;
            t.deinit();
        }
        const r2 = try f.mul(alloc, &r, &r);
        defer {
            var t = r2;
            t.deinit();
        }
        const uu1h2 = try f.mul(alloc, &uu1, &h2);
        defer {
            var t = uu1h2;
            t.deinit();
        }
        var two = try Big.initSet(alloc, 2);
        defer two.deinit();
        const t2 = try f.mul(alloc, &two, &uu1h2);
        defer {
            var t = t2;
            t.deinit();
        }
        const x3a = try f.sub(alloc, &r2, &h3);
        defer {
            var t = x3a;
            t.deinit();
        }
        const x3 = try f.sub(alloc, &x3a, &t2);
        errdefer {
            var t = x3;
            t.deinit();
        }
        const ux = try f.sub(alloc, &uu1h2, &x3);
        defer {
            var t = ux;
            t.deinit();
        }
        const rux = try f.mul(alloc, &r, &ux);
        defer {
            var t = rux;
            t.deinit();
        }
        const s1h3 = try f.mul(alloc, &s1, &h3);
        defer {
            var t = s1h3;
            t.deinit();
        }
        const y3 = try f.sub(alloc, &rux, &s1h3);
        errdefer {
            var t = y3;
            t.deinit();
        }
        const z1z2 = try f.mul(alloc, &p1.z, &p2.z);
        defer {
            var t = z1z2;
            t.deinit();
        }
        const z3 = try f.mul(alloc, &z1z2, &h);
        return .{ .x = x3, .y = y3, .z = z3 };
    }

    pub fn add(self: *Curve, alloc: std.mem.Allocator, a: *const Point, b: *const Point) !Point {
        var ja = try self.toJac(alloc, a);
        defer ja.deinit();
        var jb = try self.toJac(alloc, b);
        defer jb.deinit();
        var jr = try self.addJac(alloc, &ja, &jb);
        defer jr.deinit();
        return self.fromJac(alloc, &jr);
    }

    pub fn dbl(self: *Curve, alloc: std.mem.Allocator, a: *const Point) !Point {
        var ja = try self.toJac(alloc, a);
        defer ja.deinit();
        var jr = try self.dblJac(alloc, &ja);
        defer jr.deinit();
        return self.fromJac(alloc, &jr);
    }

    /// k*P. Con n conocido reduce mod n; con n==0 usa k directo.
    /// k<0 sin n: niega P y usa -k.
    pub fn mul(self: *Curve, alloc: std.mem.Allocator, k: *const Big, p: *const Point) !Point {
        var neg_p: ?Point = null;
        defer {
            if (neg_p) |*bp| bp.deinit();
        }
        var base_pt: *const Point = p;
        if (self.n.eqlZero() and !k.isPositive() and !k.eqlZero()) {
            neg_p = try self.neg(p);
            base_pt = &neg_p.?;
        }
        var kk: Big = undefined;
        if (self.n.eqlZero()) {
            if (!k.isPositive() and !k.eqlZero()) {
                var zero = try Big.initSet(alloc, 0);
                defer zero.deinit();
                var km = k.*;
                kk = try abi.sub(alloc, &zero, &km);
            } else {
                kk = try k.clone();
            }
        } else {
            kk = try abi.modPos(alloc, k, &self.n);
        }
        defer kk.deinit();
        // Acumulador Jacobiano en infinito (1,1,0).
        var r = Jac{
            .x = try Big.initSet(alloc, 1),
            .y = try Big.initSet(alloc, 1),
            .z = try Big.initSet(alloc, 0),
        };
        errdefer r.deinit();
        var base = try self.toJac(alloc, base_pt);
        defer base.deinit();
        const bits = kk.bitCountAbs();
        var i: usize = bits;
        while (i > 0) {
            i -= 1;
            const d = try self.dblJac(alloc, &r);
            r.deinit();
            r = d;
            var kc = try kk.clone();
            defer kc.deinit();
            var ks = try Big.init(alloc);
            defer ks.deinit();
            try ks.shiftRight(&kc, i);
            if (ks.isOdd()) {
                const s = try self.addJac(alloc, &r, &base);
                r.deinit();
                r = s;
            }
        }
        defer r.deinit();
        return self.fromJac(alloc, &r);
    }

    /// k*G.
    pub fn gen(self: *Curve, alloc: std.mem.Allocator, k: *const Big) !Point {
        var g = try self.generator();
        defer g.deinit();
        return self.mul(alloc, k, &g);
    }

    /// Orden del punto (menor o>0 con o*P=inf). Limite anti-DoS.
    /// Devuelve owned. Error.Range si supera el limite.
    pub fn orderOf(self: *Curve, alloc: std.mem.Allocator, pt: *const Point, limit: u64) !Big {
        if (pt.inf) return Big.initSet(alloc, 1);
        if (!try self.isOnCurve(pt)) return error.Invalid;
        var acc = try pt.clone();
        defer acc.deinit();
        var ord: u64 = 1;
        while (!acc.inf) {
            if (ord >= limit) return error.Range;
            const nxt = try self.add(alloc, &acc, pt);
            acc.deinit();
            acc = nxt;
            ord += 1;
        }
        return Big.initSet(alloc, ord);
    }

    // ----- Codec (longitud segun bitlen(p)) -----

    fn hexFixed(self: *Curve, alloc: std.mem.Allocator, v: *const Big) ![]u8 {
        var t = v.*;
        const h = try t.toString(alloc, 16, .lower);
        defer alloc.free(h);
        const want = self.bytelen * 2;
        if (h.len > want) return error.Invalid;
        if (h.len == want) return alloc.dupe(u8, h);
        var out = try alloc.alloc(u8, want);
        @memset(out[0 .. want - h.len], '0');
        @memcpy(out[want - h.len ..], h);
        return out;
    }

    /// 0x02|03 + x.
    pub fn compress(self: *Curve, alloc: std.mem.Allocator, pt: *const Point) ![]u8 {
        if (pt.inf) return error.Invalid;
        const xh = try self.hexFixed(alloc, &pt.x);
        defer alloc.free(xh);
        var res = try alloc.alloc(u8, 2 + 2 + xh.len);
        res[0] = '0';
        res[1] = 'x';
        res[2] = '0';
        res[3] = if (pt.y.isOdd()) '3' else '2';
        @memcpy(res[4..], xh);
        return res;
    }

    /// 0x04 + x + y.
    pub fn uncompressed(self: *Curve, alloc: std.mem.Allocator, pt: *const Point) ![]u8 {
        if (pt.inf) return error.Invalid;
        const xh = try self.hexFixed(alloc, &pt.x);
        defer alloc.free(xh);
        const yh = try self.hexFixed(alloc, &pt.y);
        defer alloc.free(yh);
        var res = try alloc.alloc(u8, 2 + 2 + xh.len + yh.len);
        res[0] = '0';
        res[1] = 'x';
        res[2] = '0';
        res[3] = '4';
        @memcpy(res[4 .. 4 + xh.len], xh);
        @memcpy(res[4 + xh.len ..], yh);
        return res;
    }

    /// Descomprime 0x02|03 + x (elige y por paridad).
    pub fn decompress(self: *Curve, alloc: std.mem.Allocator, comp: []const u8) !Point {
        var t = comp;
        if (t.len >= 2 and t[0] == '0' and (t[1] == 'x' or t[1] == 'X')) t = t[2..];
        if (t.len != 2 + self.bytelen * 2 or t[0] != '0') return error.Invalid;
        const odd: bool = switch (t[1]) {
            '2' => false,
            '3' => true,
            else => return error.Invalid,
        };
        var x = blk: {
            // abi.parse exige 0x para hex: prefijo temporal (parse copia).
            const hex = t[2..];
            const tmp = try alloc.alloc(u8, hex.len + 2);
            defer alloc.free(tmp);
            tmp[0] = '0';
            tmp[1] = 'x';
            @memcpy(tmp[2..], hex);
            break :blk try abi.parse(alloc, tmp);
        };
        errdefer x.deinit();
        // y^2 = x^3 + a*x + b
        const x2 = try self.f.mul(alloc, &x, &x);
        defer {
            var v = x2;
            v.deinit();
        }
        const x3 = try self.f.mul(alloc, &x2, &x);
        defer {
            var v = x3;
            v.deinit();
        }
        const ax = try self.f.mul(alloc, &self.a, &x);
        defer {
            var v = ax;
            v.deinit();
        }
        const s1 = try self.f.add(alloc, &x3, &ax);
        defer {
            var v = s1;
            v.deinit();
        }
        const rhs = try self.f.add(alloc, &s1, &self.b);
        defer {
            var v = rhs;
            v.deinit();
        }
        var y = try self.f.sqrt(alloc, &rhs);
        errdefer y.deinit();
        if (y.isOdd() != odd) {
            const ny = try self.f.neg(alloc, &y);
            y.deinit();
            y = ny;
        }
        return .{ .x = x, .y = y, .inf = false };
    }
};

test "curva chica: y^2=x^3+2x+3 mod 97" {
    const alloc = std.testing.allocator;
    // G=(3,6)? 36 vs 27+6+3=36 mod 97. Si.
    var c = try Curve.init(alloc, "97", "2", "3", "5", "3", "6");
    defer c.deinit();
    var g = try c.generator();
    defer g.deinit();
    try std.testing.expect(try c.isOnCurve(&g));
    // 5*G debe existir y estar en curva (n=5 inventado: solo chequear on-curve).
    var k = try abi.parse(alloc, "3");
    defer k.deinit();
    var p3 = try c.mul(alloc, &k, &g);
    defer p3.deinit();
    try std.testing.expect(try c.isOnCurve(&p3));
    // add == mul(2): G+G = 2G.
    var p2a = try c.add(alloc, &g, &g);
    defer p2a.deinit();
    var two = try abi.parse(alloc, "2");
    defer two.deinit();
    var p2m = try c.mul(alloc, &two, &g);
    defer p2m.deinit();
    try std.testing.expect(p2a.x.eql(p2m.x) and p2a.y.eql(p2m.y));
    // neg: G + (-G) = inf.
    var ng = try c.neg(&g);
    defer ng.deinit();
    var inf = try c.add(alloc, &g, &ng);
    defer inf.deinit();
    try std.testing.expect(inf.inf);
}

test "secp256k1: G, 2G conocido, n*G=inf" {
    const alloc = std.testing.allocator;
    var c = try Curve.initSecp256k1(alloc);
    defer c.deinit();
    var g = try c.generator();
    defer g.deinit();
    try std.testing.expect(try c.isOnCurve(&g));
    // 2G vector conocido.
    var two = try abi.parse(alloc, "2");
    defer two.deinit();
    var p2 = try c.mul(alloc, &two, &g);
    defer p2.deinit();
    var ex = try abi.parse(alloc, "0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5");
    defer ex.deinit();
    var ey = try abi.parse(alloc, "0x1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A");
    defer ey.deinit();
    try std.testing.expect(p2.x.eql(ex) and p2.y.eql(ey));
    // n*G = infinito.
    var n = try c.n.clone();
    defer n.deinit();
    var inf = try c.mul(alloc, &n, &g);
    defer inf.deinit();
    try std.testing.expect(inf.inf);
    // compresion/descompresion roundtrip de G.
    const comp = try c.compress(alloc, &g);
    defer alloc.free(comp);
    try std.testing.expect(std.mem.startsWith(u8, comp, "0x02") or std.mem.startsWith(u8, comp, "0x03"));
    var back = try c.decompress(alloc, comp);
    defer back.deinit();
    try std.testing.expect(back.x.eql(g.x) and back.y.eql(g.y));
}
