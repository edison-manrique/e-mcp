const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════
//  source/hash/sha256.zig — SHA-256 & HMAC-SHA256 via std.crypto
// ═══════════════════════════════════════════════════════════════════════════

pub const BLOCK_BYTES: usize = 64;
pub const HASH_BYTES: usize = 32;

pub const Sha256Context = std.crypto.hash.sha2.Sha256;

/// Streaming update
pub fn update(ctx: *Sha256Context, data: []const u8) void {
    ctx.update(data);
}

/// Finalize
pub fn final(ctx: *Sha256Context, out: *[32]u8) void {
    ctx.final(out);
}

/// One-shot SHA-256
pub fn hash(data: []const u8, out: *[32]u8) void {
    std.crypto.hash.sha2.Sha256.hash(data, out, .{});
}

/// Double SHA-256 (Bitcoin)
pub fn hash2(data: []const u8, out: *[32]u8) void {
    var tmp: [32]u8 = undefined;
    hash(data, &tmp);
    hash(&tmp, out);
}

/// HMAC-SHA256
pub fn hmac(key: []const u8, data: []const u8, out: *[32]u8) void {
    var ctx = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
    ctx.update(data);
    ctx.final(out);
}
