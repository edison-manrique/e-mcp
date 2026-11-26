const std = @import("std");

// Grafo de compilación del MCP de criptografía (mcp-crypto).
//
//   - `secp`  : la librería secp256k1 real (raíz: secp256k1-fast/root.zig).
//   - `mcp_crypto` : el paquete MCP (dominio puro en src/bc/, sin IO).
//   - exe `mcp-crypto` : servidor MCP por stdio o CLI efímero.
//
// Por defecto optimiza ReleaseFast (este servidor busca velocidad).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // ReleaseFast POR DEFECTO.
    //
    // Antes se usaba `standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast })`,
    // pero esa función devuelve .Debug salvo que se pase `-Drelease`/`--release`.
    // Resultado: `zig build` a secas compilaba el servidor en Debug y las
    // operaciones de curva iban ~5x más lentas (vanity: ~80 k/s en vez de ~1 M/s).
    //
    //   zig build                  -> ReleaseFast
    //   zig build --release=safe   -> ReleaseSafe
    //   zig build -Doptimize=Debug -> Debug
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Modo de optimización (por defecto: ReleaseFast)") orelse .ReleaseFast;

    // ---------- Módulo de la librería criptográfica ----------
    const secp_mod = b.createModule(.{
        .root_source_file = b.path("secp256k1-fast/root.zig"),
        .target = target,
    });

    // ---------- Módulo del paquete MCP ----------
    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("secp", secp_mod);

    // ---------- Ejecutable ----------
    const exe = b.addExecutable(.{
        .name = "mcp-crypto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mcp_crypto", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Ejecuta el binario (servidor MCP o CLI)");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    // ---------- Tests ----------
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    // Tests de la librería (motor de entropía, ChaCha20): viven en su propio
    // módulo, así que necesitan su propia raíz de test.
    const secp_test_mod = b.createModule(.{
        .root_source_file = b.path("secp256k1-fast/pruebas.zig"),
        .target = target,
    });
    const secp_tests = b.addTest(.{ .root_module = secp_test_mod });
    const run_secp_tests = b.addRunArtifact(secp_tests);
    const test_step = b.step("test", "Corre los tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_secp_tests.step);

    // ---------- Cross-compile a Linux x86_64 (musl) con BMI2/ADX ----------
    // Queda en zig-out/unix/mcp-crypto (no pisa el binario local).
    var q = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    };
    q.cpu_features_add = std.Target.x86.featureSet(&.{ .bmi2, .adx, .lzcnt, .popcnt });
    const linux = b.resolveTargetQuery(q);

    const secp_unix = b.createModule(.{
        .root_source_file = b.path("secp256k1-fast/root.zig"),
        .target = linux,
    });
    const mod_unix = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = linux,
    });
    mod_unix.addImport("secp", secp_unix);

    const exe_unix = b.addExecutable(.{
        .name = "mcp-crypto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = linux,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "mcp_crypto", .module = mod_unix },
            },
        }),
    });
    const inst_unix = b.addInstallArtifact(exe_unix, .{
        .dest_dir = .{ .override = .{ .custom = "unix" } },
    });
    const unix_step = b.step("unix", "Cross-compila a Linux x86_64 (musl) ReleaseFast");
    unix_step.dependOn(&inst_unix.step);
}
