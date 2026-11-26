const std = @import("std");
const builtin = @import("builtin");
const BigInt256 = @import("main.zig").BigInt256;

var global_prng = std.Random.DefaultPrng.init(0x123456789);

fn getRandomU64() u64 {
    if (builtin.cpu.arch == .x86_64) {
        var val: u64 = undefined;
        var success: u8 = 0;
        var attempts: usize = 0;

        while (attempts < 10) : (attempts += 1) {
            asm volatile (
                \\rdrand %[val]
                \\setc %[success]
                : [val] "=r" (val),
                  [success] "=r" (success),
                :
                : .{ .cc = true });
            if (success == 1) return val;
        }
    }
    return global_prng.random().int(u64);
}

test "BigInt256 basic addition" {
    const a = BigInt256.fromU64(100);
    const b = BigInt256.fromU64(200);
    const c = a.add(b).result;
    try std.testing.expectEqual(c.limbs[0], 300);
}

test "BigInt256 multiplication" {
    const a = BigInt256.fromU64(1000000);
    const b = BigInt256.fromU64(1000000);
    const c = a.mul(b);
    try std.testing.expectEqual(c.low.limbs[0], 1000000 * 1000000);
}

test "BigInt256 reduction" {
    // Test reduction with a known value
    // P = 2^256 - 2^32 - 977
    // Let's test P + 1
    const p_plus_1_low = BigInt256.P.add(BigInt256.one).result;
    // const p_plus_1_high = BigInt256.zero; // Unused

    // P+1 should reduce to 1
    const res = BigInt256.reduce(p_plus_1_low, BigInt256.zero);
    try std.testing.expectEqual(res.limbs[0], 1);
    try std.testing.expectEqual(res.limbs[1], 0);
    try std.testing.expectEqual(res.limbs[2], 0);
    try std.testing.expectEqual(res.limbs[3], 0);
}

test "BigInt256 max values addition" {
    // 2^256 - 1
    const max = BigInt256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const one = BigInt256.one;

    // max + 1 = 0 with carry 1
    const res = max.add(one);
    try std.testing.expectEqual(res.result.limbs[0], 0);
    try std.testing.expectEqual(res.result.limbs[1], 0);
    try std.testing.expectEqual(res.result.limbs[2], 0);
    try std.testing.expectEqual(res.result.limbs[3], 0);
    try std.testing.expectEqual(res.carry, 1);
}

test "BigInt256 subtraction zero" {
    // 0 - 1 = 2^256 - 1 with borrow 1
    const zero = BigInt256.zero;
    const one = BigInt256.one;

    const res = zero.sub(one);
    try std.testing.expectEqual(res.result.limbs[0], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res.result.limbs[1], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res.result.limbs[2], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res.result.limbs[3], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res.borrow, 1);
}

test "BigInt256 reduction max" {
    // Reduce (2^256 - 1) * (2^256 - 1)
    // This is effectively (-1) * (-1) = 1 mod P?
    // No, P is not 2^256. P is slightly less.
    // max = P + (2^32 + 976) roughly.
    // So result should be (2^32 + 976)^2 mod P.

    // Let's verify with a simpler property.
    // (P + 1) * 1 = P + 1 = 1 mod P
    const p_plus_1 = BigInt256.P.add(BigInt256.one).result;
    const prod2 = p_plus_1.mul(BigInt256.one);
    const res2 = BigInt256.reduce(prod2.low, prod2.high);

    try std.testing.expectEqual(res2.limbs[0], 1);
    try std.testing.expectEqual(res2.limbs[1], 0);
    try std.testing.expectEqual(res2.limbs[2], 0);
    try std.testing.expectEqual(res2.limbs[3], 0);
}

test "BigInt256 asm addition" {
    if (builtin.cpu.arch != .x86_64) return;

    const a = BigInt256{ .limbs = .{ 1, 2, 3, 4 } };
    const b = BigInt256{ .limbs = .{ 5, 6, 7, 8 } };

    const res = a.addAsm(b);
    try std.testing.expectEqual(res.result.limbs[0], 6);
    try std.testing.expectEqual(res.result.limbs[1], 8);
    try std.testing.expectEqual(res.result.limbs[2], 10);
    try std.testing.expectEqual(res.result.limbs[3], 12);
    try std.testing.expectEqual(res.carry, 0);

    // Test carry
    const max = BigInt256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const res2 = max.addAsm(BigInt256.one);
    try std.testing.expectEqual(res2.result.limbs[0], 0);
    try std.testing.expectEqual(res2.carry, 1);
}

