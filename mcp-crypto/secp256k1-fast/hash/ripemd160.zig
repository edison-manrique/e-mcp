const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════
//  source/hash/ripemd160.zig — RIPEMD-160 (High Performance, 5-Round Unrolled)
// ═══════════════════════════════════════════════════════════════════════════

pub const BLOCK_BYTES: usize = 64;
pub const HASH_BYTES: usize = 20;

inline fn rotl(x: u32, comptime n: u5) u32 {
    return std.math.rotl(u32, x, n);
}

inline fn f1(x: u32, y: u32, z: u32) u32 {
    return x ^ y ^ z;
}
inline fn f2(x: u32, y: u32, z: u32) u32 {
    return (x & y) | (~x & z);
}
inline fn f3(x: u32, y: u32, z: u32) u32 {
    return (x | ~y) ^ z;
}
inline fn f4(x: u32, y: u32, z: u32) u32 {
    return (x & z) | (y & ~z);
}
inline fn f5(x: u32, y: u32, z: u32) u32 {
    return x ^ (y | ~z);
}

pub const Ripemd160Context = struct {
    state: [5]u32,
    buffer: [64]u8,
    total_len: u64,
    buffer_len: u32,

    pub fn init() Ripemd160Context {
        return Ripemd160Context{
            .state = [5]u32{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 },
            .buffer = undefined,
            .total_len = 0,
            .buffer_len = 0,
        };
    }
};

