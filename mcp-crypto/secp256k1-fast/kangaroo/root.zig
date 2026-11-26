const std = @import("std");
const builtin = @import("builtin");
const field = @import("../field/root.zig");
const scalar = @import("../scalar/root.zig");
const point = @import("../point/root.zig");

const config_mod = @import("config.zig");
const utils_mod = @import("utils.zig");
const jump_table_mod = @import("jump_table.zig");
const state_mod = @import("state.zig");
const worker_mod = @import("worker.zig");

const BigInt256 = field.BigInt256;
const Point = point.Point;

pub const KangarooConfig = config_mod.KangarooConfig;
pub const KangarooResult = config_mod.KangarooResult;
const OptimalParams = config_mod.OptimalParams;
const JumpTable = jump_table_mod.JumpTable;
const SharedState = state_mod.SharedState;

/// ═══════════════════════════════════════════════════════════════════════════
///  source/kangaroo/root.zig — Kangaroo Module Public API
/// ═══════════════════════════════════════════════════════════════════════════

// ── Re-exports de tipos para uso externo ──
pub const config = config_mod;
pub const utils = utils_mod;
pub const jump_table = jump_table_mod;
pub const state = state_mod;
pub const worker = worker_mod;

pub const KangarooType = config_mod.KangarooType;
pub const DistinguishedPoint = config_mod.DistinguishedPoint;
pub const ConfigError = config_mod.ConfigError;
pub const Jump = jump_table_mod.Jump;
pub const WalkerState = state_mod.WalkerState;
pub const DPMap = state_mod.DPMap;

/// Error de la API Kangaroo
pub const KangarooError = error{
    InvalidConfig,
    ThreadSpawnFailed,
    AllocationFailed,
    NoSolution,
};

/// Resuelve el logaritmo discreto de forma síncrona.
/// Retorna la clave privada si se encuentra, o null si no hay solución
/// dentro del límite de iteraciones.
pub fn solve(allocator: std.mem.Allocator, cfg: *const KangarooConfig) KangarooError!?KangarooResult {
    // 1. Validar configuración
    config_mod.validateConfig(cfg) catch return error.InvalidConfig;

    const start_ns = nowNano();

    // 2. Calcular parámetros óptimos
    const range_size = cfg.getRangeSize();
    const num_threads = cfg.getEffectiveThreads();
    var params = config_mod.calculateOptimalParams(range_size, num_threads);

    // Sobrescribir con valores del usuario si están definidos
    if (cfg.distinguished_bits > 0) params.distinguished_bits = cfg.distinguished_bits;
    if (cfg.jump_table_size > 0) params.jump_table_size = cfg.jump_table_size;
    if (cfg.max_iterations > 0) params.max_iterations = cfg.max_iterations;

    // 3. Crear tabla de saltos (determinística si hay seed)
    var jt = JumpTable.init(
        allocator,
        params.avg_jump_distance,
        params.jump_table_size,
        cfg.manual_seed,
        cfg.manual_seed_hex,
    ) catch return error.AllocationFailed;
    defer jt.deinit();

    // 4. Crear máscara de puntos distinguidos
    const dp_mask = utils_mod.generateDistinguishedMask(params.distinguished_bits);

    // 5. Crear estado compartido
    var shared = SharedState.init(
        allocator,
        cfg.target_point,
        cfg.range_min,
        cfg.range_max,
        &jt,
        dp_mask,
        params.max_iterations,
        num_threads,
        cfg.on_progress,
        cfg.on_solution,
    );
    defer shared.deinit();

    // 6. Lanzar workers
    var threads = allocator.alloc(std.Thread, num_threads) catch return error.AllocationFailed;
    defer allocator.free(threads);

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, worker_mod.workerFn, .{ &shared, @as(u32, @intCast(i)) }) catch
            return error.ThreadSpawnFailed;
    }

    // 7. Esperar a que terminen
    for (threads) |*t| t.join();

    // 8. Construir resultado
    const elapsed_s = @as(f64, @floatFromInt(nowNano() - start_ns)) / 1_000_000_000.0;

    if (shared.hasSolution()) {
        return KangarooResult{
            .private_key = shared.getSolution(),
            .iterations = shared.total_iterations.load(.monotonic),
            .elapsed_seconds = elapsed_s,
            .distinguished_points = shared.total_distinguished.load(.monotonic),
        };
    }

    return null;
}

/// Handle para ejecución asíncrona
pub const KangarooHandle = struct {
    thread: std.Thread,
    result_ptr: *?KangarooResult,
    allocator: std.mem.Allocator,

    /// Espera a que termine y retorna el resultado
    pub fn join(self: *KangarooHandle) ?KangarooResult {
        self.thread.join();
        const res = self.result_ptr.*;
        self.allocator.destroy(self.result_ptr);
        return res;
    }

    /// Verifica si ya terminó (no bloqueante)
    pub fn isRunning(self: *KangarooHandle) bool {
        _ = self;
        return true; // simplificado; usar join() para bloquear
    }
};

/// Resuelve de forma asíncrona. Retorna un handle para hacer join() después.
/// Los callbacks on_progress / on_solution se invocan desde el thread de trabajo.
pub fn solveAsync(allocator: std.mem.Allocator, cfg: *const KangarooConfig) KangarooError!*KangarooHandle {
    const result_ptr = allocator.create(?KangarooResult) catch return error.AllocationFailed;
    result_ptr.* = null;

    const Ctx = struct {
        allocator: std.mem.Allocator,
        cfg: KangarooConfig,
        result_ptr: *?KangarooResult,

        fn run(ctx: *@This()) void {
            ctx.result_ptr.* = solve(ctx.allocator, &ctx.cfg) catch null;
        }
    };

    const ctx = allocator.create(Ctx) catch return error.AllocationFailed;
    ctx.* = .{ .allocator = allocator, .cfg = cfg.*, .result_ptr = result_ptr };

    const thread = std.Thread.spawn(.{}, Ctx.run, .{ctx}) catch return error.ThreadSpawnFailed;

    const handle = allocator.create(KangarooHandle) catch return error.AllocationFailed;
    handle.* = .{
        .thread = thread,
        .result_ptr = result_ptr,
        .allocator = allocator,
    };

    return handle;
}

/// Conveniencia: resuelve con configuración por defecto y retorna solo la clave.
pub fn solveKey(allocator: std.mem.Allocator, target: Point, range_min: BigInt256, range_max: BigInt256) KangarooError!?BigInt256 {
    const cfg = KangarooConfig{
        .range_min = range_min,
        .range_max = range_max,
        .target_point = target,
    };
    const res = try solve(allocator, &cfg);
    if (res) |r| return r.private_key;
    return null;
}

/// Timestamp en nanosegundos (cross-platform, para medir elapsed)
fn nowNano() u64 {
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
        return @divTrunc(c *% 1_000_000_000, f); // ← ticks → nanosegundos reales
    } else if (builtin.os.tag == .linux) {
        var ts: std.os.linux.timespec = undefined;
        const rc = std.os.linux.clock_gettime(.MONOTONIC, &ts);
        if (rc == 0) {
            return @as(u64, @intCast(ts.sec)) *% 1_000_000_000 +% @as(u64, @intCast(ts.nsec));
        }
        return 0;
    } else {
        var dummy: u8 = undefined;
        return @intFromPtr(&dummy);
    }
}
