const std = @import("std");
const constants = @import("../constants.zig");
const addsub = @import("addsub.zig");
const mulmod = @import("mulmod.zig");
const raw = @import("raw.zig");

/// ═══════════════════════════════════════════════════════════════════════════
///  source/scalar/reduce.zig — Modular Reduction mod N for Scalar256
/// ═══════════════════════════════════════════════════════════════════════════

const C_LIMBS = [4]u64{
    0x402DA1732FC9BEBF,
    0x4551231950B75FC4,
    0x0000000000000001,
    0x0000000000000000,
};

/// Modular reduction for secp256k1 scalar (low, high) mod N
pub fn reduce(low: [4]u64, high: [4]u64) [4]u64 {
    const hc = mulScalarC(high);

    var res = low;
    var carry_acc: u64 = 0;

    var rc = addsub.addRaw(res, hc.low);
    res = rc.limbs;
    carry_acc += rc.carry;

    var h2 = hc.high;
    var rc2 = addsub.addRaw(h2, .{ carry_acc, 0, 0, 0 });
    h2 = rc2.limbs;

    const h2c = mulScalarC(h2);

    rc = addsub.addRaw(res, h2c.low);
    res = rc.limbs;
    carry_acc = rc.carry;

    var h3 = h2c.high;
    rc2 = addsub.addRaw(h3, .{ carry_acc, 0, 0, 0 });
    h3 = rc2.limbs;

    const h3c = mulScalarC(h3);

    rc = addsub.addRaw(res, h3c.low);
    res = rc.limbs;

    if (rc.carry > 0) {
        rc = addsub.addRaw(res, C_LIMBS);
        res = rc.limbs;
    }

    while (raw.isGreaterOrEqual(res, constants.N_LIMBS)) {
        res = addsub.subRaw(res, constants.N_LIMBS).limbs;
    }

    return res;
}

fn mulScalarC(a: [4]u64) mulmod.WideMulResult {
    return mulmod.mulWide(a, C_LIMBS);
}
