// ═══════════════════════════════════════════════════════════════════════════
//  source/hash/sha512.zig — Ultra-Fast Register-Optimized SHA-512 (FIPS 180-4)
//  Zero heap, zero memory spill, 100% register loop for PBKDF2/BIP39.
// ═══════════════════════════════════════════════════════════════════════════

pub const BLOCK_BYTES: usize = 128;
pub const HASH_BYTES: usize = 64;

pub const SHA512_IV: [8]u64 = [8]u64{
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
};

pub const SHA512_K = [80]u64{
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
};

inline fn rotr(x: u64, comptime r: u6) u64 {
    const shift: u6 = @truncate(@as(u7, 64) - r);
    return (x >> r) | (x << shift);
}

inline fn sigma0_512(x: u64) u64 {
    return rotr(x, 1) ^ rotr(x, 8) ^ (x >> 7);
}

inline fn sigma1_512(x: u64) u64 {
    return rotr(x, 19) ^ rotr(x, 61) ^ (x >> 6);
}

inline fn Sigma0_512(x: u64) u64 {
    return rotr(x, 28) ^ rotr(x, 34) ^ rotr(x, 39);
}

inline fn Sigma1_512(x: u64) u64 {
    return rotr(x, 14) ^ rotr(x, 18) ^ rotr(x, 41);
}

inline fn Ch64(x: u64, y: u64, z: u64) u64 {
    return z ^ (x & (y ^ z));
}

inline fn Maj64(x: u64, y: u64, z: u64) u64 {
    return (x & y) ^ (z & (x ^ y));
}

