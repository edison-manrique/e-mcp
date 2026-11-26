const std = @import("std");
const keccak256 = @import("../hash/keccak256.zig");
const BigInt256 = @import("../field/root.zig").BigInt256;

// ═══════════════════════════════════════════════════════════════════════════
//  source/address/eth.zig — Ethereum EIP-55 Address (Zero-Alloc, Pure Speed)
// ═══════════════════════════════════════════════════════════════════════════

const HEX_LO = "0123456789abcdef";

/// Ethereum address derivation: "0x" + 40 chars of Keccak256(pubkey_64_uncompressed) with EIP-55 checksum.
/// Accepts uncompressed pubkey (64B or 65B with 0x04) or compressed pubkey (33B).
/// Writes 42 ASCII chars to out_buf and returns out_buf[0..42].
pub fn ethAddress(pubkey: []const u8, out_buf: []u8) ![]u8 {
    if (out_buf.len < 42) return error.OutputBufferTooSmall;

    var pure_key: [64]u8 = undefined;

    if (pubkey.len == 65 and pubkey[0] == 0x04) {
        @memcpy(&pure_key, pubkey[1..65]);
    } else if (pubkey.len == 64) {
        @memcpy(&pure_key, pubkey);
    } else if (pubkey.len == 33) {
        // Decompress 33B -> 64B
        const x = BigInt256.fromBytes(pubkey[1..33]);
        var y = try x.liftX();
        if ((pubkey[0] == 0x03 and !y.isOdd()) or (pubkey[0] == 0x02 and y.isOdd())) {
            y = BigInt256.P.sub(y).result;
        }
        x.toBytes(pure_key[0..32]);
        y.toBytes(pure_key[32..64]);
    } else {
        return error.InvalidPubkey;
    }

    // 1. Keccak256(pureKey) -> 32B hash
    var k_hash: [32]u8 = undefined;
    keccak256.hash(&pure_key, &k_hash);

    // 2. Last 20 bytes (k_hash[12..32]) -> lowercase hex ASCII (40 chars)
    var hex_buf: [40]u8 = undefined;
    for (0..20) |i| {
        const b = k_hash[12 + i];
        hex_buf[i * 2] = HEX_LO[b >> 4];
        hex_buf[i * 2 + 1] = HEX_LO[b & 0x0f];
    }

    // 3. EIP-55 checksum = Keccak256(hex_buf)
    var checksum_hash: [32]u8 = undefined;
    keccak256.hash(&hex_buf, &checksum_hash);

    // 4. "0x" + EIP-55 capitalized address
    out_buf[0] = '0';
    out_buf[1] = 'x';
    for (0..40) |i| {
        var c = hex_buf[i];
        const hash_byte = checksum_hash[i >> 1];
        const hash_nibble: u8 = if ((i & 1) == 0) hash_byte >> 4 else hash_byte & 0x0f;

        if (c >= 'a' and c <= 'f' and hash_nibble >= 8) {
            c -= 32; // 'a'-'f' -> 'A'-'F'
        }
        out_buf[2 + i] = c;
    }

    return out_buf[0..42];
}
