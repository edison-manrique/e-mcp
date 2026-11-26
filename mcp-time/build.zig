const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Modo de optimizacion (por defecto: fast)") orelse .fast;

    const proto_mod = b.createModule(.{
        .root_source_file = b.path("../shared/proto.zig"),
        .target = target,
    });

    const mod = b.addModule("mcp_time", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{.{ .name = "proto", .module = proto_mod }},
    });

    const exe = b.addExecutable(.{
        .name = "world-time",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mcp_time", .module = mod },
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

    const linux = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl });
    const proto_linux = b.createModule(.{ .root_source_file = b.path("../shared/proto.zig"), .target = linux });
    const exe_unix = b.addExecutable(.{
        .name = "world-time",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = linux,
            .optimize = optimize,
            .imports = &.{.{ .name = "proto", .module = proto_linux }},
        }),
    });
    const inst_unix = b.addInstallArtifact(exe_unix, .{ .dest_dir = .{ .override = .{ .custom = "unix" } } });
    b.step("unix", "Cross-compila a Linux x86_64 (musl)").dependOn(&inst_unix.step);
}