/// Fully unrolled in-register 16-word window compression
pub fn compressWords(st: *[8]u64, w_in: *const [16]u64) void {
    var a = st[0];
    var b = st[1];
    var c = st[2];
    var d = st[3];
    var e = st[4];
    var f = st[5];
    var g = st[6];
    var h = st[7];

    var w: [16]u64 = w_in.*;

    // Rounds 0..15
    inline for (0..16) |i| {
        const t1 = h +% Sigma1_512(e) +% Ch64(e, f, g) +% SHA512_K[i] +% w[i];
        const t2 = Sigma0_512(a) +% Maj64(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d +% t1;
        d = c;
        c = b;
        b = a;
        a = t1 +% t2;
    }

    // Rounds 16..79 (4 blocks of 16 rounds with rotating register window)
    var round_idx: usize = 16;
    while (round_idx < 80) : (round_idx += 16) {
        inline for (0..16) |j| {
            const idx = round_idx + j;
            w[j] +%= sigma1_512(w[(j + 14) % 16]) +% w[(j + 9) % 16] +% sigma0_512(w[(j + 1) % 16]);
            const t1 = h +% Sigma1_512(e) +% Ch64(e, f, g) +% SHA512_K[idx] +% w[j];
            const t2 = Sigma0_512(a) +% Maj64(a, b, c);
            h = g;
            g = f;
            f = e;
            e = d +% t1;
            d = c;
            c = b;
            b = a;
            a = t1 +% t2;
        }
    }

    st[0] +%= a;
    st[1] +%= b;
    st[2] +%= c;
    st[3] +%= d;
    st[4] +%= e;
    st[5] +%= f;
    st[6] +%= g;
    st[7] +%= h;
}

/// Compresses a 128-byte raw block (converted from big-endian bytes)
pub fn compressBlock(st: *[8]u64, block: *const [128]u8) void {
    var w: [16]u64 = undefined;
    for (0..16) |i| {
        const offset = i * 8;
        w[i] = (@as(u64, block[offset + 0]) << 56) |
            (@as(u64, block[offset + 1]) << 48) |
            (@as(u64, block[offset + 2]) << 40) |
            (@as(u64, block[offset + 3]) << 32) |
            (@as(u64, block[offset + 4]) << 24) |
            (@as(u64, block[offset + 5]) << 16) |
            (@as(u64, block[offset + 6]) << 8) |
            (@as(u64, block[offset + 7]));
    }
    compressWords(st, &w);
}

pub const Sha512Context = struct {
    state: [8]u64,
    buffer: [128]u8,
    count: u64, // total bytes hashed
    buf_len: usize,

    pub fn init() Sha512Context {
        return .{
            .state = SHA512_IV,
            .buffer = undefined,
            .count = 0,
            .buf_len = 0,
        };
    }

    pub fn update(self: *Sha512Context, data: []const u8) void {
        var pos: usize = 0;
        const len = data.len;
        self.count += len;

        if (self.buf_len > 0) {
            const need = 128 - self.buf_len;
            if (len >= need) {
                @memcpy(self.buffer[self.buf_len..128], data[0..need]);
                compressBlock(&self.state, &self.buffer);
                pos += need;
                self.buf_len = 0;
            } else {
                @memcpy(self.buffer[self.buf_len..][0..len], data[0..len]);
                self.buf_len += len;
                return;
            }
        }

        while (pos + 128 <= len) : (pos += 128) {
            const blk: *const [128]u8 = data[pos..][0..128];
            compressBlock(&self.state, blk);
        }

        const rem = len - pos;
        if (rem > 0) {
            @memcpy(self.buffer[0..rem], data[pos..][0..rem]);
            self.buf_len = rem;
        }
    }

    pub fn final(self: *Sha512Context, out: *[64]u8) void {
        // Pad 0x80
        self.buffer[self.buf_len] = 0x80;
        self.buf_len += 1;

        if (self.buf_len > 112) {
            @memset(self.buffer[self.buf_len..128], 0);
            compressBlock(&self.state, &self.buffer);
            self.buf_len = 0;
        }

        @memset(self.buffer[self.buf_len..112], 0);
        const total_bits = self.count * 8;
        self.buffer[112] = 0;
        self.buffer[113] = 0;
        self.buffer[114] = 0;
        self.buffer[115] = 0;
        self.buffer[116] = 0;
        self.buffer[117] = 0;
        self.buffer[118] = 0;
        self.buffer[119] = 0;
        self.buffer[120] = @intCast((total_bits >> 56) & 0xff);
        self.buffer[121] = @intCast((total_bits >> 48) & 0xff);
        self.buffer[122] = @intCast((total_bits >> 40) & 0xff);
        self.buffer[123] = @intCast((total_bits >> 32) & 0xff);
        self.buffer[124] = @intCast((total_bits >> 24) & 0xff);
        self.buffer[125] = @intCast((total_bits >> 16) & 0xff);
        self.buffer[126] = @intCast((total_bits >> 8) & 0xff);
        self.buffer[127] = @intCast(total_bits & 0xff);

        compressBlock(&self.state, &self.buffer);

        inline for (0..8) |i| {
            const val = self.state[i];
            out[i * 8 + 0] = @intCast((val >> 56) & 0xff);
            out[i * 8 + 1] = @intCast((val >> 48) & 0xff);
            out[i * 8 + 2] = @intCast((val >> 40) & 0xff);
            out[i * 8 + 3] = @intCast((val >> 32) & 0xff);
            out[i * 8 + 4] = @intCast((val >> 24) & 0xff);
            out[i * 8 + 5] = @intCast((val >> 16) & 0xff);
            out[i * 8 + 6] = @intCast((val >> 8) & 0xff);
            out[i * 8 + 7] = @intCast(val & 0xff);
        }
    }
};

/// One-shot SHA-512 hash
pub fn hash(data: []const u8, out: []u8) void {
    var ctx = Sha512Context.init();
    ctx.update(data);
    var digest: [64]u8 = undefined;
    ctx.final(&digest);
    const n = if (out.len < 64) out.len else 64;
    @memcpy(out[0..n], digest[0..n]);
}

pub fn update(ctx: *Sha512Context, data: []const u8) void {
    ctx.update(data);
}

pub fn final(ctx: *Sha512Context, out: *[64]u8) void {
    ctx.final(out);
}
