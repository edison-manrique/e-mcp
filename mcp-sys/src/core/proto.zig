//! Re-exporta el transporte JSON-RPC compartido (`shared/proto.zig`).
const shared = @import("proto");

pub const Ctx = shared.Ctx;
pub const bracesBalanced = shared.bracesBalanced;
pub const parsesAsObject = shared.parsesAsObject;
pub const has = shared.has;
pub const argStr = shared.argStr;
pub const argStrOpt = shared.argStrOpt;
pub const argBool = shared.argBool;
pub const argInt = shared.argInt;
pub const argDigits = shared.argDigits;
pub const argArray = shared.argArray;
pub const writeId = shared.writeId;
pub const sendResult = shared.sendResult;
pub const sendJsonError = shared.sendJsonError;
pub const sendToolText = shared.sendToolText;
pub const sendToolError = shared.sendToolError;