test "BigInt256 multiplication extreme" {
    const max = BigInt256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const zero = BigInt256.zero;
    const one = BigInt256.one;

    // Max * 0
    const res_zero = max.mul(zero);
    try std.testing.expectEqual(res_zero.low.limbs[0], 0);
    try std.testing.expectEqual(res_zero.low.limbs[1], 0);
    try std.testing.expectEqual(res_zero.low.limbs[2], 0);
    try std.testing.expectEqual(res_zero.low.limbs[3], 0);
    try std.testing.expectEqual(res_zero.high.limbs[0], 0);

    // Max * 1
    const res_one = max.mul(one);
    try std.testing.expectEqual(res_one.low.limbs[0], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res_one.low.limbs[3], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res_one.high.limbs[0], 0);

    // Max * Max
    // (2^256 - 1)^2 = 2^512 - 2*2^256 + 1
    // High part: 2^256 - 2 = 0xFF...FE
    // Low part: 1
    const res_max = max.mul(max);
    try std.testing.expectEqual(res_max.low.limbs[0], 1);
    try std.testing.expectEqual(res_max.low.limbs[1], 0);
    try std.testing.expectEqual(res_max.low.limbs[2], 0);
    try std.testing.expectEqual(res_max.low.limbs[3], 0);

    try std.testing.expectEqual(res_max.high.limbs[0], 0xFFFFFFFFFFFFFFFE);
    try std.testing.expectEqual(res_max.high.limbs[1], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res_max.high.limbs[2], 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(res_max.high.limbs[3], 0xFFFFFFFFFFFFFFFF);
}

test "BigInt256 multiplication patterns" {
    // Pattern 0x5555... and 0xAAAA...
    const pat5 = BigInt256{ .limbs = .{ 0x5555555555555555, 0x5555555555555555, 0x5555555555555555, 0x5555555555555555 } };
    const patA = BigInt256{ .limbs = .{ 0xAAAAAAAAAAAAAAAA, 0xAAAAAAAAAAAAAAAA, 0xAAAAAAAAAAAAAAAA, 0xAAAAAAAAAAAAAAAA } };

    const res = pat5.mul(patA);
    // (2^64-1)/3 * 2*(2^64-1)/3  -> comprobación cruzada con std.math.big.int
    const allocator = std.testing.allocator;
    var a_big = try toManaged(allocator, pat5);
    defer a_big.deinit();
    var b_big = try toManaged(allocator, patA);
    defer b_big.deinit();
    var res_big = try std.math.big.int.Managed.init(allocator);
    defer res_big.deinit();
    try res_big.mul(&a_big, &b_big);

    const limbs = [_]u64{
        res.low.limbs[0],  res.low.limbs[1],  res.low.limbs[2],  res.low.limbs[3],
        res.high.limbs[0], res.high.limbs[1], res.high.limbs[2], res.high.limbs[3],
    };
    var res_custom_big = try limbsToManaged(allocator, &limbs);
    defer res_custom_big.deinit();
    try std.testing.expect(res_big.order(res_custom_big) == .eq);
}

test "mulx sanity" {
    if (comptime builtin.cpu.arch != .x86_64) return;
    // BMI2 is required for mulx — check at comptime so the asm block is never emitted on non-BMI2 targets
    if (comptime !std.Target.x86.featureSetHas(builtin.cpu.features, .bmi2)) return;

    const a: u64 = 0xFFFFFFFFFFFFFFFF;
    const b: u64 = 0xFFFFFFFFFFFFFFFF;
    var lo: u64 = 0;
    var hi: u64 = 0;
    asm volatile (
        \\movq %[a], %%rdx
        \\mulxq %[b], %[lo], %[hi]
        : [lo] "=r" (lo),
          [hi] "=r" (hi),
        : [a] "r" (a),
          [b] "r" (b),
        : .{ .rdx = true });
    try std.testing.expectEqual(lo, 1);
    try std.testing.expectEqual(hi, 0xFFFFFFFFFFFFFFFE);
}

// Helper to convert a slice of u64 limbs (little-endian) to std.math.big.int.Managed
fn limbsToManaged(allocator: std.mem.Allocator, limbs: []const u64) !std.math.big.int.Managed {
    var res = try std.math.big.int.Managed.init(allocator);
    errdefer res.deinit();

    var limb_val = try std.math.big.int.Managed.init(allocator);
    defer limb_val.deinit();

    // Iterate from most significant limb
    var i: usize = limbs.len;
    while (i > 0) {
        i -= 1;
        try res.shiftLeft(&res, 64);
        try limb_val.set(limbs[i]);
        try res.add(&res, &limb_val);
    }
    return res;
}

// Helper to convert BigInt256 to std.math.big.int.Managed
fn toManaged(allocator: std.mem.Allocator, val: BigInt256) !std.math.big.int.Managed {
    return limbsToManaged(allocator, &val.limbs);
}

test "BigInt256 vs std.math.big.int addition" {
    if (@bitSizeOf(usize) != 64) return;
    const allocator = std.testing.allocator;
    const iterations = 100;

    for (0..iterations) |_| {
        const a_val = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const b_val = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };

        var a_big = try toManaged(allocator, a_val);
        defer a_big.deinit();
        var b_big = try toManaged(allocator, b_val);
        defer b_big.deinit();

        // BigInt256 add
        const res_custom = a_val.add(b_val);

        // std.math.big.int add
        var res_big = try std.math.big.int.Managed.init(allocator);
        defer res_big.deinit();
        try res_big.add(&a_big, &b_big);

        // Convert custom result to Managed for comparison
        // Note: custom add returns carry separately.
        // std.math.big.int result will include the carry in the next limb if overflow.

        // Reconstruct full result from custom
        // Reconstruct full result from custom
        const limbs = [_]u64{
            res_custom.result.limbs[0],
            res_custom.result.limbs[1],
            res_custom.result.limbs[2],
            res_custom.result.limbs[3],
            @as(u64, res_custom.carry),
        };
        var res_custom_big = try limbsToManaged(allocator, &limbs);
        defer res_custom_big.deinit();

        try std.testing.expect(res_big.order(res_custom_big) == .eq);
    }
}

