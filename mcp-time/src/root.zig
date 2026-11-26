// Puerta reutilizable del paquete: re-exporta los módulos y registra los tests
// de todos ellos para `zig build test` (main.zig no se importa aquí).

pub const tm = @import("time/tmtool.zig");
pub const civil = @import("time/civil.zig");
pub const zona = @import("time/zona.zig");
pub const dst = @import("time/dst.zig");
pub const fecha = @import("time/fecha.zig");
pub const dur = @import("time/dur.zig");
pub const feriados = @import("time/feriados.zig");
pub const laborable = @import("time/laborable.zig");
pub const strftime = @import("time/strftime.zig");
pub const epoca = @import("time/epoca.zig");

pub const proto = @import("core/proto.zig");
pub const jsonw = @import("core/jsonw.zig");

pub const registro = @import("registro.zig");
pub const tools = @import("mcp/tools.zig");
pub const handlers = @import("mcp/handlers.zig");

pub const ayuda = @import("ayuda.zig");
pub const cli = @import("cli/cli.zig");

test {
    _ = @import("registro.zig");
    _ = @import("time/civil.zig");
    _ = @import("time/dst.zig");
    _ = @import("time/zona.zig");
    _ = @import("time/dur.zig");
    _ = @import("time/fecha.zig");
    _ = @import("time/feriados.zig");
    _ = @import("time/laborable.zig");
    _ = @import("time/epoca.zig");
    _ = @import("time/strftime.zig");
    _ = @import("time/tmtool.zig");
}
