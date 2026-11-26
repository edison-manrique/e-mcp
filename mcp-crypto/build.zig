const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Modo de optimizacion (por defecto: fast)") orelse .fast;

    const proto_mod = b.createModule(.{
        .root_source_file = b.path("../shared/proto.zig"),
        .target = target,
    });
    const secp_mod = b.createModule(.{
        .root_source_file = b.path("secp256k1-fast/root.zig"),
        .target = target,
    });
    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "secp", .module = secp_mod },
            .{ .name = "proto", .module = proto_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "mcp-crypto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mcp_crypto", .module = mod },
                .{ .name = "proto", .module = proto_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Ejecuta el binario (servidor MCP o CLI)").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Corre los tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
    const secp_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("secp256k1-fast/pruebas.zig"), .target = target }),
    });
    test_step.dependOn(&b.addRunArtifact(secp_tests).step);

    var q = std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl };
    q.cpu_features_add = std.Target.x86.featureSet(&.{ .bmi2, .adx, .lzcnt, .popcnt });
    const linux = b.resolveTargetQuery(q);

    const proto_unix = b.createModule(.{ .root_source_file = b.path("../shared/proto.zig"), .target = linux });
    const secp_unix = b.createModule(.{ .root_source_file = b.path("secp256k1-fast/root.zig"), .target = linux });
    const mod_unix = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = linux,
        .imports = &.{
            .{ .name = "secp", .module = secp_unix },
            .{ .name = "proto", .module = proto_unix },
        },
    });
    const exe_unix = b.addExecutable(.{
        .name = "mcp-crypto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = linux,
            .optimize = .fast,
            .imports = &.{
                .{ .name = "mcp_crypto", .module = mod_unix },
                .{ .name = "proto", .module = proto_unix },
            },
        }),
    });
    const inst_unix = b.addInstallArtifact(exe_unix, .{ .dest_dir = .{ .override = .{ .custom = "unix" } } });
    b.step("unix", "Cross-compila a Linux x86_64 (musl) fast").dependOn(&inst_unix.step);
}
