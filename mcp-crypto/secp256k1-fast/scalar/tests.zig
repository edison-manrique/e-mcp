const std = @import("std");
const Scalar256 = @import("main.zig").Scalar256;

test "Scalar256 basic addition" {
    const a = Scalar256.fromU64(100);
    const b = Scalar256.fromU64(200);
    const c = a.add(b);
    try std.testing.expectEqual(c.limbs[0], 300);
}

test "Scalar256 modular addition overflow" {
    // N - 1 + 2 = 1
    const n_minus_1 = Scalar256.N.subRaw(Scalar256.one).result;
    const two = Scalar256.fromU64(2);
    const res = n_minus_1.add(two);
    try std.testing.expectEqual(res.limbs[0], 1);
}

test "Scalar256 multiplication" {
    const a = Scalar256.fromU64(1000000);
    const b = Scalar256.fromU64(1000000);
    const c = a.mul(b);
    try std.testing.expectEqual(c.limbs[0], 1000000 * 1000000);
}

test "Scalar256 inversion" {
    const a = Scalar256.fromU64(123456789);
    const inv = a.invert();
    const res = a.mul(inv);
    // res should be 1
    try std.testing.expectEqual(res.limbs[0], 1);
    try std.testing.expectEqual(res.limbs[1], 0);
    try std.testing.expectEqual(res.limbs[2], 0);
    try std.testing.expectEqual(res.limbs[3], 0);
}
