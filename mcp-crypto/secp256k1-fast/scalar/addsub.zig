const std = @import("std");
const constants = @import("../constants.zig");
const raw = @import("raw.zig");

/// ═══════════════════════════════════════════════════════════════════════════
///  source/scalar/addsub.zig — 256-bit Scalar Addition & Subtraction mod N
/// ═══════════════════════════════════════════════════════════════════════════
pub const AddRawResult = struct {
    limbs: [4]u64,
    carry: u1,
};

pub const SubRawResult = struct {
    limbs: [4]u64,
    borrow: u1,
};

pub inline fn addRaw(a: [4]u64, b: [4]u64) AddRawResult {
    var res = [4]u64{ 0, 0, 0, 0 };
    var carry: u1 = 0;
    var ov: u1 = 0;

    res[0], ov = @addWithOverflow(a[0], b[0]);
    carry = ov;

    res[1], ov = @addWithOverflow(a[1], b[1]);
    var ov2: u1 = 0;
    res[1], ov2 = @addWithOverflow(res[1], @as(u64, carry));
    carry = ov | ov2;

    res[2], ov = @addWithOverflow(a[2], b[2]);
    res[2], ov2 = @addWithOverflow(res[2], @as(u64, carry));
    carry = ov | ov2;

    res[3], ov = @addWithOverflow(a[3], b[3]);
    res[3], ov2 = @addWithOverflow(res[3], @as(u64, carry));
    carry = ov | ov2;

    return .{ .limbs = res, .carry = carry };
}

/// Modular Addition (a + b) mod N
pub fn add(a: [4]u64, b: [4]u64) [4]u64 {
    const res_raw = addRaw(a, b);
    var res = res_raw.limbs;

    if (res_raw.carry == 1 or raw.isGreaterOrEqual(res, constants.N_LIMBS)) {
        res = subRaw(res, constants.N_LIMBS).limbs;
    }
    return res;
}

pub inline fn subRaw(a: [4]u64, b: [4]u64) SubRawResult {
    var res = [4]u64{ 0, 0, 0, 0 };
    var borrow: u1 = 0;
    var ov: u1 = 0;

    res[0], ov = @subWithOverflow(a[0], b[0]);
    borrow = ov;

    res[1], ov = @subWithOverflow(a[1], b[1]);
    var ov2: u1 = 0;
    res[1], ov2 = @subWithOverflow(res[1], @as(u64, borrow));
    borrow = ov | ov2;

    res[2], ov = @subWithOverflow(a[2], b[2]);
    res[2], ov2 = @subWithOverflow(res[2], @as(u64, borrow));
    borrow = ov | ov2;

    res[3], ov = @subWithOverflow(a[3], b[3]);
    res[3], ov2 = @subWithOverflow(res[3], @as(u64, borrow));
    borrow = ov | ov2;

    return .{ .limbs = res, .borrow = borrow };
}

/// Modular Subtraction (a - b) mod N
pub fn sub(a: [4]u64, b: [4]u64) [4]u64 {
    const res_raw = subRaw(a, b);
    var res = res_raw.limbs;

    if (res_raw.borrow == 1) {
        res = addRaw(res, constants.N_LIMBS).limbs;
    }
    return res;
}
