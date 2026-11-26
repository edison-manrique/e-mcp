const std = @import("std");
const builtin = @import("builtin");
const bip32 = @import("../bip32/root.zig");
const bip39 = @import("../bip39/root.zig");
const bip44 = @import("../bip44/root.zig");
const btc_address = @import("../address/btc.zig");

// ═══════════════════════════════════════════════════════════════════════════
//  source/recovery/solver.zig — High Speed Multithreaded BTC Puzzle Solver
// ═══════════════════════════════════════════════════════════════════════════

pub const SpinLock = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn lock(self: *SpinLock) void {
        while (self.state.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *SpinLock) void {
        self.state.store(false, .release);
    }
};

pub fn nowMilli() u64 {
    if (builtin.os.tag == .windows) {
        const kernel32 = struct {
            extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *i64) callconv(.winapi) i32;
            extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *i64) callconv(.winapi) i32;
        };
        var count: i64 = 0;
        var freq: i64 = 0;
        _ = kernel32.QueryPerformanceCounter(&count);
        _ = kernel32.QueryPerformanceFrequency(&freq);
        if (freq == 0) return 0;
        const c: u64 = @bitCast(count);
        const f: u64 = @bitCast(freq);
        return @divTrunc(c *% 1_000, f);
    } else if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        const rc = std.os.linux.clock_gettime(.MONOTONIC, &ts);
        if (rc == 0) {
            return @as(u64, @intCast(ts.sec)) *% 1_000 +% @as(u64, @intCast(@divTrunc(ts.nsec, 1_000_000)));
        }
        return 0;
    } else {
        var dummy: u8 = undefined;
        return @intFromPtr(&dummy);
    }
}

pub const RecoverConfig = struct {
    target_address: []const u8,
    partial_mnemonic: []const u8,
    candidate_words: ?[]const []const u8 = null,
    passphrase: []const u8 = "",
    purpose: u32 = 44,
    coin_type: u32 = 0,
    account: u32 = 0,
    change: u32 = 0,
    max_index: u32 = 1,
    num_threads: usize = 0,
};

pub const RecoverResult = struct {
    mnemonic: [256]u8,
    mnemonic_len: usize,
    private_key: [32]u8,
    public_key: [33]u8,
    address: [64]u8,
    address_len: usize,
    total_tested: u64,
    elapsed_ms: u64,

    pub fn getMnemonic(self: *const RecoverResult) []const u8 {
        return self.mnemonic[0..self.mnemonic_len];
    }

    pub fn getAddress(self: *const RecoverResult) []const u8 {
        return self.address[0..self.address_len];
    }
};

const SharedState = struct {
    found: std.atomic.Value(bool),
    total_tested: std.atomic.Value(u64),
    result: ?RecoverResult,
    lock: SpinLock,
};

