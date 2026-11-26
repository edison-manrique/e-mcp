// ═══════════════════════════════════════════════════════════════════════════
//  source/hash/pbkdf2_sha512.zig — Ultra-Fast PBKDF2-HMAC-SHA512 (RFC 8018)
//  Precomputed HMAC states + pure register word compression for BIP-39 (2048 iter).
//  Zero heap, zero syscalls, 100% register loop.
// ═══════════════════════════════════════════════════════════════════════════

const sha512 = @import("sha512.zig");

/// Precomputed HMAC key states — compute ONCE per mnemonic, reuse across passphrases
pub const PrecomputedKey = struct {
    ipad_state: [8]u64,
    opad_state: [8]u64,
};

/// Precompute the HMAC key states from the password (mnemonic).
pub fn precomputeKey(password: []const u8) PrecomputedKey {
    var key_buf: [128]u8 = @splat(0);
    var key_len: usize = password.len;

    if (password.len > 128) {
        sha512.hash(password, key_buf[0..64]);
        key_len = 64;
    } else {
        @memcpy(key_buf[0..password.len], password);
    }

    var ipad_block: [128]u8 = undefined;
    var opad_block: [128]u8 = undefined;
    for (0..128) |i| {
        const k = if (i < key_len) key_buf[i] else 0;
        ipad_block[i] = k ^ 0x36;
        opad_block[i] = k ^ 0x5c;
    }

    var ipad_state: [8]u64 = sha512.SHA512_IV;
    sha512.compressBlock(&ipad_state, &ipad_block);

    var opad_state: [8]u64 = sha512.SHA512_IV;
    sha512.compressBlock(&opad_state, &opad_block);

    return .{ .ipad_state = ipad_state, .opad_state = opad_state };
}

/// Ultra-Fast derive for standard BIP-39 (no passphrase: salt = "mnemonic")
/// Directly builds U_1 in registers with zero Sha512Context overhead!
pub fn deriveMnemonicNoPassphrase(pkey: *const PrecomputedKey, out: *[64]u8) void {
    const ipad_state = pkey.ipad_state;
    const opad_state = pkey.opad_state;

    // 1. Direct U_1 calculation for salt = "mnemonic" || 0x00000001
    // "mnemonic" (8 bytes) + 0x00000001 (4 bytes) = 12 bytes
    // Total count = 128 (ipad) + 12 = 140 bytes -> 1120 bits = 0x0460
    var w_u1: [16]u64 = undefined;
    w_u1[0] = 0x6d6e656d6f6e6963; // "mnemonic"
    w_u1[1] = 0x0000000180000000; // 0x00000001 + 0x80 padding
    w_u1[2] = 0;
    w_u1[3] = 0;
    w_u1[4] = 0;
    w_u1[5] = 0;
    w_u1[6] = 0;
    w_u1[7] = 0;
    w_u1[8] = 0;
    w_u1[9] = 0;
    w_u1[10] = 0;
    w_u1[11] = 0;
    w_u1[12] = 0;
    w_u1[13] = 0;
    w_u1[14] = 0;
    w_u1[15] = 0x0000000000000460; // 1120 bits

    var st_inner = ipad_state;
    sha512.compressWords(&st_inner, &w_u1);

    var st_outer = opad_state;
    inline for (0..8) |i| {
        w_u1[i] = st_inner[i];
    }
    w_u1[8] = 0x8000000000000000;
    w_u1[9] = 0;
    w_u1[10] = 0;
    w_u1[11] = 0;
    w_u1[12] = 0;
    w_u1[13] = 0;
    w_u1[14] = 0;
    w_u1[15] = 0x0000000000000600; // 1536 bits
    sha512.compressWords(&st_outer, &w_u1);

    // U_1 is in st_outer
    var U: [8]u64 = st_outer;
    var T = U;

    // 2. Hot Loop: U_2 .. U_2048 (100% in registers)
    var w_block: [16]u64 = undefined;
    w_block[8] = 0x8000000000000000;
    w_block[9] = 0;
    w_block[10] = 0;
    w_block[11] = 0;
    w_block[12] = 0;
    w_block[13] = 0;
    w_block[14] = 0;
    w_block[15] = 0x0000000000000600;

    var iter: u32 = 1;
    while (iter < 2048) : (iter += 1) {
        var inner_cur = ipad_state;
        inline for (0..8) |i| {
            w_block[i] = U[i];
        }
        sha512.compressWords(&inner_cur, &w_block);

        var outer_cur = opad_state;
        inline for (0..8) |i| {
            w_block[i] = inner_cur[i];
        }
        sha512.compressWords(&outer_cur, &w_block);

        inline for (0..8) |i| {
            U[i] = outer_cur[i];
            T[i] ^= outer_cur[i];
        }
    }

    // 3. Store 64-byte seed
    inline for (0..8) |i| {
        const val = T[i];
        out[i * 8 + 0] = @intCast((val >> 56) & 0xff);
        out[i * 8 + 1] = @intCast((val >> 48) & 0xff);
        out[i * 8 + 2] = @intCast((val >> 40) & 0xff);
        out[i * 8 + 3] = @intCast((val >> 32) & 0xff);
        out[i * 8 + 4] = @intCast((val >> 24) & 0xff);
        out[i * 8 + 5] = @intCast((val >> 16) & 0xff);
        out[i * 8 + 6] = @intCast((val >> 8)  & 0xff);
        out[i * 8 + 7] = @intCast(val & 0xff);
    }
}