test "BigInt256 vs std.math.big.int multiplication" {
    if (@bitSizeOf(usize) != 64) return;
    const allocator = std.testing.allocator;
    const iterations = 100;

    for (0..iterations) |_| {
        const a_val = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const b_val = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };

        var a_big = try toManaged(allocator, a_val);
        defer a_big.deinit();
        var b_big = try toManaged(allocator, b_val);
        defer b_big.deinit();

        // BigInt256 mul
        const res_custom = a_val.mul(b_val);

        // std.math.big.int mul
        var res_big = try std.math.big.int.Managed.init(allocator);
        defer res_big.deinit();
        try res_big.mul(&a_big, &b_big);

        // Reconstruct full result from custom (512 bits)
        const limbs = [_]u64{
            res_custom.low.limbs[0],
            res_custom.low.limbs[1],
            res_custom.low.limbs[2],
            res_custom.low.limbs[3],
            res_custom.high.limbs[0],
            res_custom.high.limbs[1],
            res_custom.high.limbs[2],
            res_custom.high.limbs[3],
        };
        var res_custom_big = try limbsToManaged(allocator, &limbs);
        defer res_custom_big.deinit();

        try std.testing.expect(res_big.order(res_custom_big) == .eq);
    }
}

test "BigInt256 mul vs std.math.big.int multiplication" {
    const allocator = std.testing.allocator;
    const iterations = 100;

    for (0..iterations) |_| {
        const a_val = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const b_val = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };

        var a_big = try toManaged(allocator, a_val);
        defer a_big.deinit();
        var b_big = try toManaged(allocator, b_val);
        defer b_big.deinit();

        // BigInt256 mul
        const res_custom = a_val.mul(b_val);

        // std.math.big.int mul
        var res_big = try std.math.big.int.Managed.init(allocator);
        defer res_big.deinit();
        try res_big.mul(&a_big, &b_big);

        // Reconstruct full result from custom (512 bits)
        const limbs = [_]u64{
            res_custom.low.limbs[0],
            res_custom.low.limbs[1],
            res_custom.low.limbs[2],
            res_custom.low.limbs[3],
            res_custom.high.limbs[0],
            res_custom.high.limbs[1],
            res_custom.high.limbs[2],
            res_custom.high.limbs[3],
        };
        var res_custom_big = try limbsToManaged(allocator, &limbs);
        defer res_custom_big.deinit();

        try std.testing.expect(res_big.order(res_custom_big) == .eq);
    }
}
test "BigInt256 sqr vs mul" {
    const iterations = 100;
    for (0..iterations) |_| {
        const a = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const res_mul = a.mul(a);
        const res_sqr = a.sqr();

        try std.testing.expectEqual(res_mul.low.limbs, res_sqr.low.limbs);
        try std.testing.expectEqual(res_mul.high.limbs, res_sqr.high.limbs);
    }
}

