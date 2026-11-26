const std = @import("std");
const constants = @import("../constants.zig");
const field = @import("../field/root.zig");
const scalar = @import("../scalar/root.zig");
const point = @import("../point/root.zig");
const generator = @import("../generator/root.zig");
const glv = @import("../glv/root.zig");
const sha256 = @import("../hash/sha256.zig");

/// ═══════════════════════════════════════════════════════════════════════════
///  secp256k1-fast/schnorr/schnorr.zig — Firma Schnorr BIP-340 (x-only)
/// ═══════════════════════════════════════════════════════════════════════════
///  Implementación directa de BIP-340 (sin MuSig, sin agregación de claves).
///  Diseñada para velocidad, no para resistencia a ataques de canal lateral:
///  no hay bloques constant-time ni enmascaramiento de nonce más allá del
///  `aux_rand` estándar del BIP.
///
///  Primitivas:
///    • taggedHash(tag, partes) → SHA256(SHA256(tag) ‖ SHA256(tag) ‖ partes…)
///    • liftX(x)                → P con Y par (x-only) o error si no está en curva
///    • publicKey(sk)           → 32 B x-only de sk·G
///    • sign(msg, sk, aux)      → 64 B (r ‖ s)
///    • verify(msg, pub, sig)   → bool
/// ═══════════════════════════════════════════════════════════════════════════
const BigInt256 = field.BigInt256;
const Scalar256 = scalar.Scalar256;
const Point = point.Point;

pub const Error = error{
    /// La clave secreta es 0 o ≥ N.
    InvalidSecretKey,
    /// El nonce derivado k′ resultó 0 (probabilidad ~2^-256).
    NonceZero,
};

/// Tag BIP-340 para el hash de la aleatoriedad auxiliar.
pub const TAG_AUX = "BIP0340/aux";
/// Tag BIP-340 para el hash del nonce.
pub const TAG_NONCE = "BIP0340/nonce";
/// Tag BIP-340 para el hash del desafío.
pub const TAG_CHALLENGE = "BIP0340/challenge";

/// Firma Schnorr BIP-340: r (32 B BE) ‖ s (32 B BE).
pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,

    /// Serializa la firma a 64 bytes (r ‖ s).
    pub fn toBytes(self: Signature) [64]u8 {
        var out: [64]u8 = undefined;
        @memcpy(out[0..32], &self.r);
        @memcpy(out[32..64], &self.s);
        return out;
    }

    /// Construye una firma desde 64 bytes (r ‖ s). No valida rangos.
    pub fn fromBytes(bytes: *const [64]u8) Signature {
        var sig: Signature = undefined;
        @memcpy(&sig.r, bytes[0..32]);
        @memcpy(&sig.s, bytes[32..64]);
        return sig;
    }
};

/// Par de claves ajustado a BIP-340 (paridad par).
pub const KeyPair = struct {
    /// Escalar secreto ajustado: d si d·G tiene Y par, si no N−d.
    secret: Scalar256,
    /// Clave pública x-only (32 B BE) = X(d·G).
    pubkey: [32]u8,
    /// Punto público P = secret·G (Y par).
    pubkey_point: Point,
};

/// Hash etiquetado BIP-340: SHA256(SHA256(tag) ‖ SHA256(tag) ‖ partes…).
/// Escribe el digest de 32 bytes en `out`.
pub fn taggedHash(tag: []const u8, parts: []const []const u8, out: *[32]u8) void {
    var tag_hash: [32]u8 = undefined;
    sha256.hash(tag, &tag_hash);

    var ctx = sha256.Sha256Context.init(.{});
    ctx.update(&tag_hash);
    ctx.update(&tag_hash);
    for (parts) |part| ctx.update(part);
    ctx.final(out);
}

/// Reduce un valor de 32 bytes BE módulo N (una sola resta condicional:
/// todo valor de 32 B es < 2·N).
pub fn modN(bytes: *const [32]u8) Scalar256 {
    const v = Scalar256.fromBytes(bytes);
    if (v.isGreaterOrEqual(Scalar256.N)) return v.sub(Scalar256.N);
    return v;
}

/// liftX(pubkey) → punto con Y par, o null si la clave no está en la curva.
/// Acepta x < P y raíz cuadrada existente.
pub fn liftX(pubkey: *const [32]u8) ?Point {
    const x = BigInt256.fromBytes(pubkey);
    if (x.isGreaterOrEqual(BigInt256.P)) return null;

    const y_root = x.liftX() catch return null;
    const y = if (y_root.isOdd()) BigInt256.P.sub(y_root).result else y_root;
    return Point{ .x = x, .y = y, .z = BigInt256.one };
}