/// Derive with generic salt using precomputed key
pub fn deriveWithPrecomputed(pkey: *const PrecomputedKey, salt: []const u8, iterations: u32, out: *[64]u8) void {
    const ipad_state = pkey.ipad_state;
    const opad_state = pkey.opad_state;

    var inner_ctx = sha512.Sha512Context{
        .state = ipad_state,
        .buffer = undefined,
        .count = 128,
        .buf_len = 0,
    };
    inner_ctx.update(salt);
    const int_be = [4]u8{ 0, 0, 0, 1 };
    inner_ctx.update(&int_be);
    var u_digest: [64]u8 = undefined;
    inner_ctx.final(&u_digest);

    var outer_ctx = sha512.Sha512Context{
        .state = opad_state,
        .buffer = undefined,
        .count = 128,
        .buf_len = 0,
    };
    outer_ctx.update(&u_digest);
    outer_ctx.final(&u_digest);

    var U: [8]u64 = undefined;
    inline for (0..8) |i| {
        const off = i * 8;
        U[i] = (@as(u64, u_digest[off + 0]) << 56) |
               (@as(u64, u_digest[off + 1]) << 48) |
               (@as(u64, u_digest[off + 2]) << 40) |
               (@as(u64, u_digest[off + 3]) << 32) |
               (@as(u64, u_digest[off + 4]) << 24) |
               (@as(u64, u_digest[off + 5]) << 16) |
               (@as(u64, u_digest[off + 6]) << 8)  |
               (@as(u64, u_digest[off + 7]));
    }

    var T = U;

    var w_block: [16]u64 = undefined;
    w_block[8] = 0x8000000000000000;
    w_block[9] = 0;
    w_block[10] = 0;
    w_block[11] = 0;
    w_block[12] = 0;
    w_block[13] = 0;
    w_block[14] = 0;
    w_block[15] = 0x0000000000000600;

    var iter: u32 = 1;
    while (iter < iterations) : (iter += 1) {
        var st_inner = ipad_state;
        inline for (0..8) |i| {
            w_block[i] = U[i];
        }
        sha512.compressWords(&st_inner, &w_block);

        var st_outer = opad_state;
        inline for (0..8) |i| {
            w_block[i] = st_inner[i];
        }
        sha512.compressWords(&st_outer, &w_block);

        inline for (0..8) |i| {
            U[i] = st_outer[i];
            T[i] ^= st_outer[i];
        }
    }

    inline for (0..8) |i| {
        const val = T[i];
        out[i * 8 + 0] = @intCast((val >> 56) & 0xff);
        out[i * 8 + 1] = @intCast((val >> 48) & 0xff);
        out[i * 8 + 2] = @intCast((val >> 40) & 0xff);
        out[i * 8 + 3] = @intCast((val >> 32) & 0xff);
        out[i * 8 + 4] = @intCast((val >> 24) & 0xff);
        out[i * 8 + 5] = @intCast((val >> 16) & 0xff);
        out[i * 8 + 6] = @intCast((val >> 8)  & 0xff);
        out[i * 8 + 7] = @intCast(val & 0xff);
    }
}

/// Generic single-shot derive64
pub fn derive64(password: []const u8, salt: []const u8, iterations: u32, out: *[64]u8) void {
    const pkey = precomputeKey(password);
    deriveWithPrecomputed(&pkey, salt, iterations, out);
}
