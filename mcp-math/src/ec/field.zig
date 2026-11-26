const std = @import("std");
const abi = @import("../abig/int.zig");
const Big = abi.Big;

// Campo primo Fp de longitud arbitraria sobre abig.
// `p` debe ser primo impar > 2 (no se testea primalidad: es parametro).
// Todas las operaciones devuelven valores en [0, p-1] y son owned (arena).
pub const Field = struct {
    p: Big,

    pub fn init(alloc: std.mem.Allocator, p_str: []const u8) !Field {
        var p = try abi.parse(alloc, p_str);
        errdefer p.deinit();
        var two = try Big.initSet(alloc, 2);
        defer two.deinit();
        if (Big.order(p, two) != .gt or p.isOdd() == false) return error.Invalid;
        return .{ .p = p };
    }

    pub fn deinit(self: *Field) void {
        self.p.deinit();
        self.* = undefined;
    }

    fn mod(self: *Field, alloc: std.mem.Allocator, v: *const Big) !Big {
        var p = self.p;
        return abi.modPos(alloc, v, &p);
    }

    pub fn add(self: *Field, alloc: std.mem.Allocator, a: *const Big, b: *const Big) !Big {
        const s = try abi.add(alloc, a, b);
        defer {
            var x = s;
            x.deinit();
        }
        var p = self.p;
        return abi.modPos(alloc, &s, &p);
    }

    pub fn sub(self: *Field, alloc: std.mem.Allocator, a: *const Big, b: *const Big) !Big {
        const d = try abi.sub(alloc, a, b);
        defer {
            var x = d;
            x.deinit();
        }
        var p = self.p;
        return abi.modPos(alloc, &d, &p);
    }

    pub fn mul(self: *Field, alloc: std.mem.Allocator, a: *const Big, b: *const Big) !Big {
        const p = try abi.mul(alloc, a, b);
        defer {
            var x = p;
            x.deinit();
        }
        var m = self.p;
        return abi.modPos(alloc, &p, &m);
    }

    pub fn neg(self: *Field, alloc: std.mem.Allocator, a: *const Big) !Big {
        var zero = try Big.initSet(alloc, 0);
        defer zero.deinit();
        return self.sub(alloc, &zero, a);
    }

    pub fn inv(self: *Field, alloc: std.mem.Allocator, a: *const Big) !Big {
        var m = self.p;
        return abi.invMod(alloc, a, &m);
    }

    pub fn div(self: *Field, alloc: std.mem.Allocator, a: *const Big, b: *const Big) !Big {
        const ib = try self.inv(alloc, b);
        defer {
            var x = ib;
            x.deinit();
        }
        return self.mul(alloc, a, &ib);
    }

    pub fn pow(self: *Field, alloc: std.mem.Allocator, a: *const Big, e: *const Big) !Big {
        var m = self.p;
        return abi.powMod(alloc, a, e, &m);
    }

    /// Legendre: 0 si a=0, 1 si residuo, -1 si no-residuo.
    pub fn legendre(self: *Field, alloc: std.mem.Allocator, a: *const Big) !i8 {
        var z = try abi.modPos(alloc, a, &self.p);
        defer z.deinit();
        if (z.eqlZero()) return 0;
        var half = try self.halfP(alloc);
        defer half.deinit();
        const l = try self.pow(alloc, &z, &half);
        defer {
            var x = l;
            x.deinit();
        }
        var one = try Big.initSet(alloc, 1);
        defer one.deinit();
        if (l.eql(one)) return 1;
        return -1;
    }

    fn halfP(self: *Field, alloc: std.mem.Allocator) !Big {
        var one = try Big.initSet(alloc, 1);
        defer one.deinit();
        var t = try abi.sub(alloc, &self.p, &one);
        defer t.deinit();
        var q = try Big.init(alloc);
        errdefer q.deinit();
        var r = try Big.init(alloc);
        defer r.deinit();
        var two = try Big.initSet(alloc, 2);
        defer two.deinit();
        var tt = t;
        try q.divTrunc(&r, &tt, &two);
        return q;
    }

    /// Raiz cuadrada mod p. Error.NoResidue si no existe.
    /// Via rapida si p % 4 == 3, si no Tonelli-Shanks generico.
    pub fn sqrt(self: *Field, alloc: std.mem.Allocator, a: *const Big) !Big {
        var n = try abi.modPos(alloc, a, &self.p);
        defer n.deinit();
        if (n.eqlZero()) {
            const z = try Big.initSet(alloc, 0);
            return z;
        }
        if (try self.legendre(alloc, &n) != 1) return error.NoResidue;
        // p % 4 == 3 ?
        var four = try Big.initSet(alloc, 4);
        defer four.deinit();
        var q4 = try Big.init(alloc);
        defer q4.deinit();
        var r4 = try Big.init(alloc);
        defer r4.deinit();
        var pp = self.p;
        try q4.divTrunc(&r4, &pp, &four);
        const r4v = try r4.toInt(u64);
        if (r4v == 3) {
            // n^((p+1)/4)
            var e = try self.pPlus1Div4(alloc);
            defer e.deinit();
            return self.pow(alloc, &n, &e);
        }
        return self.tonelliShanks(alloc, &n);
    }

    fn pPlus1Div4(self: *Field, alloc: std.mem.Allocator) !Big {
        var one = try Big.initSet(alloc, 1);
        defer one.deinit();
        var t = try abi.add(alloc, &self.p, &one);
        defer t.deinit();
        var q = try Big.init(alloc);
        errdefer q.deinit();
        var r = try Big.init(alloc);
        defer r.deinit();
        var four = try Big.initSet(alloc, 4);
        defer four.deinit();
        var tt = t;
        try q.divTrunc(&r, &tt, &four);
        return q;
    }

    fn tonelliShanks(self: *Field, alloc: std.mem.Allocator, n: *const Big) !Big {
        var one = try Big.initSet(alloc, 1);
        defer one.deinit();
        var two = try Big.initSet(alloc, 2);
        defer two.deinit();
        // p - 1 = q * 2^s con q impar.
        var q = try abi.sub(alloc, &self.p, &one);
        defer q.deinit();
        var s: u32 = 0;
        while (true) {
            var qq = try Big.init(alloc);
            var rr = try Big.init(alloc);
            defer rr.deinit();
            var qv = q;
            try qq.divTrunc(&rr, &qv, &two);
            const even = rr.eqlZero();
            if (!even) {
                qq.deinit();
                break;
            }
            q.deinit();
            q = qq;
            s += 1;
        }
        // z = primer no-residuo (prueba 2, 3, ...).
        var z = try Big.initSet(alloc, 2);
        defer z.deinit();
        while (true) {
            if (try self.legendre(alloc, &z) == -1) break;
            const nz = try abi.add(alloc, &z, &one);
            z.deinit();
            z = nz;
        }
        var c = try self.pow(alloc, &z, &q);
        defer c.deinit();
        // x = n^((q+1)/2)
        var qp1 = try abi.add(alloc, &q, &one);
        defer qp1.deinit();
        var xh = try Big.init(alloc);
        var xr = try Big.init(alloc);
        defer xr.deinit();
        var qv2 = qp1;
        try xh.divTrunc(&xr, &qv2, &two);
        defer xh.deinit();
        var x = try self.pow(alloc, n, &xh);
        errdefer x.deinit();
        var t = try self.pow(alloc, n, &q);
        errdefer t.deinit();
        var m = s;
        while (!t.eql(one)) {
            // i = menor con t^(2^i) == 1, 1 <= i < m.
            var tt = try t.clone();
            defer tt.deinit();
            var i: u32 = 0;
            while (i < m) : (i += 1) {
                const sq = try self.mul(alloc, &tt, &tt);
                tt.deinit();
                tt = sq;
                if (tt.eql(one)) break;
            }
            i += 1; // i cuenta squarings desde 1
            if (i >= m) return error.NoResidue; // no deberia pasar (legendre=1)
            // b = c^(2^(m-i-1))
            var b = try c.clone();
            defer b.deinit();
            var j: u32 = 0;
            while (j < m - i - 1) : (j += 1) {
                const nb = try self.mul(alloc, &b, &b);
                b.deinit();
                b = nb;
            }
            const nx = try self.mul(alloc, &x, &b);
            x.deinit();
            x = nx;
            const bsq = try self.mul(alloc, &b, &b);
            c.deinit();
            c = bsq;
            const nt = try self.mul(alloc, &t, &c);
            t.deinit();
            t = nt;
            m = i;
        }
        t.deinit();
        return x;
    }
};