/// Solves a puzzle with 1 missing word in a partial mnemonic (e.g. "abandon ability ... ? ... about")
pub fn solveOneMissingWord(allocator: std.mem.Allocator, config: *const RecoverConfig) !?RecoverResult {
    _ = allocator;
    const trimmed = std.mem.trim(u8, config.partial_mnemonic, " \t\r\n");

    // Parse words into static array (max 24 words for BIP-39)
    var words: [24][]const u8 = undefined;
    var total_words: usize = 0;
    var missing_idx: ?usize = null;

    var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (it.next()) |w| {
        if (total_words >= 24) return error.InvalidWordCount;
        if (std.mem.eql(u8, w, "?") or std.mem.eql(u8, w, "*") or std.mem.eql(u8, w, "MISSING") or std.mem.eql(u8, w, "missing")) {
            missing_idx = total_words;
            words[total_words] = "";
        } else {
            words[total_words] = w;
        }
        total_words += 1;
    }

    if (total_words != 12 and total_words != 15 and total_words != 18 and total_words != 21 and total_words != 24) {
        return error.InvalidWordCount;
    }

    const missing_pos = missing_idx orelse return error.NoMissingWordFound;

    const candidates = if (config.candidate_words) |cw| cw else &bip39.WORDS;

    var shared = SharedState{
        .found = std.atomic.Value(bool).init(false),
        .total_tested = std.atomic.Value(u64).init(0),
        .result = null,
        .lock = .{},
    };

    const thread_count = @min(64, if (config.num_threads > 0)
        config.num_threads
    else
        @max(1, std.Thread.getCpuCount() catch 4));

    const Worker = struct {
        fn run(
            w_slice: []const []const u8,
            m_pos: usize,
            cand_slice: []const []const u8,
            cfg: *const RecoverConfig,
            st: *SharedState,
            start_time: u64,
        ) void {
            var local_words: [24][]const u8 = undefined;
            for (w_slice, 0..) |w, i| {
                local_words[i] = w;
            }

            var mn_buf: [256]u8 = undefined;
            var seed_buf: [64]u8 = undefined;
            var addr_buf: [64]u8 = undefined;

            for (cand_slice) |cand| {
                if (st.found.load(.monotonic)) return;

                local_words[m_pos] = cand;

                // Format mnemonic string
                var mn_len: usize = 0;
                for (0..w_slice.len) |i| {
                    if (i > 0) {
                        mn_buf[mn_len] = ' ';
                        mn_len += 1;
                    }
                    const w = local_words[i];
                    @memcpy(mn_buf[mn_len..][0..w.len], w);
                    mn_len += w.len;
                }
                const mnemonic = mn_buf[0..mn_len];

                _ = st.total_tested.fetchAdd(1, .monotonic);

                // 1. Fast Checksum Filter
                if (!bip39.validateMnemonic(mnemonic)) continue;

                // 2. Mnemonic to Seed
                bip39.mnemonicToSeed(mnemonic, cfg.passphrase, &seed_buf);

                // 3. Derive Master Key
                const master = bip32.fromSeed(&seed_buf) catch continue;

                // 4. Test addresses for indices 0..max_index
                var addr_idx: u32 = 0;
                while (addr_idx < cfg.max_index) : (addr_idx += 1) {
                    const leaf = bip32.deriveAddress(&master, cfg.purpose, cfg.coin_type, cfg.account, cfg.change, addr_idx) catch continue;
                    const pub_key = leaf.getPublicKey();
                    const addr = switch (cfg.purpose) {
                        44 => btc_address.p2pkh(&pub_key, &addr_buf) catch continue,
                        49 => btc_address.p2sh_p2wpkh(&pub_key, &addr_buf) catch continue,
                        84 => btc_address.p2wpkh(&pub_key, &addr_buf) catch continue,
                        86 => btc_address.p2tr(&pub_key, &addr_buf) catch continue,
                        else => btc_address.p2pkh(&pub_key, &addr_buf) catch continue,
                    };

                    if (std.mem.eql(u8, addr, cfg.target_address)) {
                        st.lock.lock();
                        defer st.lock.unlock();
                        if (!st.found.load(.monotonic)) {
                            st.found.store(true, .monotonic);
                            const now = nowMilli();
                            var res = RecoverResult{
                                .mnemonic = undefined,
                                .mnemonic_len = mn_len,
                                .private_key = leaf.getPrivateKey() orelse @as([32]u8, @splat(0)),
                                .public_key = pub_key,
                                .address = undefined,
                                .address_len = addr.len,
                                .total_tested = st.total_tested.load(.monotonic),
                                .elapsed_ms = @max(1, now - start_time),
                            };
                            @memcpy(res.mnemonic[0..mn_len], mnemonic);
                            @memcpy(res.address[0..addr.len], addr);
                            st.result = res;
                        }
                        return;
                    }
                }
            }
        }
    };

    const start_time = nowMilli();
    var threads: [64]std.Thread = undefined;
    var spawned_count: usize = 0;

    const chunk_size = (candidates.len + thread_count - 1) / thread_count;
    for (0..thread_count) |t| {
        const start_idx = t * chunk_size;
        if (start_idx >= candidates.len) break;
        const end_idx = @min(start_idx + chunk_size, candidates.len);
        const thread_cand = candidates[start_idx..end_idx];

        threads[spawned_count] = try std.Thread.spawn(.{}, Worker.run, .{
            words[0..total_words],
            missing_pos,
            thread_cand,
            config,
            &shared,
            start_time,
        });
        spawned_count += 1;
    }

    for (0..spawned_count) |t| {
        threads[t].join();
    }

    return shared.result;
}
