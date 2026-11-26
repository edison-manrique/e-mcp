// file: apps/vanity_cli.zig
const std = @import("std");
const secp = @import("secp256k1");
const vanity = secp.vanity;
const AddressType = vanity.AddressType;
const MatchMode = vanity.MatchMode;
const CaseSensitivity = vanity.CaseSensitivity;
const Rule = vanity.Rule;
const VanityConfig = vanity.VanityConfig;
const VanityResult = vanity.VanityResult;
const SharedState = vanity.SharedState;

// ===========================================================================
//  apps/vanity_cli.zig -- High Performance Multi-Threaded Vanity CLI App
//  Interactive TUI when launched with no arguments.
//  Supports manual seed for deterministic output.
// ===========================================================================

var g_io: std.Io = undefined;
var g_start_clock: std.Io.Timestamp = undefined;
var g_output_file_path: []const u8 = "vanity_results.txt";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    g_io = io;

    var out_buffer: [8192]u8 = undefined;
    var stdout_impl = std.Io.File.stdout().writer(io, &out_buffer);
    const stdout = &stdout_impl.interface;
    defer stdout.flush() catch {};

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len <= 1) {
        try runInteractiveMode(io, stdout, allocator);
    } else {
        try runCliMode(io, stdout, allocator, args);
    }
}

// ─────────────────────────────────────────────────────────────────────────
// INTERACTIVE TUI MODE
// ─────────────────────────────────────────────────────────────────────────

fn readLine(io: std.Io, buf: []u8) []u8 {
    var stdin_buf: [512]u8 = undefined;
    var stdin_impl = std.Io.File.stdin().reader(io, &stdin_buf);
    const stdin = &stdin_impl.interface;

    const line = stdin.takeDelimiterExclusive('\n') catch return buf[0..0];
    const trimmed = std.mem.trimEnd(u8, line, "\r");
    const copy_len = @min(trimmed.len, buf.len);
    @memcpy(buf[0..copy_len], trimmed[0..copy_len]);
    return buf[0..copy_len];
}

