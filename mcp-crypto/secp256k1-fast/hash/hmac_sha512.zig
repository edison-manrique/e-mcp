// ═══════════════════════════════════════════════════════════════════════════
//  source/hash/hmac_sha512.zig — Pure, Ultra-Fast HMAC-SHA512 (RFC 2104)
//  Zero heap, zero std.crypto dependency, pure Zig 0.16.
// ═══════════════════════════════════════════════════════════════════════════

const sha512 = @import("sha512.zig");

pub const BLOCK_BYTES: usize = 128;
pub const MAC_BYTES: usize = 64;

pub const HmacSha512Context = struct {
    inner: sha512.Sha512Context,
    opad: [128]u8,

    pub fn init(key: []const u8) HmacSha512Context {
        var key_buf: [128]u8 = @splat(0);
        var key_len: usize = key.len;
        if (key.len > 128) {
            sha512.hash(key, key_buf[0..64]);
            key_len = 64;
        } else {
            @memcpy(key_buf[0..key.len], key);
        }

        var ipad: [128]u8 = undefined;
        var opad: [128]u8 = undefined;
        for (0..128) |i| {
            const k = if (i < key_len) key_buf[i] else 0;
            ipad[i] = k ^ 0x36;
            opad[i] = k ^ 0x5c;
        }

        var inner = sha512.Sha512Context.init();
        inner.update(&ipad);

        return .{
            .inner = inner,
            .opad = opad,
        };
    }

    pub fn update(self: *HmacSha512Context, data: []const u8) void {
        self.inner.update(data);
    }

    pub fn final(self: *HmacSha512Context, out: *[64]u8) void {
        var inner_hash: [64]u8 = undefined;
        self.inner.final(&inner_hash);

        var outer = sha512.Sha512Context.init();
        outer.update(&self.opad);
        outer.update(&inner_hash);
        outer.final(out);
    }
};

/// One-shot HMAC-SHA512
pub fn hmac(key: []const u8, data: []const u8, out: *[64]u8) void {
    var ctx = HmacSha512Context.init(key);
    ctx.update(data);
    ctx.final(out);
}
