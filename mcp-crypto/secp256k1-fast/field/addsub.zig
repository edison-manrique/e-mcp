const std = @import("std");
const builtin = @import("builtin");

/// ═══════════════════════════════════════════════════════════════════════════
///  source/field/addsub.zig — 256-bit Addition and Subtraction
/// ═══════════════════════════════════════════════════════════════════════════

pub const AddResult = struct {
    limbs: [4]u64,
    carry: u1,
};

pub const SubResult = struct {
    limbs: [4]u64,
    borrow: u1,
};

/// Addition with carry (dispatches to x86_64 ASM if available)
pub inline fn add(a: [4]u64, b: [4]u64) AddResult {
    if (@inComptime() or comptime (builtin.cpu.arch != .x86_64 or builtin.abi == .msvc)) {
        return addGeneric(a, b);
    }
    return addAsm(a, b);
}

/// Generic multi-precision addition
pub inline fn addGeneric(a: [4]u64, b: [4]u64) AddResult {
    var res: [4]u64 = undefined;
    var carry: u1 = 0;
    var ov: u1 = 0;

    inline for (0..4) |i| {
        res[i], ov = @addWithOverflow(a[i], b[i]);
        if (i > 0) {
            var ov2: u1 = 0;
            res[i], ov2 = @addWithOverflow(res[i], @as(u64, carry));
            ov |= ov2;
        }
        carry = ov;
    }
    return .{ .limbs = res, .carry = carry };
}

/// Assembly-optimized addition for x86_64 using addq/adcq
pub noinline fn addAsm(a: [4]u64, b: [4]u64) AddResult {
    if (@inComptime() or comptime (builtin.cpu.arch != .x86_64 or builtin.abi == .msvc)) {
        return addGeneric(a, b);
    }
    var r0: u64 = undefined;
    var r1: u64 = undefined;
    var r2: u64 = undefined;
    var r3: u64 = undefined;
    var c: u8 = 0;

    asm volatile (
        \\addq %[b0], %[r0]
        \\adcq %[b1], %[r1]
        \\adcq %[b2], %[r2]
        \\adcq %[b3], %[r3]
        \\setc %[c]
        : [r0] "=&r" (r0),
          [r1] "=&r" (r1),
          [r2] "=&r" (r2),
          [r3] "=&r" (r3),
          [c] "=r" (c),
        : [a0] "0" (a[0]),
          [a1] "1" (a[1]),
          [a2] "2" (a[2]),
          [a3] "3" (a[3]),
          [b0] "rme" (b[0]),
          [b1] "rme" (b[1]),
          [b2] "rme" (b[2]),
          [b3] "rme" (b[3]),
        : .{ .cc = true });

    return .{ .limbs = .{ r0, r1, r2, r3 }, .carry = @as(u1, @truncate(c)) };
}

/// Subtraction with borrow (dispatches to x86_64 ASM if available)
pub inline fn sub(a: [4]u64, b: [4]u64) SubResult {
    if (@inComptime() or comptime (builtin.cpu.arch != .x86_64 or builtin.abi == .msvc)) {
        return subGeneric(a, b);
    }
    return subAsm(a, b);
}

/// Generic multi-precision subtraction
pub inline fn subGeneric(a: [4]u64, b: [4]u64) SubResult {
    var res: [4]u64 = undefined;
    var borrow: u1 = 0;
    var ov: u1 = 0;
    inline for (0..4) |i| {
        res[i], ov = @subWithOverflow(a[i], b[i]);
        if (i > 0) {
            var ov2: u1 = 0;
            res[i], ov2 = @subWithOverflow(res[i], @as(u64, borrow));
            ov |= ov2;
        }
        borrow = ov;
    }
    return .{ .limbs = res, .borrow = borrow };
}

/// Assembly-optimized subtraction for x86_64 using subq/sbbq
pub noinline fn subAsm(a: [4]u64, b: [4]u64) SubResult {
    if (@inComptime() or comptime (builtin.cpu.arch != .x86_64 or builtin.abi == .msvc)) {
        return subGeneric(a, b);
    }
    var r0: u64 = undefined;
    var r1: u64 = undefined;
    var r2: u64 = undefined;
    var r3: u64 = undefined;
    var b_out: u8 = 0;
    asm volatile (
        \\subq %[b0], %[r0]
        \\sbbq %[b1], %[r1]
        \\sbbq %[b2], %[r2]
        \\sbbq %[b3], %[r3]
        \\setc %[c]
        : [r0] "=&r" (r0),
          [r1] "=&r" (r1),
          [r2] "=&r" (r2),
          [r3] "=&r" (r3),
          [c] "=r" (b_out),
        : [a0] "0" (a[0]),
          [a1] "1" (a[1]),
          [a2] "2" (a[2]),
          [a3] "3" (a[3]),
          [b0] "rme" (b[0]),
          [b1] "rme" (b[1]),
          [b2] "rme" (b[2]),
          [b3] "rme" (b[3]),
        : .{ .cc = true });
    return .{ .limbs = .{ r0, r1, r2, r3 }, .borrow = @as(u1, @truncate(b_out)) };
}