test "field primo chico: inv, div, sqrt (p=13, p%4==1)" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, "13");
    defer f.deinit();
    var a = try abi.parse(alloc, "5");
    defer a.deinit();
    var b = try abi.parse(alloc, "3");
    defer b.deinit();
    var iv = try f.inv(alloc, &a); // 5^-1 = 8 mod 13
    defer iv.deinit();
    try std.testing.expect((try iv.toInt(i64)) == 8);
    var q = try f.div(alloc, &a, &b); // 5/3 = 5*9=45=6 mod 13
    defer q.deinit();
    try std.testing.expect((try q.toInt(i64)) == 6);
    var n = try abi.parse(alloc, "9");
    defer n.deinit();
    var r = try f.sqrt(alloc, &n); // +-3
    defer r.deinit();
    const rv = try r.toInt(i64);
    try std.testing.expect(rv == 3 or rv == 10);
    var nr = try abi.parse(alloc, "7"); // no-residuo mod 13
    defer nr.deinit();
    try std.testing.expectError(error.NoResidue, f.sqrt(alloc, &nr));
}

test "field: via rapida p%4==3 (p=101)" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, "101");
    defer f.deinit();
    var n = try abi.parse(alloc, "25");
    defer n.deinit();
    var r = try f.sqrt(alloc, &n); // +-5
    defer r.deinit();
    const rv = try r.toInt(i64);
    try std.testing.expect(rv == 5 or rv == 96);
}

test "field: Tonelli-Shanks p%4==1 (p=17)" {
    const alloc = std.testing.allocator;
    var f = try Field.init(alloc, "17");
    defer f.deinit();
    var n = try abi.parse(alloc, "2"); // 6^2=36=2 mod 17
    defer n.deinit();
    var r = try f.sqrt(alloc, &n);
    defer r.deinit();
    const rv = try r.toInt(i64);
    try std.testing.expect(rv == 6 or rv == 11);
}