fn runInteractiveMode(io: std.Io, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    try printBanner(stdout);
    try stdout.flush();

    var rules_list: std.ArrayList(Rule) = .empty;
    defer rules_list.deinit(allocator);

    var addr_type: AddressType = .btc_p2pkh;
    var num_threads: u32 = 0;
    var max_attempts: u64 = 0;
    var case_sensitivity: CaseSensitivity = .insensitive;
    var stop_on_first: bool = false;
    var output_file: [256]u8 = undefined;
    var output_file_path: []const u8 = "vanity_results.txt";

    // ═══ NUEVOS CAMPOS PARA SEED MANUAL ═══
    var manual_seed_buf: [256]u8 = undefined;
    var manual_seed: ?[]const u8 = null;
    var manual_seed_hex_buf: [256]u8 = undefined;
    var manual_seed_hex: ?[]const u8 = null;

    var input_buf: [512]u8 = undefined;

    while (true) {
        try stdout.print("\n", .{});
        try stdout.print("+----------------------------------------------+\n", .{});
        try stdout.print("|      VANITY GENERATOR - MAIN MENU            |\n", .{});
        try stdout.print("+----------------------------------------------+\n", .{});
        try stdout.print("|  [1] Set address type    ({s:<18}) |\n", .{@tagName(addr_type)});
        try stdout.print("|  [2] Add prefix rule                         |\n", .{});
        try stdout.print("|  [3] Add suffix rule                         |\n", .{});
        try stdout.print("|  [4] Add contains rule                       |\n", .{});
        try stdout.print("|  [5] Set threads         ({d:<18}) |\n", .{num_threads});
        try stdout.print("|  [6] Set max keys        ({d:<18}) |\n", .{max_attempts});
        try stdout.print("|  [7] Case sensitivity    ({s:<18}) |\n", .{@tagName(case_sensitivity)});
        try stdout.print("|  [8] Stop after 1 match  ({s:<18}) |\n", .{if (stop_on_first) "yes" else "no"});
        try stdout.print("|  [9] Set output file     ({s:<18}) |\n", .{output_file_path[0..@min(output_file_path.len, 18)]});
        try stdout.print("|  [A] Set manual seed (decimal)               |\n", .{});
        try stdout.print("|  [B] Set manual seed (hex)                   |\n", .{});
        try stdout.print("|  [C] Clear manual seed                       |\n", .{});
        try stdout.print("|  [D] Clear all rules     ({d} rule(s))         |\n", .{rules_list.items.len});
        try stdout.print("|  [S] Start search                            |\n", .{});
        try stdout.print("|  [Q] Quit                                    |\n", .{});
        try stdout.print("+----------------------------------------------+\n", .{});

        // Show manual seed status
        if (manual_seed != null or manual_seed_hex != null) {
            try stdout.print("  [SEED] DETERMINISTIC MODE ACTIVE\n", .{});
            if (manual_seed) |s| {
                try stdout.print("    Decimal seed: {s}\n", .{s});
            }
            if (manual_seed_hex) |s| {
                try stdout.print("    Hex seed: {s}\n", .{s});
            }
            try stdout.print("    Same seed = same addresses every run\n", .{});
        }

        if (rules_list.items.len > 0) {
            try stdout.print("  Active rules:\n", .{});
            for (rules_list.items, 1..) |r, idx| {
                try stdout.print("    {d}. {s} \"{s}\"\n", .{ idx, @tagName(r.mode), r.pattern });
            }
        }
        try stdout.print("\n> ", .{});
        try stdout.flush();

        const choice = readLine(io, &input_buf);

        if (choice.len == 0) continue;

        switch (choice[0]) {
            '1' => {
                try stdout.print("\nAddress type:\n", .{});
                try stdout.print("  [1] p2pkh   - Bitcoin Legacy (1...)\n", .{});
                try stdout.print("  [2] p2sh    - Bitcoin SegWit compat (3...)\n", .{});
                try stdout.print("  [3] p2wpkh  - Bitcoin Native SegWit (bc1q...)\n", .{});
                try stdout.print("  [4] p2tr    - Bitcoin Taproot (bc1p...)\n", .{});
                try stdout.print("  [5] eth     - Ethereum (0x...)\n", .{});
                try stdout.print("> ", .{});
                try stdout.flush();
                const t = readLine(io, &input_buf);
                switch (if (t.len > 0) t[0] else '1') {
                    '1' => addr_type = .btc_p2pkh,
                    '2' => addr_type = .btc_p2sh_p2wpkh,
                    '3' => addr_type = .btc_p2wpkh,
                    '4' => addr_type = .btc_p2tr,
                    '5' => addr_type = .eth,
                    else => try stdout.print("  [!] Invalid choice, keeping {s}\n", .{@tagName(addr_type)}),
                }
                rules_list.clearRetainingCapacity();
                try stdout.print("  [OK] Address type: {s}\n", .{@tagName(addr_type)});
            },
            '2', '3', '4' => {
                const mode: MatchMode = switch (choice[0]) {
                    '2' => .starts_with,
                    '3' => .ends_with,
                    else => .contains,
                };
                const mode_name: []const u8 = switch (mode) {
                    .starts_with => "prefix",
                    .ends_with => "suffix",
                    .contains => "contains",
                };
                try stdout.print("  Enter {s} pattern: ", .{mode_name});
                try stdout.flush();
                const pat = readLine(io, &input_buf);
                if (pat.len == 0) {
                    try stdout.print("  [!] Empty pattern ignored.\n", .{});
                    continue;
                }
                vanity.validator.validatePattern(pat, addr_type) catch |err| {
                    try stdout.print("  [ERROR] Invalid pattern: ", .{});
                    switch (err) {
                        error.InvalidBase58Char => try stdout.print("Invalid Base58 chars (forbidden: 0, O, I, l)\n", .{}),
                        error.InvalidBech32Char => try stdout.print("Invalid Bech32 chars\n", .{}),
                        error.InvalidHexChar => try stdout.print("Invalid hex chars (use 0-9, a-f)\n", .{}),
                        error.EmptyPattern => try stdout.print("Pattern is empty\n", .{}),
                        error.PatternTooLong => try stdout.print("Pattern too long (max 40)\n", .{}),
                    }
                    continue;
                };
                const pat_dup = try allocator.dupe(u8, pat);
                try rules_list.append(allocator, .{ .pattern = pat_dup, .mode = mode });
                try stdout.print("  [OK] Added rule: {s} \"{s}\"\n", .{ @tagName(mode), pat });
            },
            '5' => {
                try stdout.print("  Threads (0 = auto, max = {d}): ", .{std.Thread.getCpuCount() catch 8});
                try stdout.flush();
                const t_str = readLine(io, &input_buf);
                num_threads = std.fmt.parseInt(u32, t_str, 10) catch blk: {
                    try stdout.print("  [!] Invalid number\n", .{});
                    break :blk num_threads;
                };
                try stdout.print("  [OK] Threads: {d}\n", .{num_threads});
            },
            '6' => {
                try stdout.print("  Max keys (0 = unlimited): ", .{});
                try stdout.flush();
                const m_str = readLine(io, &input_buf);
                max_attempts = std.fmt.parseInt(u64, m_str, 10) catch blk: {
                    try stdout.print("  [!] Invalid number\n", .{});
                    break :blk max_attempts;
                };
                try stdout.print("  [OK] Max keys: {d}\n", .{max_attempts});
            },
            '7' => {
                case_sensitivity = if (case_sensitivity == .sensitive) .insensitive else .sensitive;
                try stdout.print("  [OK] Case sensitivity: {s}\n", .{@tagName(case_sensitivity)});
            },
            '8' => {
                stop_on_first = !stop_on_first;
                try stdout.print("  [OK] Stop on first: {s}\n", .{if (stop_on_first) "yes" else "no"});
            },
            '9' => {
                try stdout.print("  Output file path: ", .{});
                try stdout.flush();
                const f = readLine(io, &input_buf);
                if (f.len > 0 and f.len < output_file.len) {
                    @memcpy(output_file[0..f.len], f);
                    output_file_path = output_file[0..f.len];
                }
                try stdout.print("  [OK] Output file: {s}\n", .{output_file_path});
            },
            // ═══ SEED MANUAL (DECIMAL) ═══
            'A', 'a' => {
                try stdout.print("\n  Enter manual seed (decimal, e.g. 123456789):\n", .{});
                try stdout.print("  [!] DETERMINISTIC: same seed = same addresses\n", .{});
                try stdout.print("  > ", .{});
                try stdout.flush();
                const seed_input = readLine(io, &input_buf);

                if (seed_input.len == 0) {
                    try stdout.print("  [!] Empty seed, keeping previous.\n", .{});
                    continue;
                }

                // Validate: must be all digits
                var valid = true;
                for (seed_input) |c| {
                    if (c < '0' or c > '9') {
                        valid = false;
                        break;
                    }
                }

                if (!valid) {
                    try stdout.print("  [ERROR] Invalid seed: must contain only digits 0-9\n", .{});
                    continue;
                }

                if (seed_input.len > 78) { // 2^256 has ~78 decimal digits
                    try stdout.print("  [ERROR] Seed too large (max 78 digits for 256-bit)\n", .{});
                    continue;
                }

                @memcpy(manual_seed_buf[0..seed_input.len], seed_input);
                manual_seed = manual_seed_buf[0..seed_input.len];
                manual_seed_hex = null; // Clear hex if decimal is set

                try stdout.print("  [OK] Manual seed set (decimal): {s}\n", .{seed_input});
                try stdout.print("  [OK] DETERMINISTIC mode enabled\n", .{});
            },
            // ═══ SEED MANUAL (HEX) ═══
            'B', 'b' => {
                try stdout.print("\n  Enter manual seed (hex, e.g. DEADBEEF or 0xDEADBEEF):\n", .{});
                try stdout.print("  [!] DETERMINISTIC: same seed = same addresses\n", .{});
                try stdout.print("  > ", .{});
                try stdout.flush();
                var seed_input = readLine(io, &input_buf);

                if (seed_input.len == 0) {
                    try stdout.print("  [!] Empty seed, keeping previous.\n", .{});
                    continue;
                }

                // Strip "0x" prefix if present
                if (seed_input.len > 2 and std.mem.startsWith(u8, seed_input, "0x")) {
                    seed_input = seed_input[2..];
                }

                // Validate: must be hex chars
                var valid = true;
                for (seed_input) |c| {
                    if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) {
                        valid = false;
                        break;
                    }
                }

                if (!valid) {
                    try stdout.print("  [ERROR] Invalid seed: must contain only hex chars (0-9, a-f)\n", .{});
                    continue;
                }

                if (seed_input.len > 64) { // 32 bytes = 64 hex chars
                    try stdout.print("  [ERROR] Seed too large (max 64 hex chars for 256-bit)\n", .{});
                    continue;
                }

                @memcpy(manual_seed_hex_buf[0..seed_input.len], seed_input);
                manual_seed_hex = manual_seed_hex_buf[0..seed_input.len];
                manual_seed = null; // Clear decimal if hex is set

                try stdout.print("  [OK] Manual seed set (hex): {s}\n", .{seed_input});
                try stdout.print("  [OK] DETERMINISTIC mode enabled\n", .{});
            },
            // ═══ CLEAR SEED ═══
            'C', 'c' => {
                manual_seed = null;
                manual_seed_hex = null;
                try stdout.print("  [OK] Manual seed cleared. Non-deterministic mode.\n", .{});
            },
            'D', 'd' => {
                rules_list.clearRetainingCapacity();
                try stdout.print("  [OK] All rules cleared.\n", .{});
            },
            'S', 's' => {
                if (rules_list.items.len == 0) {
                    try stdout.print("  [ERROR] No rules set. Add at least one rule first.\n", .{});
                    continue;
                }
                g_output_file_path = output_file_path;
                const config = VanityConfig{
                    .address_type = addr_type,
                    .num_threads = num_threads,
                    .case_sensitivity = case_sensitivity,
                    .rules = rules_list.items,
                    .max_attempts = max_attempts,
                    .stop_on_first = stop_on_first,
                    .progress_interval = 100_000,
                    .manual_seed = manual_seed,
                    .manual_seed_hex = manual_seed_hex,
                };
                try runSearch(io, stdout, config, output_file_path);
            },
            'Q', 'q' => {
                try stdout.print("\nGoodbye!\n", .{});
                try stdout.flush();
                return;
            },
            else => {
                try stdout.print("  [!] Unknown option '{s}'. Try again.\n", .{choice});
            },
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// CLI MODE
// ─────────────────────────────────────────────────────────────────────────

fn printUsage(stdout: *std.Io.Writer) void {
    stdout.print(
        \\
        \\secp256k1-zig Vanity Address Generator
        \\
        \\USAGE:
        \\  vanity-cli [OPTIONS]
        \\  vanity-cli           (no args -> interactive menu)
        \\
        \\OPTIONS:
        \\  --type <type>        Address type: p2pkh (default), p2sh, p2wpkh, p2tr, eth
        \\  --threads <N>        Number of CPU worker threads (1 to max CPU cores)
        \\  --max <N>            Maximum keys to search before stopping (default: 0 = unlimited)
        \\  --sensitive          Enable case-sensitive matching (default: insensitive)
        \\  --stop-first         Stop after finding the first match
        \\  --prefix <pattern>   Find address starting with <pattern>
        \\  --suffix <pattern>   Find address ending with <pattern>
        \\  --contains <pattern> Find address containing <pattern>
        \\  --out <file>         File path to save results (default: vanity_results.txt)
        \\  --config <file.json> Load search configuration from JSON file
        \\  --seed <decimal>     Manual seed in base-10 (DETERMINISTIC mode)
        \\  --seed-hex <hex>     Manual seed in hex (DETERMINISTIC mode)
        \\  --help               Display this help message
        \\
        \\DETERMINISTIC MODE:
        \\  When --seed or --seed-hex is provided, the output is fully deterministic.
        \\  Same seed + same rules = same addresses every run.
        \\  The seed is multiplied by the secp256k1 generator G, and the X
        \\  coordinate of the resulting point is used as the ChaCha20 key.
        \\
        \\EXAMPLES:
        \\  vanity-cli --type p2pkh --prefix 777 --threads 8
        \\  vanity-cli --type eth --prefix DEAD --seed 12345678901234567890
        \\  vanity-cli --type p2wpkh --prefix zzz --seed-hex CAFEBABE
        \\  vanity-cli --config vanity_example.json
        \\
        \\VALID CHARACTERS BY TYPE:
        \\  Base58 (P2PKH/P2SH): 1-9, A-Z (no I,O), a-z (no l)
        \\  Bech32 (P2WPKH/P2TR): qpzry9x8gf2tvdw0s3jn54khce6mua7l
        \\  Hex (ETH): 0-9, a-f, A-F
        \\
    , .{}) catch {};
}

fn runCliMode(io: std.Io, stdout: *std.Io.Writer, allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    var addr_type: AddressType = .btc_p2pkh;
    var num_threads: u32 = 0;
    var max_attempts: u64 = 0;
    var case_sensitivity: CaseSensitivity = .insensitive;
    var stop_on_first: bool = false;
    var config_file: ?[]const u8 = null;
    var output_file_path: []const u8 = "vanity_results.txt";

    // ═══ NUEVOS: SEED MANUAL ═══
    var manual_seed: ?[]const u8 = null;
    var manual_seed_hex: ?[]const u8 = null;

    var rules_list: std.ArrayList(Rule) = .empty;
    defer rules_list.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(stdout);
            return;
        } else if (std.mem.eql(u8, arg, "--type")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            const val = args[i];
            if (std.mem.eql(u8, val, "p2pkh") or std.mem.eql(u8, val, "btc")) {
                addr_type = .btc_p2pkh;
            } else if (std.mem.eql(u8, val, "p2sh")) {
                addr_type = .btc_p2sh_p2wpkh;
            } else if (std.mem.eql(u8, val, "p2wpkh") or std.mem.eql(u8, val, "segwit")) {
                addr_type = .btc_p2wpkh;
            } else if (std.mem.eql(u8, val, "p2tr") or std.mem.eql(u8, val, "taproot")) {
                addr_type = .btc_p2tr;
            } else if (std.mem.eql(u8, val, "eth") or std.mem.eql(u8, val, "ethereum")) {
                addr_type = .eth;
            } else {
                try stdout.print("[ERROR] Invalid address type '{s}'\n", .{val});
                return error.InvalidAddressType;
            }
        } else if (std.mem.eql(u8, arg, "--threads")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            num_threads = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--max")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            max_attempts = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--sensitive")) {
            case_sensitivity = .sensitive;
        } else if (std.mem.eql(u8, arg, "--stop-first")) {
            stop_on_first = true;
        } else if (std.mem.eql(u8, arg, "--prefix")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            try rules_list.append(allocator, .{ .pattern = args[i], .mode = .starts_with });
        } else if (std.mem.eql(u8, arg, "--suffix")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            try rules_list.append(allocator, .{ .pattern = args[i], .mode = .ends_with });
        } else if (std.mem.eql(u8, arg, "--contains")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            try rules_list.append(allocator, .{ .pattern = args[i], .mode = .contains });
        } else if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            output_file_path = args[i];
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            config_file = args[i];
        }
        // ═══ NUEVOS FLAGS DE SEED ═══
        else if (std.mem.eql(u8, arg, "--seed")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            manual_seed = args[i];
            manual_seed_hex = null; // Decimal takes priority
        } else if (std.mem.eql(u8, arg, "--seed-hex")) {
            i += 1;
            if (i >= args.len) return error.MissingArgumentValue;
            var hex_val = args[i];
            // Strip "0x" prefix if present
            if (hex_val.len > 2 and std.mem.startsWith(u8, hex_val, "0x")) {
                hex_val = hex_val[2..];
            }
            manual_seed_hex = hex_val;
            manual_seed = null; // Hex takes priority
        }
    }

    // Load config file if provided
    if (config_file) |cfg_path| {
        try parseConfigFile(allocator, cfg_path, &rules_list, &addr_type, &num_threads, &case_sensitivity);
    }

    if (rules_list.items.len == 0) {
        try stdout.print("[ERROR] No search rules specified.\n", .{});
        return;
    }

    // Thread count validation
    const max_cpus: u32 = @intCast(@max(1, std.Thread.getCpuCount() catch 1));
    if (num_threads > max_cpus) {
        try stdout.print("[ERROR] Requested {d} threads exceeds CPU count ({d}).\n", .{ num_threads, max_cpus });
        return error.ThreadCountExceedsCpuCores;
    }

    // Validate patterns
    vanity.validator.validateRules(rules_list.items, addr_type) catch |err| {
        try stdout.print("[ERROR] Pattern validation failed: {}\n", .{err});
        return;
    };

    const config = VanityConfig{
        .address_type = addr_type,
        .num_threads = num_threads,
        .case_sensitivity = case_sensitivity,
        .rules = rules_list.items,
        .max_attempts = max_attempts,
        .stop_on_first = stop_on_first,
        .progress_interval = 100_000,
        .manual_seed = manual_seed,
        .manual_seed_hex = manual_seed_hex,
    };

    g_output_file_path = output_file_path;
    try runSearch(io, stdout, config, output_file_path);
}