/// Deriva el par BIP-340 de una clave secreta de 32 B BE.
/// Falla si sk = 0 o sk ≥ N.
pub fn keyPair(secret: *const [32]u8) Error!KeyPair {
    const d0 = Scalar256.fromBytes(secret);
    if (d0.isZero() or d0.isGreaterOrEqual(Scalar256.N)) return error.InvalidSecretKey;

    const p0 = generator.mulG(d0);
    if (p0.isInfinity()) return error.InvalidSecretKey;

    const aff = p0.toAffine();
    var pubkey: [32]u8 = undefined;
    aff.x.toBytes(&pubkey);

    const d = if (aff.y.isOdd()) Scalar256.zero.sub(d0) else d0;
    const p = if (aff.y.isOdd()) p0.negate() else p0;

    return .{ .secret = d, .pubkey = pubkey, .pubkey_point = p };
}

/// Clave pública x-only (32 B BE) de una clave secreta de 32 B BE.
pub fn publicKey(secret: *const [32]u8) Error![32]u8 {
    return (try keyPair(secret)).pubkey;
}

/// Firma BIP-340 de `msg` (longitud arbitraria) con `secret` y `aux` (32 B).
/// `aux` debe ser aleatorio; ceros produce firmas deterministas (vectores de
/// prueba BIP-340).
pub fn sign(msg: []const u8, secret: *const [32]u8, aux: *const [32]u8) Error!Signature {
    const kp = try keyPair(secret);

    var d_bytes: [32]u8 = undefined;
    kp.secret.toBytes(&d_bytes);

    // t = bytes(d) ⊕ SHA256("BIP0340/aux" ‖ SHA256("BIP0340/aux") ‖ aux)
    var aux_hash: [32]u8 = undefined;
    taggedHash(TAG_AUX, &.{aux}, &aux_hash);
    var t: [32]u8 = undefined;
    for (0..32) |i| t[i] = d_bytes[i] ^ aux_hash[i];

    // k′ = int(SHA256_nonce(t ‖ px ‖ msg)) mod N
    var rand: [32]u8 = undefined;
    taggedHash(TAG_NONCE, &.{ &t, &kp.pubkey, msg }, &rand);
    const k0 = modN(&rand);
    if (k0.isZero()) return error.NonceZero;

    // R = k′·G ; k = k′ si Y(R) es par, si no N−k′
    const r0 = generator.mulG(k0);
    if (r0.isInfinity()) return error.NonceZero;
    const r_aff = r0.toAffine();
    var rx: [32]u8 = undefined;
    r_aff.x.toBytes(&rx);
    const k = if (r_aff.y.isOdd()) Scalar256.zero.sub(k0) else k0;

    // e = int(SHA256_challenge(rx ‖ px ‖ msg)) mod N
    var e_hash: [32]u8 = undefined;
    taggedHash(TAG_CHALLENGE, &.{ &rx, &kp.pubkey, msg }, &e_hash);
    const e = modN(&e_hash);

    // s = (k + e·d) mod N
    const s = k.add(e.mul(kp.secret));
    var s_bytes: [32]u8 = undefined;
    s.toBytes(&s_bytes);

    return .{ .r = rx, .s = s_bytes };
}

/// Verificación BIP-340. Devuelve true si la firma es válida.
/// Rechaza: r ≥ P, s ≥ N, pubkey ≥ P o fuera de curva, R en el infinito o
/// con Y impar, y X(R) ≠ r.
pub fn verify(msg: []const u8, pubkey: *const [32]u8, sig: Signature) bool {
    // r debe ser un elemento de campo válido (< P)
    const r_field = BigInt256.fromBytes(&sig.r);
    if (r_field.isGreaterOrEqual(BigInt256.P)) return false;

    // s debe ser un escalar válido (< N)
    const s = Scalar256.fromBytes(&sig.s);
    if (s.isGreaterOrEqual(Scalar256.N)) return false;

    // P = lift_x(pubkey), con Y par
    const p = liftX(pubkey) orelse return false;

    // e = int(SHA256_challenge(r ‖ pubkey ‖ msg)) mod N
    var e_hash: [32]u8 = undefined;
    taggedHash(TAG_CHALLENGE, &.{ &sig.r, pubkey, msg }, &e_hash);
    const e = modN(&e_hash);

    // R = s·G − e·P
    const sg = generator.mulG(s);
    const ep = glv.mulGLV(p, e).negate();
    const r_point = sg.add(ep);
    if (r_point.isInfinity()) return false;

    const r_aff = r_point.toAffine();
    if (r_aff.y.isOdd()) return false;

    var rx: [32]u8 = undefined;
    r_aff.x.toBytes(&rx);
    return std.mem.eql(u8, &rx, &sig.r);
}
