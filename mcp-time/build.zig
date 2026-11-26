const std = @import("std");

// Describe el grafo de compilación: módulo de librería, ejecutable MCP/CLI,
// suites de test y un cross-compile a Linux/musl (paso `unix`).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // ReleaseFast POR DEFECTO: `standardOptimizeOption(.{})` devuelve Debug
    // salvo `-Doptimize`/`--release`, y aqui la velocidad pesa mas que el tamano.
    //   zig build -> ReleaseFast | --release=safe -> ReleaseSafe | -Doptimize=Debug -> Debug
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Modo de optimizacion (por defecto: ReleaseFast)") orelse .ReleaseFast;

    // Módulo de librería (puerta: src/root.zig). Reutilizable sin lanzar proceso.
    const mod = b.addModule("mcp_time", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Ejecutable `world-time` (nombre de compatibilidad con instalaciones y
    // con el orquestador). Entrada delgada: src/main.zig.
    const exe = b.addExecutable(.{
        .name = "world-time",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mcp_time", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Ejecuta el binario (servidor MCP o CLI)");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    // Tests: módulo de librería + módulo del ejecutable.
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Corre los tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Cross-compile a Linux x86_64 (musl): `zig build unix`.
    // Queda en zig-out/unix/world-time (no pisa el binario local).
    const linux = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl });
    const exe_unix = b.addExecutable(.{
        .name = "world-time",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = linux,
            .optimize = optimize,
        }),
    });
    const inst_unix = b.addInstallArtifact(exe_unix, .{
        .dest_dir = .{ .override = .{ .custom = "unix" } },
    });
    const unix_step = b.step("unix", "Cross-compila a Linux x86_64 (musl)");
    unix_step.dependOn(&inst_unix.step);
}