// ─────────────────────────────────────────────────────────────────────────
// SHARED SEARCH RUNNER
// ─────────────────────────────────────────────────────────────────────────

fn runSearch(io: std.Io, stdout: *std.Io.Writer, config: VanityConfig, output_file_path: []const u8) !void {
    const max_cpus: u32 = @intCast(@max(1, std.Thread.getCpuCount() catch 1));
    const effective_threads = config.getEffectiveThreads();

    try stdout.print("\n==> STARTING VANITY SEARCH\n", .{});
    try stdout.print("================================================================\n", .{});
    try stdout.print("   Type      : {s}\n", .{@tagName(config.address_type)});
    try stdout.print("   Threads   : {d} / {d} cores\n", .{ effective_threads, max_cpus });
    try stdout.print("   Matching  : {s}\n", .{@tagName(config.case_sensitivity)});
    try stdout.print("   Max Keys  : {s}\n", .{if (config.max_attempts == 0) "unlimited" else "limited"});
    if (config.max_attempts > 0) {
        try stdout.print("   Max Count : {d}\n", .{config.max_attempts});
    }
    try stdout.print("   Stop Mode : {s}\n", .{if (config.stop_on_first) "first match" else "all matches"});
    try stdout.print("   Output    : {s}\n", .{output_file_path});

    // ═══ MOSTRAR SEED MANUAL ═══
    if (config.manual_seed) |seed| {
        try stdout.print("   Seed      : {s} (decimal) [DETERMINISTIC]\n", .{seed});
    } else if (config.manual_seed_hex) |seed| {
        try stdout.print("   Seed      : {s} (hex) [DETERMINISTIC]\n", .{seed});
    } else {
        try stdout.print("   Seed      : auto (non-deterministic)\n", .{});
    }

    try stdout.print("   Rules     : {d}\n", .{config.rules.len});
    for (config.rules, 0..) |rule, idx| {
        try stdout.print("     #{d}: {s} \"{s}\"\n", .{ idx + 1, @tagName(rule.mode), rule.pattern });
    }
    try stdout.print("================================================================\n", .{});
    try stdout.print("Searching... Press Ctrl+C to stop.\n\n", .{});
    try stdout.flush();

    g_start_clock = std.Io.Clock.awake.now(io);
    g_output_file_path = output_file_path;

    initOutputFile(output_file_path, &config) catch |err| {
        try stdout.print("[WARNING] Could not write to output file: {}\n", .{err});
    };

    var shared = SharedState.init(onProgress, onMatch);

    const total_found = vanity.search(config, &shared) catch |err| blk: {
        try stdout.print("\n[ERROR] Search failed: {}\n", .{err});
        break :blk shared.total_found.load(.acquire);
    };

    const duration = g_start_clock.untilNow(io, .awake);
    const elapsed_ns = duration.toNanoseconds();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const elapsed_ms = elapsed_s * 1000.0;
    const total_attempts = shared.total_attempts.load(.acquire);
    const keys_per_sec: u64 = if (elapsed_s > 0.001)
        @intFromFloat(@as(f64, @floatFromInt(total_attempts)) / elapsed_s)
    else
        total_attempts;

    try stdout.print("\n\n================================================================\n", .{});
    try stdout.print("[STATS] SEARCH COMPLETE\n", .{});
    try stdout.print("   Total Keys Searched : {d}\n", .{total_attempts});
    try stdout.print("   Total Matches Found : {d}\n", .{total_found});
    try stdout.print("   Time Elapsed        : {d:.2} ms ({d:.3} sec)\n", .{ elapsed_ms, elapsed_s });
    try stdout.print("   Average Speed       : {d} keys/sec\n", .{keys_per_sec});
    if (total_found > 0) {
        try stdout.print("   Results saved to    : {s}\n", .{output_file_path});
    }
    try stdout.print("================================================================\n\n", .{});
    try stdout.flush();
}

