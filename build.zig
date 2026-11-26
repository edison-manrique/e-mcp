const std = @import("std");

/// Grafo de compilación raíz para `e-mcp` (Zig 0.17.0).
/// Ejecuta `zig build test` para correr todas las pruebas unitarias del repo.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const proto_mod = b.createModule(.{
        .root_source_file = b.path("shared/proto.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Corre todas las pruebas unitarias del repositorio");

    const standalone_tests = [_][]const u8{
        "shared/proto.zig",
        "emcp/src/registro.zig",
        "emcp/src/core/args.zig",
        "emcp/src/core/jsonw.zig",
        "emcp/src/mcp/search.zig",
        "mcp-crypto/src/registro.zig",
        "mcp-runner/src/registro.zig",
        "mcp-time/src/registro.zig",
        "mcp-math/src/bigint/addsub.zig",
    };

    for (standalone_tests) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "proto", .module = proto_mod }},
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}

