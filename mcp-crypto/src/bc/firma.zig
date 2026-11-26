// Firma y verificación Schnorr BIP-340 (x-only). Puro: sin IO.
//
// Nota de diseño: este servidor prioriza VELOCIDAD, no resistencia a ataques
// de canal lateral (el entorno de ejecución se asume seguro). La `aux_rand`
// es el estándar BIP-340 para enmascarar el nonce.

const std = @import("std");
const secp = @import("secp");
const hex = @import("hex.zig");

pub const ESQUEMA = "bip340-schnorr";

/// Tamaño máximo del mensaje a firmar (bytes).
pub const MAX_MENSAJE = 1024;

pub const Resultado = struct {
    /// Clave pública x-only derivada (32 B).
    pubkey_xonly: [32]u8,
    /// Firma BIP-340 (64 B: r ‖ s).
    firma: [64]u8,
};

/// Firma `msg` con `secret` y `aux` (ambos de 32 B). Deriva además la pubkey
/// x-only. Errores de la librería: `InvalidSecretKey`, `NonceZero`.
pub fn firmar(msg: []const u8, secret: *const [32]u8, aux: *const [32]u8) !Resultado {
    const kp = try secp.schnorr.keyPair(secret);
    const sig = try secp.schnorr.sign(msg, secret, aux);
    return .{ .pubkey_xonly = kp.pubkey, .firma = sig.toBytes() };
}

/// Verifica una firma BIP-340. Devuelve false si la firma/clave/mensaje no
/// forman una firma válida (incluye pubkey fuera de curva).
pub fn verificar(msg: []const u8, pubkey: *const [32]u8, firma: *const [64]u8) bool {
    return secp.schnorr.verify(msg, pubkey, secp.schnorr.Signature.fromBytes(firma));
}

/// Hex exacto de `n` bytes (2n dígitos, opcional prefijo 0x).
pub fn parseHexExact(comptime n: usize, s: []const u8) ![n]u8 {
    const t = hex.trim0x(std.mem.trim(u8, s, " \t\r\n"));
    if (t.len != n * 2) return error.LongitudInvalida;
    var out: [n]u8 = undefined;
    for (0..n) |i| {
        const hi = hex.hexVal(t[2 * i]) orelse return error.HexInvalido;
        const lo = hex.hexVal(t[2 * i + 1]) orelse return error.HexInvalido;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

/// Clave pública x-only: acepta 64 hex (x-only) o 66 hex (02/03 + x).
pub fn parseXOnly(s: []const u8) ![32]u8 {
    const t = hex.trim0x(std.mem.trim(u8, s, " \t\r\n"));
    if (t.len == 64) return parseHexExact(32, t);
    if (t.len == 66) {
        if (t[0] != '0' or (t[1] != '2' and t[1] != '3')) return error.PubkeyInvalida;
        return parseHexExact(32, t[2..]);
    }
    return error.LongitudInvalida;
}

/// Resuelve el mensaje a firmar/verificar a bytes crudos en `buf`.
/// Prioriza `mensaje_hex`; si no, usa `mensaje` (texto UTF-8).
pub fn mensajeBytes(texto: ?[]const u8, mensaje_hex: ?[]const u8, buf: []u8) ![]const u8 {
    if (mensaje_hex) |hs| {
        const t = hex.trim0x(std.mem.trim(u8, hs, " \t\r\n"));
        if (t.len % 2 != 0) return error.HexInvalido;
        const n = t.len / 2;
        if (n > buf.len) return error.MensajeInvalido;
        for (0..n) |i| {
            const hi = hex.hexVal(t[2 * i]) orelse return error.HexInvalido;
            const lo = hex.hexVal(t[2 * i + 1]) orelse return error.HexInvalido;
            buf[i] = (hi << 4) | lo;
        }
        return buf[0..n];
    }
    if (texto) |tx| {
        if (tx.len > buf.len) return error.MensajeInvalido;
        @memcpy(buf[0..tx.len], tx);
        return buf[0..tx.len];
    }
    return error.MensajeInvalido;
}

// ---------- tests ----------

const testing = std.testing;

test "firma: vector oficial BIP-340 #0" {
    const secret = try parseHexExact(32, "0000000000000000000000000000000000000000000000000000000000000003");
    const aux: [32]u8 = @splat(0);
    const msg: [32]u8 = @splat(0);

    const r = try firmar(&msg, &secret, &aux);
    try testing.expectEqualSlices(
        u8,
        &(try parseHexExact(32, "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9")),
        &r.pubkey_xonly,
    );
    try testing.expectEqualSlices(
        u8,
        &(try parseHexExact(64, "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0")),
        &r.firma,
    );
    try testing.expect(verificar(&msg, &r.pubkey_xonly, &r.firma));
}

test "firma: verificar detecta manipulacion" {
    const secret = try parseHexExact(32, "0000000000000000000000000000000000000000000000000000000000000001");
    const aux: [32]u8 = @splat(7);
    const msg = "mensaje de prueba";
    const r = try firmar(msg, &secret, &aux);

    try testing.expect(verificar(msg, &r.pubkey_xonly, &r.firma));

    var firma_mala = r.firma;
    firma_mala[63] ^= 1;
    try testing.expect(!verificar(msg, &r.pubkey_xonly, &firma_mala));
    try testing.expect(!verificar("otro mensaje", &r.pubkey_xonly, &r.firma));
}

test "firma: parseXOnly acepta x-only y comprimida" {
    const xonly = "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117";
    const a = try parseXOnly(xonly);
    const b = try parseXOnly("02778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117");
    try testing.expectEqualSlices(u8, &a, &b);
    try testing.expectError(error.PubkeyInvalida, parseXOnly("04" ++ xonly));
    try testing.expectError(error.LongitudInvalida, parseXOnly("abcd"));
}

test "firma: mensajeBytes hex y texto" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualSlices(u8, &[_]u8{ 0xAB, 0xCD }, try mensajeBytes(null, "abcd", &buf));
    try testing.expectEqualSlices(u8, "hola", try mensajeBytes("hola", null, &buf));
    try testing.expectError(error.HexInvalido, mensajeBytes(null, "abc", &buf));
    try testing.expectError(error.MensajeInvalido, mensajeBytes(null, null, &buf));
}

test "firma: mensaje vacío es válido (vector #15)" {
    const secret = try parseHexExact(32, "0340034003400340034003400340034003400340034003400340034003400340");
    const aux: [32]u8 = @splat(0);
    const r = try firmar("", &secret, &aux);
    try testing.expect(verificar("", &r.pubkey_xonly, &r.firma));
}
