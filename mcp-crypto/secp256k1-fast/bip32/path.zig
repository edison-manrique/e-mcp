const std = @import("std");
const constants = @import("constants.zig");
const xkey_mod = @import("xkey.zig");
const ExtendedKey = xkey_mod.ExtendedKey;
const ckd = @import("ckd.zig");

// ═══════════════════════════════════════════════════════════════════════════
//  source/bip32/path.zig — BIP-32 Derivation Path Parser & Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Derives an extended key following a standard BIP-32 derivation path string.
/// Supports formats: "m/44'/0'/0'/0/0", "M/84'/0'/0'/0/0", "44'/0'", "m", "".
/// Hardened suffixes: "'", "h", "H".
pub fn derivePath(parent: *const ExtendedKey, path: []const u8) constants.Error!ExtendedKey {
    var cur = parent.*;
    var pos: usize = 0;

    // Skip leading "m" or "M" with optional "/"
    if (path.len > 0 and (path[0] == 'm' or path[0] == 'M')) {
        pos = 1;
        if (pos < path.len and path[pos] == '/') {
            pos += 1;
        }
    }

    while (pos < path.len) {
        if (path[pos] == '/') {
            pos += 1;
            continue;
        }

        var idx: u32 = 0;
        var hardened = false;
        var has_digit = false;

        while (pos < path.len) {
            const c = path[pos];
            if (c >= '0' and c <= '9') {
                idx = idx * 10 + (c - '0');
                has_digit = true;
                pos += 1;
            } else if (c == '\'' or c == 'h' or c == 'H') {
                hardened = true;
                pos += 1;
            } else if (c == '/') {
                pos += 1;
                break;
            } else {
                return error.InvalidPath;
            }
        }

        if (!has_digit) continue;

        const final_idx: u32 = if (hardened) idx + constants.HARDENED_OFFSET else idx;
        cur = try ckd.derive(&cur, final_idx);
    }

    return cur;
}

/// Derives m / purpose' / coin_type' / account' (3 hardened levels)
pub fn deriveAccount(
    parent: *const ExtendedKey,
    purpose: u32,
    coin_type: u32,
    account: u32,
) constants.Error!ExtendedKey {
    var cur = try ckd.derive(parent, purpose + constants.HARDENED_OFFSET);
    cur = try ckd.derive(&cur, coin_type + constants.HARDENED_OFFSET);
    cur = try ckd.derive(&cur, account + constants.HARDENED_OFFSET);
    return cur;
}

/// Derives m / purpose' / coin_type' / account' / change / index (5 levels)
pub fn deriveAddress(
    parent: *const ExtendedKey,
    purpose: u32,
    coin_type: u32,
    account: u32,
    change: u32,
    index: u32,
) constants.Error!ExtendedKey {
    var cur = try deriveAccount(parent, purpose, coin_type, account);
    cur = try ckd.derive(&cur, change);
    cur = try ckd.derive(&cur, index);
    return cur;
}