// ─────────────────────────────────────────────────────────────────────────
// CALLBACKS
// ─────────────────────────────────────────────────────────────────────────

fn onProgress(total_keys: u64, total_found: u32) void {
    const duration = g_start_clock.untilNow(g_io, .awake);
    const elapsed_ns = duration.toNanoseconds();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const speed: u64 = if (elapsed_s > 0.001)
        @intFromFloat(@as(f64, @floatFromInt(total_keys)) / elapsed_s)
    else
        0;

    var buf: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writer(g_io, &buf);
    const stdout = &writer.interface;

    stdout.print("\rKeys: {d:>12} | Found: {d:>4} | Speed: {d:>10} k/s | Time: {d:.1}s   ", .{
        total_keys,
        total_found,
        speed / 1000,
        elapsed_s,
    }) catch {};
    stdout.flush() catch {};
}

fn onMatch(result: *const vanity.VanityResult) void {
    const duration = g_start_clock.untilNow(g_io, .awake);
    const elapsed_ns = duration.toNanoseconds();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const keys_per_sec: u64 = if (elapsed_s > 0.001)
        @intFromFloat(@as(f64, @floatFromInt(result.attempts)) / elapsed_s)
    else
        result.attempts;

    const priv_hex = result.getPrivateKeyHex();

    var buf: [2048]u8 = undefined;
    var writer = std.Io.File.stdout().writer(g_io, &buf);
    const stdout = &writer.interface;

    stdout.print("\n\n*** MATCH FOUND! ***\n", .{}) catch {};
    stdout.print("   Address     : {s}\n", .{result.getAddress()}) catch {};
    stdout.print("   Private Key : {s}\n", .{&priv_hex}) catch {};
    stdout.print("   At Key #    : {d}\n", .{result.attempts}) catch {};
    stdout.print("   Speed       : {d} keys/sec\n", .{keys_per_sec}) catch {};
    stdout.print("\n", .{}) catch {};
    stdout.flush() catch {};

    appendResultToFile(g_output_file_path, result, elapsed_s, keys_per_sec) catch {};
}