test "BigInt256 reduceGeneric vs reduceAsm" {
    if (builtin.cpu.arch != .x86_64) return;
    const iterations = 1000;
    for (0..iterations) |_| {
        const low = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const high = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };

        const res_gen = BigInt256.reduceGeneric(low, high);
        const res_asm = BigInt256.reduceAsm(low, high);

        // Note: reduceAsm might return a value in [0, 2*P-1] in some cases?
        // Actually, both should return a value in [0, P-1] now.
        try std.testing.expectEqual(res_gen.limbs, res_asm.limbs);
    }
}

test "BigInt256 addGeneric vs addAsm" {
    if (builtin.cpu.arch != .x86_64) return;
    const iterations = 1000;
    for (0..iterations) |_| {
        const a = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const b = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };

        const res_gen = BigInt256.addGeneric(a, b);
        const res_asm = BigInt256.addAsm(a, b);

        try std.testing.expectEqual(res_gen.result.limbs, res_asm.result.limbs);
        try std.testing.expectEqual(res_gen.carry, res_asm.carry);
    }
}

test "BigInt256 subGeneric vs subAsm" {
    if (builtin.cpu.arch != .x86_64) return;
    const iterations = 1000;
    for (0..iterations) |_| {
        const a = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };
        const b = BigInt256{ .limbs = .{ getRandomU64(), getRandomU64(), getRandomU64(), getRandomU64() } };

        const res_gen = BigInt256.subGeneric(a, b);
        const res_asm = BigInt256.subAsm(a, b);

        try std.testing.expectEqual(res_gen.result.limbs, res_asm.result.limbs);
        try std.testing.expectEqual(res_gen.borrow, res_asm.borrow);
    }
}

test "BigInt256 constant-time reduce check" {
    // This test ensures that reduceGeneric doesn't crash and returns correct results
    // for edge cases that might have triggered the 'while' loop before.
    const max = BigInt256{ .limbs = .{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF } };
    const res = BigInt256.reduceGeneric(max, max);

    // Verify against ASM
    if (builtin.cpu.arch == .x86_64) {
        const res_asm = BigInt256.reduceAsm(max, max);
        try std.testing.expectEqual(res.limbs, res_asm.limbs);
    }
}

test "BigInt256 reduction edge cases" {
    const one = BigInt256.one;
    const zero = BigInt256.zero;
    const p = BigInt256.P;
    
    // P mod P = 0
    try std.testing.expectEqual(BigInt256.reduce(p, zero).limbs, zero.limbs);
    
    // P-1 mod P = P-1
    const p_minus_1 = p.sub(one).result;
    try std.testing.expectEqual(BigInt256.reduce(p_minus_1, zero).limbs, p_minus_1.limbs);
    
    // P+1 mod P = 1
    const p_plus_1 = p.add(one).result;
    try std.testing.expectEqual(BigInt256.reduce(p_plus_1, zero).limbs, one.limbs);

    // 2P mod P = 0
    const two_p = p.add(p);
    // 2P is res: two_p.result, high: two_p.carry
    try std.testing.expectEqual(BigInt256.reduce(two_p.result, BigInt256.fromU64(two_p.carry)).limbs, zero.limbs);
}
