const std = @import("std");
const sha256 = @import("sha256.zig");
const ripemd160 = @import("ripemd160.zig");

// ═══════════════════════════════════════════════════════════════════════════
//  source/hash/hash160.zig — Hash160 (RIPEMD160(SHA256(data))) for Bitcoin
// ═══════════════════════════════════════════════════════════════════════════

pub const HASH_BYTES: usize = 20;

/// Fast inline Hash160: SHA256 first, then RIPEMD160
pub fn hash(data: []const u8, out: *[20]u8) void {
    var sha_out: [32]u8 = undefined;
    sha256.hash(data, &sha_out);
    ripemd160.hash(&sha_out, out);
}