// ─────────────────────────────────────────────────────────────────────────
// FILE I/O
// ─────────────────────────────────────────────────────────────────────────

fn initOutputFile(path: []const u8, config: *const VanityConfig) !void {
    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(g_io, path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try cwd.createFile(g_io, path, .{}),
        else => return err,
    };
    defer file.close(g_io);

    const offset = try file.length(g_io);

    var buf: [1024]u8 = undefined;
    const seed_info = if (config.manual_seed != null or config.manual_seed_hex != null)
        "DETERMINISTIC"
    else
        "NON-DETERMINISTIC";

    const header = std.fmt.bufPrint(&buf,
        \\================================================================
        \\ VANITY ADDRESS SEARCH - {s} - {d} rules - {s}
        \\================================================================
        \\
    , .{ @tagName(config.address_type), config.rules.len, seed_info }) catch return;
    try file.writePositionalAll(g_io, header, offset);
}

fn appendResultToFile(path: []const u8, result: *const vanity.VanityResult, elapsed_s: f64, keys_per_sec: u64) !void {
    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(g_io, path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try cwd.createFile(g_io, path, .{}),
        else => return err,
    };
    defer file.close(g_io);

    const offset = try file.length(g_io);

    var buf: [1024]u8 = undefined;
    const priv_hex = result.getPrivateKeyHex();
    const formatted = std.fmt.bufPrint(&buf,
        \\----------------------------------------------------------------
        \\ Address     : {s}
        \\ Private Key : {s}
        \\ At Key #    : {d}
        \\ Time        : {d:.3} sec
        \\ Speed       : {d} keys/sec
        \\
    , .{
        result.getAddress(),
        &priv_hex,
        result.attempts,
        elapsed_s,
        keys_per_sec,
    }) catch return error.BufferOverflow;

    try file.writePositionalAll(g_io, formatted, offset);
}

