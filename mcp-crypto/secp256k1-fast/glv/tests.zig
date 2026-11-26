const std = @import("std");
const glv = @import("root.zig");
const scalar = @import("../scalar/root.zig");
const generator = @import("../generator/root.zig");
const constants = @import("../constants.zig");
const testing = std.testing;

/// ═══════════════════════════════════════════════════════════════════════════
///  secp256k1-fast/glv/tests.zig — Descomposición GLV y mulGLV
/// ═══════════════════════════════════════════════════════════════════════════
///  Regresión: `decompose` estaba mal (k1 > 2^128 y la identidad no se
///  cumplía), lo que hacía que `mulGLV` devolviera puntos incorrectos.
///  Referencia cruzada: `generator.mulG` (validado por BIP-32/44/86).
/// ═══════════════════════════════════════════════════════════════════════════

const Scalar256 = scalar.Scalar256;
const LAMBDA = Scalar256{ .limbs = constants.LAMBDA_LIMBS };

fn signed(v: Scalar256, neg: bool) Scalar256 {
    return if (neg) Scalar256.N.sub(v) else v;
}

fn fits128(v: Scalar256) bool {
    return v.limbs[2] == 0 and v.limbs[3] == 0;
}

fn expectAffineEq(a: @import("../point/root.zig").Point, b: @import("../point/root.zig").Point) !void {
    const af = a.toAffine();
    const bf = b.toAffine();
    try testing.expectEqualSlices(u64, &af.x.limbs, &bf.x.limbs);
    try testing.expectEqualSlices(u64, &af.y.limbs, &bf.y.limbs);
}

test "glv: identidad ±k1 + λ·(±k2) ≡ k y |k1|,|k2| < 2^128" {
    const boundary = [_]Scalar256{
        Scalar256.one,
        Scalar256.fromU64(2),
        Scalar256.fromU64(3),
        Scalar256.N.sub(Scalar256.one),
        Scalar256.N.sub(Scalar256.fromU64(2)),
        Scalar256.N.shiftRight(1),
        Scalar256.one.shiftLeft(128),
        Scalar256.one.shiftLeft(128).subU64(1),
        Scalar256.one.shiftLeft(127),
        Scalar256.one.shiftLeft(255),
    };

    var seed: u64 = 0x9E3779B97F4A7C15;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var k: Scalar256 = undefined;
        if (i < boundary.len) {
            k = boundary[i];
        } else {
            var b: [32]u8 = undefined;
            for (&b) |*x| {
                seed = seed *% 6364136223846793005 +% 1442695040888963407;
                x.* = @truncate(seed >> 33);
            }
            k = Scalar256.fromBytes(&b);
            if (k.isZero() or k.isGreaterOrEqual(Scalar256.N)) k = Scalar256.one;
        }

        const d = glv.decompose(k);
        try testing.expect(fits128(d.k1));
        try testing.expect(fits128(d.k2));

        const lhs = signed(d.k1, d.neg_k1).add(signed(d.k2, d.neg_k2).mul(LAMBDA));
        try testing.expectEqualSlices(u64, &lhs.limbs, &k.limbs);
    }
}

test "glv: mulGLV coincide con generator.mulG" {
    var seed: u64 = 0x123456789ABCDEF0;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        var b: [32]u8 = undefined;
        for (&b) |*x| {
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            x.* = @truncate(seed >> 33);
        }
        var k = Scalar256.fromBytes(&b);
        if (k.isZero() or k.isGreaterOrEqual(Scalar256.N)) k = Scalar256.one;

        const j = Scalar256.fromU64(@as(u64, i % 7) + 2); // evita j=0
        const base = generator.mulG(j);
        const expected = generator.mulG(k.mul(j));
        try expectAffineEq(glv.mulGLV(base, k), expected);
    }
}

test "glv: casos borde de mulGLV" {
    const one = Scalar256.one;
    const g = generator.mulG(one);
    const two = generator.mulG(Scalar256.fromU64(2));

    try expectAffineEq(glv.mulGLV(g, one), g);
    try expectAffineEq(glv.mulGLV(g, Scalar256.fromU64(2)), two);
    try expectAffineEq(glv.mulGLV(g, Scalar256.N.sub(one)), g.negate());
    try expectAffineEq(glv.mulGLV(g, Scalar256.zero), @import("../point/root.zig").Point.infinity);
}
