const std = @import("std");
pub const ecdsa_mod = @import("ecdsa.zig");

/// ═══════════════════════════════════════════════════════════════════════════
///  source/ecdsa/root.zig — ECDSA Module Public API
/// ═══════════════════════════════════════════════════════════════════════════
pub const Ecdsa = ecdsa_mod.Ecdsa;
pub const Signature = ecdsa_mod.Signature;
