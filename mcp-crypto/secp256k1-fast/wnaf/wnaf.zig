const std = @import("std");
const scalar = @import("../scalar/root.zig");
const Scalar256 = scalar.Scalar256;

/// ═══════════════════════════════════════════════════════════════════════════
///  source/wnaf/wnaf.zig — Windowed Non-Adjacent Form (wNAF)
/// ═══════════════════════════════════════════════════════════════════════════

pub const WnafResult = struct {
    wnaf: [260]i8,
    len: usize,
};

/// Computes the wNAF representation of a scalar `k` for a given window width
pub fn computeWNAF(k: Scalar256, width: u5) WnafResult {
    var wnaf: [260]i8 = @splat(0);
    var len: usize = 0;
    var a = k;
    const pow2w: u64 = @as(u64, 1) << width;
    const pow2w1: u64 = pow2w >> 1;
    const mask: u64 = pow2w - 1;

    while (!a.isZero()) {
        var mod: i8 = 0;
        if (a.isOdd()) {
            const val = a.bitwiseAndU64(mask);
            mod = @as(i8, @intCast(val));
            if (mod > pow2w1) {
                mod -= @as(i8, @intCast(pow2w));
            }

            if (mod > 0) {
                a = a.subU64(@as(u64, @intCast(mod)));
            } else {
                a = a.addU64(@as(u64, @intCast(-mod)));
            }
        }
        wnaf[len] = mod;
        len += 1;
        a = a.shiftRight(1);
    }
    return .{ .wnaf = wnaf, .len = len };
}
