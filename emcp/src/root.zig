// Puerta reutilizable del paquete: re-exporta los modulos y registra sus
// tests para que `zig build test` los corra.

pub const proto = @import("core/proto.zig");
pub const jsonw = @import("core/jsonw.zig");
pub const version = @import("core/version.zig");
pub const args = @import("core/args.zig");
pub const firma = @import("core/firma.zig");
pub const run = @import("core/run.zig");
pub const proc = @import("core/proc.zig");
// Identidad de ESTE servidor (version/desc/meta-tools).
pub const registro = @import("registro.zig");
pub const ayuda = @import("ayuda.zig");
// Parser del `registro.json` de terceros (formato firmado).
pub const manifiesto = @import("core/registro.zig");
pub const mcp_client = @import("core/mcp_client.zig");
pub const pool = @import("core/pool.zig");
pub const tools = @import("mcp/tools.zig");
pub const registry = @import("mcp/registry.zig");
pub const meta = @import("mcp/meta.zig");

test {
    _ = @import("registro.zig");
    _ = @import("ayuda.zig");
    _ = @import("core/proto.zig");
    _ = @import("core/jsonw.zig");
    _ = @import("core/args.zig");
    _ = @import("core/firma.zig");
    _ = @import("core/run.zig");
    _ = @import("core/proc.zig");
    _ = @import("core/registro.zig");
    _ = @import("core/mcp_client.zig");
    _ = @import("core/pool.zig");
    _ = @import("mcp/tools.zig");
    _ = @import("mcp/registry.zig");
    _ = @import("mcp/meta.zig");
}