pub fn compressBlock(st: *[5]u32, block: *const [64]u8) void {
    var h0 = st[0];
    var h1 = st[1];
    var h2 = st[2];
    var h3 = st[3];
    var h4 = st[4];

    var A = h0;
    var B = h1;
    var C = h2;
    var D = h3;
    var E = h4;
    var Ap = h0;
    var Bp = h1;
    var Cp = h2;
    var Dp = h3;
    var Ep = h4;

    var X: [16]u32 = undefined;
    for (0..16) |i| {
        X[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .little);
    }

    // ── Round 1 ──
    A = rotl(A +% f1(B, C, D) +% X[0], 11) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f5(Bp, Cp, Dp) +% X[5] +% 0x50a28be6, 8) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f1(A, B, C) +% X[1], 14) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f5(Ap, Bp, Cp) +% X[14] +% 0x50a28be6, 9) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f1(E, A, B) +% X[2], 15) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f5(Ep, Ap, Bp) +% X[7] +% 0x50a28be6, 9) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f1(D, E, A) +% X[3], 12) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f5(Dp, Ep, Ap) +% X[0] +% 0x50a28be6, 11) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f1(C, D, E) +% X[4], 5) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f5(Cp, Dp, Ep) +% X[9] +% 0x50a28be6, 13) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f1(B, C, D) +% X[5], 8) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f5(Bp, Cp, Dp) +% X[2] +% 0x50a28be6, 15) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f1(A, B, C) +% X[6], 7) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f5(Ap, Bp, Cp) +% X[11] +% 0x50a28be6, 15) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f1(E, A, B) +% X[7], 9) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f5(Ep, Ap, Bp) +% X[4] +% 0x50a28be6, 5) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f1(D, E, A) +% X[8], 11) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f5(Dp, Ep, Ap) +% X[13] +% 0x50a28be6, 7) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f1(C, D, E) +% X[9], 13) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f5(Cp, Dp, Ep) +% X[6] +% 0x50a28be6, 7) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f1(B, C, D) +% X[10], 14) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f5(Bp, Cp, Dp) +% X[15] +% 0x50a28be6, 8) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f1(A, B, C) +% X[11], 15) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f5(Ap, Bp, Cp) +% X[8] +% 0x50a28be6, 11) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f1(E, A, B) +% X[12], 6) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f5(Ep, Ap, Bp) +% X[1] +% 0x50a28be6, 14) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f1(D, E, A) +% X[13], 7) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f5(Dp, Ep, Ap) +% X[10] +% 0x50a28be6, 14) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f1(C, D, E) +% X[14], 9) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f5(Cp, Dp, Ep) +% X[3] +% 0x50a28be6, 12) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f1(B, C, D) +% X[15], 8) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f5(Bp, Cp, Dp) +% X[12] +% 0x50a28be6, 6) +% Ep; Cp = rotl(Cp, 10);

    // ── Round 2 ──
    E = rotl(E +% f2(A, B, C) +% X[7] +% 0x5a827999, 7) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f4(Ap, Bp, Cp) +% X[6] +% 0x5c4dd124, 9) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f2(E, A, B) +% X[4] +% 0x5a827999, 6) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f4(Ep, Ap, Bp) +% X[11] +% 0x5c4dd124, 13) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f2(D, E, A) +% X[13] +% 0x5a827999, 8) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f4(Dp, Ep, Ap) +% X[3] +% 0x5c4dd124, 15) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f2(C, D, E) +% X[1] +% 0x5a827999, 13) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f4(Cp, Dp, Ep) +% X[7] +% 0x5c4dd124, 7) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f2(B, C, D) +% X[10] +% 0x5a827999, 11) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f4(Bp, Cp, Dp) +% X[0] +% 0x5c4dd124, 12) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f2(A, B, C) +% X[6] +% 0x5a827999, 9) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f4(Ap, Bp, Cp) +% X[13] +% 0x5c4dd124, 8) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f2(E, A, B) +% X[15] +% 0x5a827999, 7) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f4(Ep, Ap, Bp) +% X[5] +% 0x5c4dd124, 9) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f2(D, E, A) +% X[3] +% 0x5a827999, 15) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f4(Dp, Ep, Ap) +% X[10] +% 0x5c4dd124, 11) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f2(C, D, E) +% X[12] +% 0x5a827999, 7) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f4(Cp, Dp, Ep) +% X[14] +% 0x5c4dd124, 7) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f2(B, C, D) +% X[0] +% 0x5a827999, 12) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f4(Bp, Cp, Dp) +% X[15] +% 0x5c4dd124, 7) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f2(A, B, C) +% X[9] +% 0x5a827999, 15) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f4(Ap, Bp, Cp) +% X[8] +% 0x5c4dd124, 12) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f2(E, A, B) +% X[5] +% 0x5a827999, 9) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f4(Ep, Ap, Bp) +% X[12] +% 0x5c4dd124, 7) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f2(D, E, A) +% X[2] +% 0x5a827999, 11) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f4(Dp, Ep, Ap) +% X[4] +% 0x5c4dd124, 6) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f2(C, D, E) +% X[14] +% 0x5a827999, 7) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f4(Cp, Dp, Ep) +% X[9] +% 0x5c4dd124, 15) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f2(B, C, D) +% X[11] +% 0x5a827999, 13) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f4(Bp, Cp, Dp) +% X[1] +% 0x5c4dd124, 13) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f2(A, B, C) +% X[8] +% 0x5a827999, 12) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f4(Ap, Bp, Cp) +% X[2] +% 0x5c4dd124, 11) +% Dp; Bp = rotl(Bp, 10);

    // ── Round 3 ──
    D = rotl(D +% f3(E, A, B) +% X[3] +% 0x6ed9eba1, 11) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f3(Ep, Ap, Bp) +% X[15] +% 0x6d703ef3, 9) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f3(D, E, A) +% X[10] +% 0x6ed9eba1, 13) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f3(Dp, Ep, Ap) +% X[5] +% 0x6d703ef3, 7) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f3(C, D, E) +% X[14] +% 0x6ed9eba1, 6) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f3(Cp, Dp, Ep) +% X[1] +% 0x6d703ef3, 15) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f3(B, C, D) +% X[4] +% 0x6ed9eba1, 7) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f3(Bp, Cp, Dp) +% X[3] +% 0x6d703ef3, 11) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f3(A, B, C) +% X[9] +% 0x6ed9eba1, 14) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f3(Ap, Bp, Cp) +% X[7] +% 0x6d703ef3, 8) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f3(E, A, B) +% X[15] +% 0x6ed9eba1, 9) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f3(Ep, Ap, Bp) +% X[14] +% 0x6d703ef3, 6) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f3(D, E, A) +% X[8] +% 0x6ed9eba1, 13) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f3(Dp, Ep, Ap) +% X[6] +% 0x6d703ef3, 6) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f3(C, D, E) +% X[1] +% 0x6ed9eba1, 15) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f3(Cp, Dp, Ep) +% X[9] +% 0x6d703ef3, 14) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f3(B, C, D) +% X[2] +% 0x6ed9eba1, 14) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f3(Bp, Cp, Dp) +% X[11] +% 0x6d703ef3, 12) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f3(A, B, C) +% X[7] +% 0x6ed9eba1, 8) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f3(Ap, Bp, Cp) +% X[8] +% 0x6d703ef3, 13) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f3(E, A, B) +% X[0] +% 0x6ed9eba1, 13) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f3(Ep, Ap, Bp) +% X[12] +% 0x6d703ef3, 5) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f3(D, E, A) +% X[6] +% 0x6ed9eba1, 6) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f3(Dp, Ep, Ap) +% X[2] +% 0x6d703ef3, 14) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f3(C, D, E) +% X[13] +% 0x6ed9eba1, 5) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f3(Cp, Dp, Ep) +% X[10] +% 0x6d703ef3, 13) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f3(B, C, D) +% X[11] +% 0x6ed9eba1, 12) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f3(Bp, Cp, Dp) +% X[0] +% 0x6d703ef3, 13) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f3(A, B, C) +% X[5] +% 0x6ed9eba1, 7) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f3(Ap, Bp, Cp) +% X[4] +% 0x6d703ef3, 7) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f3(E, A, B) +% X[12] +% 0x6ed9eba1, 5) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f3(Ep, Ap, Bp) +% X[13] +% 0x6d703ef3, 5) +% Cp; Ap = rotl(Ap, 10);

    // ── Round 4 ──
    C = rotl(C +% f4(D, E, A) +% X[1] +% 0x8f1bbcdc, 11) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f2(Dp, Ep, Ap) +% X[8] +% 0x7a6d76e9, 15) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f4(C, D, E) +% X[9] +% 0x8f1bbcdc, 12) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f2(Cp, Dp, Ep) +% X[6] +% 0x7a6d76e9, 5) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f4(B, C, D) +% X[11] +% 0x8f1bbcdc, 14) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f2(Bp, Cp, Dp) +% X[4] +% 0x7a6d76e9, 8) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f4(A, B, C) +% X[10] +% 0x8f1bbcdc, 15) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f2(Ap, Bp, Cp) +% X[1] +% 0x7a6d76e9, 11) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f4(E, A, B) +% X[0] +% 0x8f1bbcdc, 14) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f2(Ep, Ap, Bp) +% X[3] +% 0x7a6d76e9, 14) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f4(D, E, A) +% X[8] +% 0x8f1bbcdc, 15) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f2(Dp, Ep, Ap) +% X[11] +% 0x7a6d76e9, 14) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f4(C, D, E) +% X[12] +% 0x8f1bbcdc, 9) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f2(Cp, Dp, Ep) +% X[15] +% 0x7a6d76e9, 6) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f4(B, C, D) +% X[4] +% 0x8f1bbcdc, 8) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f2(Bp, Cp, Dp) +% X[0] +% 0x7a6d76e9, 14) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f4(A, B, C) +% X[13] +% 0x8f1bbcdc, 9) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f2(Ap, Bp, Cp) +% X[5] +% 0x7a6d76e9, 6) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f4(E, A, B) +% X[3] +% 0x8f1bbcdc, 14) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f2(Ep, Ap, Bp) +% X[12] +% 0x7a6d76e9, 9) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f4(D, E, A) +% X[7] +% 0x8f1bbcdc, 5) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f2(Dp, Ep, Ap) +% X[2] +% 0x7a6d76e9, 12) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f4(C, D, E) +% X[15] +% 0x8f1bbcdc, 6) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f2(Cp, Dp, Ep) +% X[13] +% 0x7a6d76e9, 9) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f4(B, C, D) +% X[14] +% 0x8f1bbcdc, 8) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f2(Bp, Cp, Dp) +% X[9] +% 0x7a6d76e9, 12) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f4(A, B, C) +% X[5] +% 0x8f1bbcdc, 6) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f2(Ap, Bp, Cp) +% X[7] +% 0x7a6d76e9, 5) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f4(E, A, B) +% X[6] +% 0x8f1bbcdc, 5) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f2(Ep, Ap, Bp) +% X[10] +% 0x7a6d76e9, 15) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f4(D, E, A) +% X[2] +% 0x8f1bbcdc, 12) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f2(Dp, Ep, Ap) +% X[14] +% 0x7a6d76e9, 8) +% Bp; Ep = rotl(Ep, 10);

    // ── Round 5 ──
    B = rotl(B +% f5(C, D, E) +% X[4] +% 0xa953fd4e, 9) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f1(Cp, Dp, Ep) +% X[12], 8) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f5(B, C, D) +% X[0] +% 0xa953fd4e, 15) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f1(Bp, Cp, Dp) +% X[15], 5) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f5(A, B, C) +% X[5] +% 0xa953fd4e, 5) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f1(Ap, Bp, Cp) +% X[10], 12) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f5(E, A, B) +% X[9] +% 0xa953fd4e, 11) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f1(Ep, Ap, Bp) +% X[4], 9) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f5(D, E, A) +% X[7] +% 0xa953fd4e, 6) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f1(Dp, Ep, Ap) +% X[1], 12) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f5(C, D, E) +% X[12] +% 0xa953fd4e, 8) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f1(Cp, Dp, Ep) +% X[5], 5) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f5(B, C, D) +% X[2] +% 0xa953fd4e, 13) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f1(Bp, Cp, Dp) +% X[8], 14) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f5(A, B, C) +% X[10] +% 0xa953fd4e, 12) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f1(Ap, Bp, Cp) +% X[7], 6) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f5(E, A, B) +% X[14] +% 0xa953fd4e, 5) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f1(Ep, Ap, Bp) +% X[6], 8) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f5(D, E, A) +% X[1] +% 0xa953fd4e, 12) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f1(Dp, Ep, Ap) +% X[2], 13) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f5(C, D, E) +% X[3] +% 0xa953fd4e, 13) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f1(Cp, Dp, Ep) +% X[13], 6) +% Ap; Dp = rotl(Dp, 10);
    A = rotl(A +% f5(B, C, D) +% X[8] +% 0xa953fd4e, 14) +% E; C = rotl(C, 10);
    Ap = rotl(Ap +% f1(Bp, Cp, Dp) +% X[14], 5) +% Ep; Cp = rotl(Cp, 10);
    E = rotl(E +% f5(A, B, C) +% X[11] +% 0xa953fd4e, 11) +% D; B = rotl(B, 10);
    Ep = rotl(Ep +% f1(Ap, Bp, Cp) +% X[0], 15) +% Dp; Bp = rotl(Bp, 10);
    D = rotl(D +% f5(E, A, B) +% X[6] +% 0xa953fd4e, 8) +% C; A = rotl(A, 10);
    Dp = rotl(Dp +% f1(Ep, Ap, Bp) +% X[3], 13) +% Cp; Ap = rotl(Ap, 10);
    C = rotl(C +% f5(D, E, A) +% X[15] +% 0xa953fd4e, 5) +% B; E = rotl(E, 10);
    Cp = rotl(Cp +% f1(Dp, Ep, Ap) +% X[9], 11) +% Bp; Ep = rotl(Ep, 10);
    B = rotl(B +% f5(C, D, E) +% X[13] +% 0xa953fd4e, 6) +% A; D = rotl(D, 10);
    Bp = rotl(Bp +% f1(Cp, Dp, Ep) +% X[11], 11) +% Ap; Dp = rotl(Dp, 10);

    const T = h1 +% C +% Dp;
    h1 = h2 +% D +% Ep;
    h2 = h3 +% E +% Ap;
    h3 = h4 +% A +% Bp;
    h4 = h0 +% B +% Cp;
    h0 = T;

    st[0] = h0;
    st[1] = h1;
    st[2] = h2;
    st[3] = h3;
    st[4] = h4;
}

