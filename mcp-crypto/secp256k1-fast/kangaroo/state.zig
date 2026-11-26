const std = @import("std");
const field = @import("../field/root.zig");
const point = @import("../point/root.zig");
const config = @import("config.zig");
const utils = @import("utils.zig");
const jump_table = @import("jump_table.zig");

const BigInt256 = field.BigInt256;
const Point = point.Point;
const KangarooType = config.KangarooType;
const DistinguishedPoint = config.DistinguishedPoint;
const KangarooResult = config.KangarooResult;
const JumpTable = jump_table.JumpTable;

/// ═══════════════════════════════════════════════════════════════════════════
///  source/kangaroo/state.zig — Worker State & Shared Data
/// ═══════════════════════════════════════════════════════════════════════════
/// SpinLock simple basado en atómicos (compatible con Zig 0.16)
pub const SpinLock = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub inline fn lock(self: *SpinLock) void {
        while (self.state.swap(true, .acquire)) {
            std.Thread.yield() catch {};
        }
    }

    pub inline fn unlock(self: *SpinLock) void {
        self.state.store(false, .release);
    }
};

/// Estado de un walker individual (kangaroo tame o wild)
pub const WalkerState = struct {
    /// Coordenada X afín actual
    x: BigInt256,
    /// Coordenada Y afín actual
    y: BigInt256,
    /// Distancia acumulada recorrida
    d: BigInt256,
    /// Tipo de walker (tame o wild)
    t: KangarooType,

    /// Inicializa un walker tame en una distancia dada
    pub fn initTame(x: BigInt256, y: BigInt256, distance: BigInt256) WalkerState {
        return WalkerState{
            .x = x,
            .y = y,
            .d = distance,
            .t = .Tame,
        };
    }

    /// Inicializa un walker wild (target + salto)
    pub fn initWild(x: BigInt256, y: BigInt256, distance: BigInt256) WalkerState {
        return WalkerState{
            .x = x,
            .y = y,
            .d = distance,
            .t = .Wild,
        };
    }

    /// Aplica un salto al walker (actualiza distancia)
    pub fn applyJump(self: *WalkerState, new_x: BigInt256, new_y: BigInt256, jump_d: BigInt256) void {
        self.x = new_x;
        self.y = new_y;
        self.d = self.d.add(jump_d).result;
    }
};

/// Mapa thread-safe de puntos distinguidos
pub const DPMap = struct {
    mutex: SpinLock,
    map: std.HashMap(BigInt256, DistinguishedPoint, utils.BigIntContext, 80),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DPMap {
        return DPMap{
            .mutex = SpinLock{},
            .map = std.HashMap(BigInt256, DistinguishedPoint, utils.BigIntContext, 80).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DPMap) void {
        self.map.deinit();
    }

    /// Inserta o verifica un punto distinguido.
    /// Retorna:
    ///   .{ .collision = false }  → insertado sin colisión
    ///   .{ .collision = true, .existing = dp } → colisión con dp existente
    pub const InsertResult = struct {
        collision: bool,
        existing: ?DistinguishedPoint = null,
    };

    pub fn insert(self: *DPMap, dp: DistinguishedPoint) InsertResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.get(dp.x)) |existing| {
            return .{ .collision = true, .existing = existing };
        } else {
            self.map.put(dp.x, dp) catch {};
            return .{ .collision = false };
        }
    }

    /// Elimina un punto (usado cuando la colisión es del mismo tipo)
    pub fn remove(self: *DPMap, x: BigInt256) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.map.remove(x);
    }

    /// Obtiene el número de puntos distinguidos almacenados
    pub fn count(self: *DPMap) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return @intCast(self.map.count());
    }
};

/// Estado compartido entre todos los workers
pub const SharedState = struct {
    /// Flag para detener todos los workers
    stop: std.atomic.Value(bool),

    /// Total de iteraciones realizadas por todos los workers
    total_iterations: std.atomic.Value(u64),

    /// Total de puntos distinguidos encontrados
    total_distinguished: std.atomic.Value(u32),

    /// Solución encontrada (clave privada)
    solution: std.atomic.Value(bool),

    /// Clave privada encontrada (protegida por mutex de solución)
    solution_key: BigInt256,

    /// Mutex para proteger la escritura de la solución
    solution_mutex: SpinLock,

    /// Mapa de puntos distinguidos
    dp_map: DPMap,

    /// Punto objetivo
    target_point: Point,

    /// Rango de búsqueda
    range_min: BigInt256,
    range_max: BigInt256,

    /// Tabla de saltos compartida
    jump_table: *const JumpTable,

    /// Máscara para puntos distinguidos
    dp_mask: BigInt256,

    /// Máximo de iteraciones
    max_iterations: u64,

    /// Número total de workers
    total_workers: u32,

    /// Callbacks
    on_progress: ?*const fn (u64, u32) void,
    on_solution: ?*const fn (*const KangarooResult) void,

    pub fn init(
        allocator: std.mem.Allocator,
        target_point: Point,
        range_min: BigInt256,
        range_max: BigInt256,
        jt: *const JumpTable,
        dp_mask: BigInt256,
        max_iterations: u64,
        total_workers: u32,
        on_progress: ?*const fn (u64, u32) void,
        on_solution: ?*const fn (*const KangarooResult) void,
    ) SharedState {
        return SharedState{
            .stop = std.atomic.Value(bool).init(false),
            .total_iterations = std.atomic.Value(u64).init(0),
            .total_distinguished = std.atomic.Value(u32).init(0),
            .solution = std.atomic.Value(bool).init(false),
            .solution_key = BigInt256.zero,
            .solution_mutex = SpinLock{},
            .dp_map = DPMap.init(allocator),
            .target_point = target_point,
            .range_min = range_min,
            .range_max = range_max,
            .jump_table = jt,
            .dp_mask = dp_mask,
            .max_iterations = max_iterations,
            .total_workers = total_workers,
            .on_progress = on_progress,
            .on_solution = on_solution,
        };
    }

    pub fn deinit(self: *SharedState) void {
        self.dp_map.deinit();
    }

    /// Solicita detener todos los workers
    pub fn requestStop(self: *SharedState) void {
        self.stop.store(true, .release);
    }

    /// Verifica si se debe detener
    pub fn shouldStop(self: *SharedState) bool {
        return self.stop.load(.acquire);
    }

    /// Verifica si ya se encontró solución
    pub fn hasSolution(self: *SharedState) bool {
        return self.solution.load(.acquire);
    }

    /// Guarda la solución encontrada (thread-safe)
    pub fn setSolution(self: *SharedState, key: BigInt256) void {
        self.solution_mutex.lock();
        defer self.solution_mutex.unlock();

        if (!self.solution.load(.acquire)) {
            self.solution_key = key;
            self.solution.store(true, .release);
            self.requestStop();
        }
    }

    /// Obtiene la solución (debe llamarse después de hasSolution())
    pub fn getSolution(self: *SharedState) BigInt256 {
        self.solution_mutex.lock();
        defer self.solution_mutex.unlock();
        return self.solution_key;
    }

    /// Reporta progreso (llamado periódicamente)
    pub fn reportProgress(self: *SharedState, iterations: u64) void {
        _ = self.total_iterations.fetchAdd(iterations, .monotonic);
        if (self.on_progress) |cb| {
            cb(self.total_iterations.load(.monotonic), self.total_distinguished.load(.monotonic));
        }
    }

    /// Incrementa contador de puntos distinguidos
    pub fn addDistinguished(self: *SharedState) void {
        _ = self.total_distinguished.fetchAdd(1, .monotonic);
    }
};