// ─────────────────────────────────────────────────────────────────────────
// BANNER
// ─────────────────────────────────────────────────────────────────────────

fn printBanner(stdout: *std.Io.Writer) !void {
    try stdout.print("\n", .{});
    try stdout.print("=========================================================\n", .{});
    try stdout.print("   SECP256K1 VANITY ADDRESS GENERATOR - Zig 0.16\n", .{});
    try stdout.print("   EC-based entropy extraction - No system RNG needed\n", .{});
    try stdout.print("=========================================================\n", .{});
    const cpus = std.Thread.getCpuCount() catch 0;
    try stdout.print("  System: {d} CPU cores available\n", .{cpus});
    try stdout.print("\n", .{});
}

// ─────────────────────────────────────────────────────────────────────────
// JSON CONFIG PARSER
// ─────────────────────────────────────────────────────────────────────────

fn parseConfigFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    rules: *std.ArrayList(Rule),
    addr_type: *AddressType,
    num_threads: *u32,
    case_sensitivity: *CaseSensitivity,
) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(g_io, path, .{});
    defer file.close(g_io);

    const stat = try file.stat(g_io);
    const content = try allocator.alloc(u8, stat.size);
    defer allocator.free(content);

    _ = try file.readPositionalAll(g_io, content, 0);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    if (root.object.get("address_type")) |val| {
        if (val == .string) {
            if (std.mem.eql(u8, val.string, "p2pkh") or std.mem.eql(u8, val.string, "btc")) {
                addr_type.* = .btc_p2pkh;
            } else if (std.mem.eql(u8, val.string, "p2sh")) {
                addr_type.* = .btc_p2sh_p2wpkh;
            } else if (std.mem.eql(u8, val.string, "p2wpkh")) {
                addr_type.* = .btc_p2wpkh;
            } else if (std.mem.eql(u8, val.string, "p2tr")) {
                addr_type.* = .btc_p2tr;
            } else if (std.mem.eql(u8, val.string, "eth")) {
                addr_type.* = .eth;
            }
        }
    }

    if (root.object.get("threads")) |val| {
        if (val == .integer) {
            num_threads.* = @intCast(val.integer);
        }
    }

    if (root.object.get("case_sensitive")) |val| {
        if (val == .bool) {
            case_sensitivity.* = if (val.bool) .sensitive else .insensitive;
        }
    }

    if (root.object.get("rules")) |rules_val| {
        if (rules_val == .array) {
            for (rules_val.array.items) |r_item| {
                if (r_item == .object) {
                    const pattern_str = if (r_item.object.get("pattern")) |p| (if (p == .string) p.string else continue) else continue;
                    const mode_str = if (r_item.object.get("mode")) |m| (if (m == .string) m.string else "starts_with") else "starts_with";

                    var mode: MatchMode = .starts_with;
                    if (std.mem.eql(u8, mode_str, "ends_with") or std.mem.eql(u8, mode_str, "suffix")) {
                        mode = .ends_with;
                    } else if (std.mem.eql(u8, mode_str, "contains")) {
                        mode = .contains;
                    }

                    const pattern_dup = try allocator.dupe(u8, pattern_str);
                    try rules.append(allocator, .{ .pattern = pattern_dup, .mode = mode });
                }
            }
        }
    }
}
