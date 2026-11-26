const std = @import("std");
const constants = @import("../constants.zig");
pub const addsub = @import("addsub.zig");
pub const mulmod = @import("mulmod.zig");
pub const reduce_mod = @import("reduce.zig");
pub const inverse_mod = @import("inverse.zig");
pub const raw = @import("raw.zig");
pub const convert = @import("convert.zig");

/// ═══════════════════════════════════════════════════════════════════════════
///  source/scalar/root.zig — Scalar256 Struct & Scalar API
/// ═══════════════════════════════════════════════════════════════════════════
/// Optimized 256-bit Scalar for secp256k1 (modulo N)
pub const Scalar256 = struct {
    limbs: [4]u64,

    /// Curve Order N
    pub const N = Scalar256{ .limbs = constants.N_LIMBS };
    pub const N_MINUS_2 = Scalar256{ .limbs = constants.N_MINUS_2_LIMBS };

    /// Zero value
    pub const zero = Scalar256{ .limbs = .{ 0, 0, 0, 0 } };

    /// One value
    pub const one = Scalar256{ .limbs = .{ 1, 0, 0, 0 } };

    /// Initialize from u64
    pub fn fromU64(val: u64) Scalar256 {
        return Scalar256{ .limbs = convert.fromU64(val) };
    }

    /// Parse from 32 big-endian bytes
    pub fn fromBytes(bytes: *const [32]u8) Scalar256 {
        var limbs: [4]u64 = undefined;
        limbs[3] = std.mem.readInt(u64, bytes[0..8], .big);
        limbs[2] = std.mem.readInt(u64, bytes[8..16], .big);
        limbs[1] = std.mem.readInt(u64, bytes[16..24], .big);
        limbs[0] = std.mem.readInt(u64, bytes[24..32], .big);
        return Scalar256{ .limbs = limbs };
    }

    /// Export to 32 big-endian bytes
    pub fn toBytes(self: Scalar256, out: *[32]u8) void {
        std.mem.writeInt(u64, out[0..8], self.limbs[3], .big);
        std.mem.writeInt(u64, out[8..16], self.limbs[2], .big);
        std.mem.writeInt(u64, out[16..24], self.limbs[1], .big);
        std.mem.writeInt(u64, out[24..32], self.limbs[0], .big);
    }

    /// Addition with carry (raw)
    pub inline fn addRaw(self: Scalar256, other: Scalar256) struct { result: Scalar256, carry: u1 } {
        const res = addsub.addRaw(self.limbs, other.limbs);
        return .{ .result = Scalar256{ .limbs = res.limbs }, .carry = res.carry };
    }

    /// Modular Addition (a + b) mod N
    pub fn add(self: Scalar256, other: Scalar256) Scalar256 {
        return Scalar256{ .limbs = addsub.add(self.limbs, other.limbs) };
    }

    /// Subtraction with borrow (raw)
    pub inline fn subRaw(self: Scalar256, other: Scalar256) struct { result: Scalar256, borrow: u1 } {
        const res = addsub.subRaw(self.limbs, other.limbs);
        return .{ .result = Scalar256{ .limbs = res.limbs }, .borrow = res.borrow };
    }

    /// Modular Subtraction (a - b) mod N
    pub fn sub(self: Scalar256, other: Scalar256) Scalar256 {
        return Scalar256{ .limbs = addsub.sub(self.limbs, other.limbs) };
    }

    /// Full 256x256 -> 512 bit multiplication
    pub inline fn mulWide(self: Scalar256, other: Scalar256) struct { low: Scalar256, high: Scalar256 } {
        const res = mulmod.mulWide(self.limbs, other.limbs);
        return .{
            .low = Scalar256{ .limbs = res.low },
            .high = Scalar256{ .limbs = res.high },
        };
    }

    /// Modular Multiplication (a * b) mod N
    pub fn mul(self: Scalar256, other: Scalar256) Scalar256 {
        const wide = self.mulWide(other);
        return reduce(wide.low, wide.high);
    }

    /// Modular reduction mod N
    pub fn reduce(low: Scalar256, high: Scalar256) Scalar256 {
        return Scalar256{ .limbs = reduce_mod.reduce(low.limbs, high.limbs) };
    }

    pub fn isGreaterOrEqual(self: Scalar256, other: Scalar256) bool {
        return raw.isGreaterOrEqual(self.limbs, other.limbs);
    }

    pub fn isLessThan(self: Scalar256, other: Scalar256) bool {
        return raw.isLessThan(self.limbs, other.limbs);
    }

    /// Modular Exponentiation: self^exp mod N
    pub fn pow(self: Scalar256, exp: Scalar256) Scalar256 {
        return Scalar256{ .limbs = inverse_mod.pow(self.limbs, exp.limbs) };
    }

    /// Modular Inverse: self^(N-2) mod N
    pub fn invert(self: Scalar256) Scalar256 {
        return Scalar256{ .limbs = inverse_mod.invert(self.limbs) };
    }

    pub fn isOdd(self: Scalar256) bool {
        return raw.isOdd(self.limbs);
    }

    pub fn shiftRight(self: Scalar256, bits: u6) Scalar256 {
        return Scalar256{ .limbs = raw.shiftRight(self.limbs, bits) };
    }

    pub fn shiftLeft(self: Scalar256, bits: u9) Scalar256 {
        return Scalar256{ .limbs = raw.shiftLeft(self.limbs, bits) };
    }

    pub fn bitwiseAndU64(self: Scalar256, mask: u64) u64 {
        return raw.bitwiseAndU64(self.limbs, mask);
    }

    pub fn subU64(self: Scalar256, val: u64) Scalar256 {
        return Scalar256{ .limbs = raw.subU64(self.limbs, val) };
    }

    pub fn addU64(self: Scalar256, val: u64) Scalar256 {
        return Scalar256{ .limbs = raw.addU64(self.limbs, val) };
    }

    pub fn isZero(self: Scalar256) bool {
        return raw.isZero(self.limbs);
    }

    pub fn isOne(self: Scalar256) bool {
        return raw.isOne(self.limbs);
    }
};
