const std = @import("std");
const sha256 = @import("../hash/sha256.zig");
const pbkdf2_sha512 = @import("../hash/pbkdf2_sha512.zig");

// ═══════════════════════════════════════════════════════════════════════════
//  source/bip39/bip39.zig — BIP-39 Mnemonic to Entropy / Seed (Zero-Alloc)
//
//  Genérico sobre la wordlist: cada función recibe `comptime wl` (el módulo
//  wordlist_en.zig / wordlist_es.zig). `mnemonicToSeed` no depende del idioma.
// ═══════════════════════════════════════════════════════════════════════════

pub const Error = error{
    InvalidEntropyLength,
    InvalidWordCount,
    WordNotFound,
    InvalidChecksum,
    OutputBufferTooSmall,
    EmptyMnemonic,
};

/// Encodes raw entropy (16, 20, 24, 28, 32 bytes) to a BIP-39 mnemonic string in out_buf.
/// Returns the slice of out_buf containing the space-separated words.
pub fn entropyToMnemonic(comptime wl: type, entropy: []const u8, out_buf: []u8) Error![]u8 {
    const ent_len = entropy.len;
    if (ent_len != 16 and ent_len != 20 and ent_len != 24 and ent_len != 28 and ent_len != 32) {
        return error.InvalidEntropyLength;
    }

    // Checksum = first ENT/32 bits of SHA-256(entropy)
    var checksum_hash: [32]u8 = undefined;
    sha256.hash(entropy, &checksum_hash);

    const checksum_bits: usize = ent_len / 4; // ent_len * 8 / 32
    const total_bits: usize = ent_len * 8 + checksum_bits;
    const word_count: usize = total_bits / 11;

    var pos: usize = 0;
    var bit_offset: usize = 0;

    for (0..word_count) |w_idx| {
        var index: u11 = 0;
        for (0..11) |_| {
            const byte_idx = bit_offset >> 3;
            const bit_idx: u3 = @intCast(7 - (bit_offset & 7));
            const val: u8 = if (byte_idx < ent_len)
                entropy[byte_idx]
            else
                checksum_hash[byte_idx - ent_len];

            const bit: u11 = @intCast((val >> bit_idx) & 1);
            index = (index << 1) | bit;
            bit_offset += 1;
        }

        const word = wl.getWord(index);
        if (w_idx > 0) {
            if (pos >= out_buf.len) return error.OutputBufferTooSmall;
            out_buf[pos] = ' ';
            pos += 1;
        }

        if (pos + word.len > out_buf.len) return error.OutputBufferTooSmall;
        @memcpy(out_buf[pos..][0..word.len], word);
        pos += word.len;
    }

    return out_buf[0..pos];
}

/// Decodes a BIP-39 mnemonic string into raw entropy in out_entropy.
/// Returns the slice of out_entropy containing the entropy bytes (16..32 bytes).
pub fn mnemonicToEntropy(comptime wl: type, mnemonic: []const u8, out_entropy: []u8) Error![]u8 {
    const trimmed = std.mem.trim(u8, mnemonic, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyMnemonic;

    // Count words
    var word_count: usize = 0;
    var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (it.next()) |_| {
        word_count += 1;
    }

    if (word_count != 12 and word_count != 15 and word_count != 18 and word_count != 21 and word_count != 24) {
        return error.InvalidWordCount;
    }

    const total_bits = word_count * 11;
    const checksum_bits = total_bits / 33;
    const entropy_bytes = (total_bits - checksum_bits) / 8;

    if (out_entropy.len < entropy_bytes) return error.OutputBufferTooSmall;
    @memset(out_entropy[0..entropy_bytes], 0);

    var provided_checksum: u8 = 0;
    var bit_offset: usize = 0;

    it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (it.next()) |word| {
        const idx = wl.findWord(word) orelse return error.WordNotFound;

        var bit: i32 = 10;
        while (bit >= 0) : (bit -= 1) {
            if (((idx >> @intCast(bit)) & 1) != 0) {
                const byte_idx = bit_offset >> 3;
                const bit_idx: u3 = @intCast(7 - (bit_offset & 7));
                const mask: u8 = @as(u8, 1) << bit_idx;

                if (byte_idx < entropy_bytes) {
                    out_entropy[byte_idx] |= mask;
                } else if (byte_idx == entropy_bytes) {
                    provided_checksum |= mask;
                }
            }
            bit_offset += 1;
        }
    }

    // Verify SHA-256 checksum
    var checksum_hash: [32]u8 = undefined;
    sha256.hash(out_entropy[0..entropy_bytes], &checksum_hash);

    const shift: u3 = @intCast(8 - checksum_bits);
    const mask: u8 = @as(u8, 0xff) << shift;
    const expected_checksum = checksum_hash[0] & mask;

    if ((provided_checksum & mask) != expected_checksum) {
        return error.InvalidChecksum;
    }

    return out_entropy[0..entropy_bytes];
}

/// Derives a 64-byte seed from a mnemonic and an optional passphrase using PBKDF2-HMAC-SHA512.
pub fn mnemonicToSeed(mnemonic: []const u8, passphrase: []const u8, out_seed: *[64]u8) void {
    // Salt is "mnemonic" + passphrase
    const prefix = "mnemonic";
    var salt_buf: [1024]u8 = undefined;
    @memcpy(salt_buf[0..prefix.len], prefix);
    const pass_len = @min(passphrase.len, salt_buf.len - prefix.len);
    @memcpy(salt_buf[prefix.len..][0..pass_len], passphrase[0..pass_len]);
    const salt = salt_buf[0 .. prefix.len + pass_len];
    pbkdf2_sha512.derive64(mnemonic, salt, 2048, out_seed);
}

/// Validates a BIP-39 mnemonic string (returns true if valid words, count, and checksum).
pub fn validateMnemonic(comptime wl: type, mnemonic: []const u8) bool {
    var dummy_entropy: [32]u8 = undefined;
    if (mnemonicToEntropy(wl, mnemonic, &dummy_entropy)) |_| {
        return true;
    } else |_| {
        return false;
    }
}
