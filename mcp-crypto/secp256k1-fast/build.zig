const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Modo de optimizacion (por defecto: fast)") orelse .fast;

    const secp = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
    });

    const vanity = cliExe(b, "vanity-cli", "apps/vanity_cli.zig", secp, target, optimize);
    const kangaroo = cliExe(b, "kangaroo-cli", "apps/kangaroo_cli.zig", secp, target, optimize);
    b.installArtifact(vanity);
    b.installArtifact(kangaroo);

    const run_vanity = b.addRunArtifact(vanity);
    run_vanity.addPassthruArgs();
    b.step("vanity", "Ejecuta la CLI de direcciones vanity (nativa)").dependOn(&run_vanity.step);

    const run_kangaroo = b.addRunArtifact(kangaroo);
    run_kangaroo.addPassthruArgs();
    b.step("kangaroo", "Ejecuta la CLI de Kangaroo / puzzle (nativa)").dependOn(&run_kangaroo.step);

    const linux_target = crossTarget(b, .linux);
    const windows_target = crossTarget(b, .windows);

    const vanity_linux = cliCross(b, "vanity-cli-linux-x86_64", "apps/vanity_cli.zig", linux_target, "linux");
    const vanity_windows = cliCross(b, "vanity-cli-windows-x86_64", "apps/vanity_cli.zig", windows_target, "windows");
    const kangaroo_linux = cliCross(b, "kangaroo-cli-linux-x86_64", "apps/kangaroo_cli.zig", linux_target, "linux");
    const kangaroo_windows = cliCross(b, "kangaroo-cli-windows-x86_64", "apps/kangaroo_cli.zig", windows_target, "windows");

    const linux_step = b.step("linux", "Compila las CLIs para Linux x86_64 (musl)");
    linux_step.dependOn(vanity_linux);
    linux_step.dependOn(kangaroo_linux);

    const windows_step = b.step("windows", "Compila las CLIs para Windows x86_64 (gnu)");
    windows_step.dependOn(vanity_windows);
    windows_step.dependOn(kangaroo_windows);

    const cross_step = b.step("cross", "Compila las CLIs para Linux x86_64 + Windows x86_64");
    cross_step.dependOn(vanity_linux);
    cross_step.dependOn(kangaroo_linux);
    cross_step.dependOn(vanity_windows);
    cross_step.dependOn(kangaroo_windows);

    const test_mod = b.createModule(.{ .root_source_file = b.path("pruebas.zig"), .target = target });
    const lib_tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Ejecuta los tests de la libreria (rng + bigint)").dependOn(&b.addRunArtifact(lib_tests).step);
}

fn cliExe(
    b: *std.Build,
    name: []const u8,
    src: []const u8,
    secp: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "secp256k1", .module = secp }},
        }),
    });
}

fn cliCross(
    b: *std.Build,
    name: []const u8,
    src: []const u8,
    target: std.Build.ResolvedTarget,
    dir: []const u8,
) *std.Build.Step {
    const secp = b.createModule(.{ .root_source_file = b.path("root.zig"), .target = target });
    const exe = cliExe(b, name, src, secp, target, .fast);
    const inst = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = dir } } });
    return &inst.step;
}

fn crossTarget(b: *std.Build, os: std.Target.Os.Tag) std.Build.ResolvedTarget {
    var q = std.Target.Query{
        .cpu_arch = .x86_64,
        .os_tag = os,
        .abi = if (os == .linux) .musl else .gnu,
    };
    q.cpu_features_add = std.Target.x86.featureSet(&.{ .bmi2, .adx, .lzcnt, .popcnt });
    return b.resolveTargetQuery(q);
}