pub fn update(ctx: *Ripemd160Context, data: []const u8) void {
    if (data.len == 0) return;

    ctx.total_len += data.len;
    var pos: usize = 0;
    var len = data.len;

    if (ctx.buffer_len > 0) {
        const take = @min(len, 64 - ctx.buffer_len);
        @memcpy(ctx.buffer[ctx.buffer_len..][0..take], data[0..take]);
        ctx.buffer_len += @intCast(take);
        pos += take;
        len -= take;

        if (ctx.buffer_len == 64) {
            compressBlock(&ctx.state, &ctx.buffer);
            ctx.buffer_len = 0;
        }
    }

    while (len >= 64) {
        compressBlock(&ctx.state, data[pos..][0..64]);
        pos += 64;
        len -= 64;
    }

    if (len > 0) {
        @memcpy(ctx.buffer[0..len], data[pos..][0..len]);
        ctx.buffer_len = @intCast(len);
    }
}

pub fn final(ctx: *Ripemd160Context, out: *[20]u8) void {
    var padded: [128]u8 = undefined;
    const r = ctx.buffer_len;
    const bit_len = ctx.total_len * 8;

    @memcpy(padded[0..r], ctx.buffer[0..r]);
    padded[r] = 0x80;

    if (r < 56) {
        @memset(padded[r + 1 .. 56], 0);
        std.mem.writeInt(u64, padded[56..64], bit_len, .little);
        compressBlock(&ctx.state, padded[0..64]);
    } else {
        @memset(padded[r + 1 .. 120], 0);
        std.mem.writeInt(u64, padded[120..128], bit_len, .little);
        compressBlock(&ctx.state, padded[0..64]);
        compressBlock(&ctx.state, padded[64..128]);
    }

    for (0..5) |i| {
        std.mem.writeInt(u32, out[i * 4 ..][0..4], ctx.state[i], .little);
    }
}

/// One-shot RIPEMD-160 calculation
pub fn hash(data: []const u8, out: *[20]u8) void {
    var ctx = Ripemd160Context.init();
    update(&ctx, data);
    final(&ctx, out);
}
