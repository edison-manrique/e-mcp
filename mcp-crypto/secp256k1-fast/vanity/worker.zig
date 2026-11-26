const std = @import("std");
const cfg = @import("config.zig");
const VanityConfig = cfg.VanityConfig;
const VanityResult = cfg.VanityResult;
const AddressType = cfg.AddressType;
const Scalar256 = @import("../scalar/root.zig").Scalar256;
const Point = @import("../point/root.zig").Point;
const AffinePoint = @import("../point/root.zig").AffinePoint;
const generator = @import("../generator/root.zig");
const btc_addr = @import("../address/btc.zig");
const eth_addr = @import("../address/eth.zig");
const ChaCha20Rng = @import("../rng/chacha20.zig").ChaCha20Rng;

pub const MAX_RESULTS: usize = 1024;

/// Batch size: amortiza 1 `mulG` (≈73 µs) entre muchos candidatos.
/// 128 es el máximo que soporta `Point.batchToAffine` (buffer interno [128]).
const BATCH_SIZE: usize = 128;

pub const SharedState = struct {
    stop: std.atomic.Value(bool),
    total_attempts: std.atomic.Value(u64),
    total_found: std.atomic.Value(u32),
    results: [MAX_RESULTS]VanityResult,
    on_progress: ?*const fn (u64, u32) void,
    on_match: ?*const fn (*const VanityResult) void,

    pub fn init(
        on_progress: ?*const fn (u64, u32) void,
        on_match: ?*const fn (*const VanityResult) void,
    ) SharedState {
        return SharedState{
            .stop = std.atomic.Value(bool).init(false),
            .total_attempts = std.atomic.Value(u64).init(0),
            .total_found = std.atomic.Value(u32).init(0),
            .results = std.mem.zeroes([MAX_RESULTS]VanityResult),
            .on_progress = on_progress,
            .on_match = on_match,
        };
    }

    pub fn requestStop(self: *SharedState) void {
        self.stop.store(true, .release);
    }
};

pub const WorkerCtx = struct {
    config: *const VanityConfig,
    shared: *SharedState,
    thread_id: u32,
};

fn compressPubkey(aff: AffinePoint, out: *[33]u8) void {
    out[0] = if (aff.y.isOdd()) 0x03 else 0x02;
    aff.x.toBytes(out[1..33]);
}

fn uncompressPubkey(aff: AffinePoint, out: *[65]u8) void {
    out[0] = 0x04;
    aff.x.toBytes(out[1..33]);
    aff.y.toBytes(out[33..65]);
}

fn deriveAddress(aff: AffinePoint, addr_type: AddressType, addr_buf: *[128]u8) !usize {
    switch (addr_type) {
        .btc_p2pkh => {
            var pub33: [33]u8 = undefined;
            compressPubkey(aff, &pub33);
            return (try btc_addr.p2pkh(&pub33, addr_buf)).len;
        },
        .btc_p2sh_p2wpkh => {
            var pub33: [33]u8 = undefined;
            compressPubkey(aff, &pub33);
            return (try btc_addr.p2sh_p2wpkh(&pub33, addr_buf)).len;
        },
        .btc_p2wpkh => {
            var pub33: [33]u8 = undefined;
            compressPubkey(aff, &pub33);
            return (try btc_addr.p2wpkh(&pub33, addr_buf)).len;
        },
        .btc_p2tr => {
            var pub33: [33]u8 = undefined;
            compressPubkey(aff, &pub33);
            return (try btc_addr.p2tr(&pub33, addr_buf)).len;
        },
        .eth => {
            var pub65: [65]u8 = undefined;
            uncompressPubkey(aff, &pub65);
            return (try eth_addr.ethAddress(&pub65, addr_buf)).len;
        },
    }
}

/// Worker optimizado: offsets en afín + addMixed + Montgomery batch inverse
pub fn workerFn(ctx: WorkerCtx) void {
    const config = ctx.config;
    const shared = ctx.shared;

    var csprng = ChaCha20Rng.init(.{
        .manual_seed = config.manual_seed,
        .manual_seed_hex = config.manual_seed_hex,
        .extra_entropy = config.extra_entropy,
        .thread_id = ctx.thread_id,
    });

    // Precomputar offsets aleatorios en forma AFÍN (una vez por hilo)
    // addMixed es ~30% más rápido que add (Jacobian + Affine vs Jacobian + Jacobian)
    var off_scalar: [BATCH_SIZE]Scalar256 = undefined;
    var off_affine: [BATCH_SIZE]AffinePoint = undefined;
    for (0..BATCH_SIZE) |j| {
        off_scalar[j] = csprng.generateScalar256();
        off_affine[j] = generator.mulG(off_scalar[j]).toAffine();
    }

    var local_attempts: u64 = 0;
    const batch_report = config.progress_interval;

    // Buffers para batch processing
    var batch_points: [BATCH_SIZE]Point = undefined;
    var batch_affine: [BATCH_SIZE]AffinePoint = undefined;
    var batch_scalars: [BATCH_SIZE]Scalar256 = undefined;

    while (!shared.stop.load(.acquire)) {
        if (config.max_attempts > 0) {
            const total = shared.total_attempts.load(.monotonic);
            if (total >= config.max_attempts) {
                shared.requestStop();
                break;
            }
        }

        // Nueva base por cada batch (en Jacobian)
        const base_scalar = csprng.generateScalar256();
        const base_point = generator.mulG(base_scalar);

        // Acumular BATCH_SIZE puntos usando addMixed (base_jacobian + offset_affine)
        // Esto es ~30% más rápido que add (jacobian + jacobian)
        for (0..BATCH_SIZE) |j| {
            batch_scalars[j] = base_scalar.add(off_scalar[j]);
            batch_points[j] = base_point.addMixed(off_affine[j].x, off_affine[j].y);
        }

        // Montgomery batch inverse: 1 inversión para todo el batch
        Point.batchToAffine(&batch_points, &batch_affine);

        // Procesar cada punto del batch
        for (0..BATCH_SIZE) |j| {
            if (shared.stop.load(.acquire)) return;

            var addr_buf: [128]u8 = undefined;
            const addr_len = deriveAddress(batch_affine[j], config.address_type, &addr_buf) catch {
                local_attempts += 1;
                continue;
            };

            const address = addr_buf[0..addr_len];

            for (config.rules, 0..) |*rule, rule_idx| {
                if (rule.matches(address, config.address_type, config.case_sensitivity)) {
                    const found_idx = shared.total_found.fetchAdd(1, .seq_cst);

                    if (found_idx < MAX_RESULTS) {
                        var res = VanityResult{
                            .private_key = undefined,
                            .address = undefined,
                            .address_len = addr_len,
                            .matched_rule = rule_idx,
                            .attempts = shared.total_attempts.load(.monotonic) + local_attempts,
                        };
                        batch_scalars[j].toBytes(&res.private_key);
                        @memcpy(res.address[0..addr_len], address);
                        shared.results[found_idx] = res;
                        if (shared.on_match) |cb| cb(&shared.results[found_idx]);
                    }

                    if (config.stop_on_first) {
                        shared.requestStop();
                        return;
                    }
                    break;
                }
            }

            local_attempts += 1;

            if (local_attempts % batch_report == 0) {
                _ = shared.total_attempts.fetchAdd(batch_report, .monotonic);
                if (shared.on_progress) |cb| {
                    cb(shared.total_attempts.load(.monotonic), shared.total_found.load(.monotonic));
                }
            }
        }
    }

    _ = shared.total_attempts.fetchAdd(local_attempts % batch_report, .monotonic);
}
