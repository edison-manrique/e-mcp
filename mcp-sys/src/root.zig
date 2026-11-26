// Puerta reutilizable del paquete: re-exporta los modulos y
// registra sus tests para que `zig build test` los corra.

pub const proto = @import("core/proto.zig");
pub const registro = @import("registro.zig");
pub const ayuda = @import("ayuda.zig");
pub const fstool = @import("fs/fstool.zig");
pub const fssearch = @import("fs/fssearch.zig");
pub const fsdir = @import("fs/fsdir.zig");
pub const fsedit = @import("fs/fsedit.zig");
pub const fspath = @import("fs/fspath.zig");
pub const fsio = @import("fs/fsio.zig");
pub const fsraw = @import("fs/fsraw.zig");
pub const exectool = @import("exec/exectool.zig");
pub const systool = @import("core/systool.zig");
pub const job = @import("exec/job.zig");
pub const proc = @import("exec/proc.zig");
pub const regex = @import("regex/regex.zig");

test {
    _ = @import("core/proto.zig");
    _ = @import("registro.zig");
    _ = @import("ayuda.zig");
    _ = @import("fs/fstool.zig");
    _ = @import("fs/fssearch.zig");
    _ = @import("fs/fsdir.zig");
    _ = @import("fs/fsedit.zig");
    _ = @import("fs/fspath.zig");
    _ = @import("fs/fsio.zig");
    _ = @import("fs/fsraw.zig");
    _ = @import("exec/exectool.zig");
    _ = @import("core/systool.zig");
    _ = @import("exec/job.zig");
    _ = @import("exec/proc.zig");
    _ = @import("regex/regex.zig");
    _ = @import("regex/tests.zig");
}
