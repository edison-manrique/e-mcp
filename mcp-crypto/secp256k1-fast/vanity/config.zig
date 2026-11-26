const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════
//  source/vanity/config.zig — Vanity Address Search Configuration
// ═══════════════════════════════════════════════════════════════════════════

/// Address type to generate
pub const AddressType = enum {
    /// Bitcoin P2PKH (Legacy "1...")
    btc_p2pkh,
    /// Bitcoin P2SH-P2WPKH (SegWit compat "3...")
    btc_p2sh_p2wpkh,
    /// Bitcoin P2WPKH (Native SegWit "bc1q...")
    btc_p2wpkh,
    /// Bitcoin P2TR (Taproot "bc1p...")
    btc_p2tr,
    /// Ethereum EIP-55 ("0x...")
    eth,

    /// Returns the fixed network prefix for this address type
    pub fn getNetworkPrefix(self: AddressType) []const u8 {
        return switch (self) {
            .btc_p2pkh => "1",
            .btc_p2sh_p2wpkh => "3",
            .btc_p2wpkh => "bc1q",
            .btc_p2tr => "bc1p",
            .eth => "0x",
        };
    }
};

/// Match mode for a rule
pub const MatchMode = enum {
    /// Address must START with the pattern (smart: matches after "1", "3", "bc1q", "0x" if not specified)
    starts_with,
    /// Address must END with the pattern
    ends_with,
    /// Address must CONTAIN the pattern anywhere
    contains,
};

/// Case sensitivity for matching
pub const CaseSensitivity = enum {
    /// Exact match (a ≠ A)
    sensitive,
    /// Case-insensitive (a == A)
    insensitive,
};

/// A single search rule (pattern to match)
pub const Rule = struct {
    /// The pattern to search for
    pattern: []const u8,
    /// How to match the pattern
    mode: MatchMode,

    /// Check if an address matches this rule
    pub fn matches(self: *const Rule, address: []const u8, addr_type: AddressType, case: CaseSensitivity) bool {
        return switch (self.mode) {
            .starts_with => startsWithSmartCheck(address, self.pattern, addr_type.getNetworkPrefix(), case),
            .ends_with => endsWithCheck(address, self.pattern, case),
            .contains => containsCheck(address, self.pattern, case),
        };
    }
};

/// Result of a vanity address search
pub const VanityResult = struct {
    /// Private key (32 bytes big-endian)
    private_key: [32]u8,
    /// The generated address string
    address: [128]u8,
    /// Length of the address string
    address_len: usize,
    /// Which rule was matched (index into rules array)
    matched_rule: usize,
    /// Number of keys tried before finding this result
    attempts: u64,

    pub fn getAddress(self: *const VanityResult) []const u8 {
        return self.address[0..self.address_len];
    }

    pub fn getPrivateKeyHex(self: *const VanityResult) [64]u8 {
        return std.fmt.bytesToHex(&self.private_key, .lower);
    }
};

/// Full vanity search configuration
pub const VanityConfig = struct {
    address_type: AddressType = .btc_p2pkh,
    num_threads: u32 = 0,
    case_sensitivity: CaseSensitivity = .insensitive,
    rules: []const Rule,
    max_attempts: u64 = 0,
    stop_on_first: bool = false,
    progress_interval: u64 = 1_000_000,
    manual_seed: ?[]const u8 = null,
    manual_seed_hex: ?[]const u8 = null,
    /// Entropía fresca a fundir (rompe determinismo; úsese sin semilla).
    extra_entropy: ?[]const u8 = null,

    pub fn hasManualSeed(self: *const VanityConfig) bool {
        if (self.manual_seed) |s| if (s.len > 0) return true;
        if (self.manual_seed_hex) |s| if (s.len > 0) return true;
        return false;
    }

    pub fn getEffectiveThreads(self: *const VanityConfig) u32 {
        if (self.num_threads == 0) {
            const cpus = std.Thread.getCpuCount() catch 4;
            return @intCast(@max(1, cpus));
        }
        return self.num_threads;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// String matching helpers (optimized for speed, zero allocations)
// ═══════════════════════════════════════════════════════════════════════════

inline fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn charsEq(a: u8, b: u8, case: CaseSensitivity) bool {
    return switch (case) {
        .sensitive => a == b,
        .insensitive => toLower(a) == toLower(b),
    };
}

/// Smart prefix matcher:
/// If pattern starts with network prefix (e.g. "1777" or "0xDEAD"), match from index 0.
/// Otherwise (e.g. "777" or "DEAD"), match immediately after the network prefix (e.g. index 1 for "1", index 2 for "0x").
fn startsWithSmartCheck(haystack: []const u8, needle: []const u8, net_prefix: []const u8, case: CaseSensitivity) bool {
    // Check if needle already starts with net_prefix
    const needle_has_prefix = startsWithCheck(needle, net_prefix, case);
    const start_offset: usize = if (needle_has_prefix) 0 else net_prefix.len;

    if (start_offset + needle.len > haystack.len) return false;

    for (0..needle.len) |i| {
        if (!charsEq(haystack[start_offset + i], needle[i], case)) return false;
    }
    return true;
}

fn startsWithCheck(haystack: []const u8, needle: []const u8, case: CaseSensitivity) bool {
    if (needle.len > haystack.len) return false;
    for (0..needle.len) |i| {
        if (!charsEq(haystack[i], needle[i], case)) return false;
    }
    return true;
}

fn endsWithCheck(haystack: []const u8, needle: []const u8, case: CaseSensitivity) bool {
    if (needle.len > haystack.len) return false;
    const offset = haystack.len - needle.len;
    for (0..needle.len) |i| {
        if (!charsEq(haystack[offset + i], needle[i], case)) return false;
    }
    return true;
}

fn containsCheck(haystack: []const u8, needle: []const u8, case: CaseSensitivity) bool {
    if (needle.len > haystack.len) return false;
    const limit = haystack.len - needle.len + 1;
    for (0..limit) |start| {
        var found = true;
        for (0..needle.len) |i| {
            if (!charsEq(haystack[start + i], needle[i], case)) {
                found = false;
                break;
            }
        }
        if (found) return true;
    }
    return false;
}
