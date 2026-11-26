// Derivación de claves y direcciones (BTC/ETH) + WIF. Puro: sin IO.
// Reutiliza la librería `secp` (secp256k1-fast).

const std = @import("std");
const secp = @import("secp");
const hexu = @import("hex.zig");

const BigInt256 = secp.BigInt256;
const Scalar256 = secp.Scalar256;
const generator = secp.generator;
const btc = secp.address.btc;
const eth = secp.address.eth;
const base58 = secp.address.base58;

pub const Tipo = secp.vanity.AddressType;
pub const Modo = secp.vanity.MatchMode;

pub const MAX_DIR = 128;

pub const Direcciones = struct {
    p2pkh: [48]u8 = undefined,
    p2pkh_len: usize = 0,
    p2sh: [48]u8 = undefined,
    p2sh_len: usize = 0,
    p2wpkh: [66]u8 = undefined,
    p2wpkh_len: usize = 0,
    p2tr: [66]u8 = undefined,
    p2tr_len: usize = 0,
    eth: [42]u8 = undefined,
    eth_len: usize = 0,
};

/// Todo lo derivable de una clave privada (tamaño acotado, sin heap).
pub const Clave = struct {
    priv: [32]u8,
    pub_comprimida: [33]u8,
    pub_sin_comprimir: [65]u8,
    wif_comp: [54]u8,
    wif_comp_len: usize,
    wif_uncomp: [54]u8,
    wif_uncomp_len: usize,
    dir: Direcciones,
};

pub fn tipoNombre(t: Tipo) []const u8 {
    return switch (t) {
        .btc_p2pkh => "p2pkh",
        .btc_p2sh_p2wpkh => "p2sh",
        .btc_p2wpkh => "p2wpkh",
        .btc_p2tr => "p2tr",
        .eth => "eth",
    };
}

/// Comparación de nombres de tipo/modo sin distinguir mayúsculas.
fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Tipos canónicos + alias (btc-p2pkh, segwit, taproot, ethereum, ...).
pub fn parseTipo(s: []const u8) ?Tipo {
    if (eqi(s, "p2pkh") or eqi(s, "btc-p2pkh") or eqi(s, "btc") or eqi(s, "legacy") or eqi(s, "btc-legacy"))
        return .btc_p2pkh;
    if (eqi(s, "p2sh") or eqi(s, "btc-p2sh") or eqi(s, "p2sh-p2wpkh") or eqi(s, "btc-p2sh-p2wpkh") or eqi(s, "segwit-compat"))
        return .btc_p2sh_p2wpkh;
    if (eqi(s, "p2wpkh") or eqi(s, "btc-p2wpkh") or eqi(s, "segwit") or eqi(s, "btc-segwit") or eqi(s, "bech32") or eqi(s, "native-segwit"))
        return .btc_p2wpkh;
    if (eqi(s, "p2tr") or eqi(s, "btc-p2tr") or eqi(s, "taproot") or eqi(s, "btc-taproot"))
        return .btc_p2tr;
    if (eqi(s, "eth") or eqi(s, "ethereum") or eqi(s, "eip55") or eqi(s, "erc20"))
        return .eth;
    return null;
}

/// Modos canónicos + alias (empieza/termina/contiene, prefix/suffix, ...).
pub fn parseModo(s: []const u8) ?Modo {
    if (eqi(s, "prefijo") or eqi(s, "prefix") or eqi(s, "starts_with") or eqi(s, "empieza") or eqi(s, "comienza") or eqi(s, "inicio"))
        return .starts_with;
    if (eqi(s, "sufijo") or eqi(s, "suffix") or eqi(s, "ends_with") or eqi(s, "termina") or eqi(s, "acaba") or eqi(s, "fin"))
        return .ends_with;
    if (eqi(s, "contiene") or eqi(s, "contains") or eqi(s, "incluye") or eqi(s, "interior"))
        return .contains;
    return null;
}

/// Alfabeto permitido por tipo (para mensajes de error útiles).
pub fn alfabetoTipo(t: Tipo) []const u8 {
    return switch (t) {
        .btc_p2pkh, .btc_p2sh_p2wpkh => "Base58: 1-9 A-Z a-z (sin 0 O I l)",
        .btc_p2wpkh, .btc_p2tr => "Bech32: qpzry9x8gf2tvdw0s3jn54khce6mua7l (a-z y 0-9, sin 1 b i o)",
        .eth => "hex: 0-9 a-f (sin el prefijo 0x)",
    };
}

/// 1 ≤ priv < N.
pub fn valida(priv: *const [32]u8) bool {
    const s = Scalar256.fromBytes(priv);
    return !s.isZero() and s.isLessThan(Scalar256.N);
}

/// Clave pública comprimida (33) y sin comprimir (65) desde la privada.
pub fn pubkeyDe(priv: *const [32]u8) struct { comp: [33]u8, uncomp: [65]u8 } {
    const s = Scalar256.fromBytes(priv);
    const aff = generator.mulG(s).toAffine();
    var comp: [33]u8 = undefined;
    var uncomp: [65]u8 = undefined;
    comp[0] = if (aff.y.isOdd()) 0x03 else 0x02;
    aff.x.toBytes(comp[1..33]);
    uncomp[0] = 0x04;
    aff.x.toBytes(uncomp[1..33]);
    aff.y.toBytes(uncomp[33..65]);
    return .{ .comp = comp, .uncomp = uncomp };
}

/// WIF (Base58Check): 0x80 || priv [|| 0x01].
pub fn wifDe(priv: *const [32]u8, comprimida: bool, out: *[54]u8) ![]u8 {
    var payload: [34]u8 = undefined;
    payload[0] = 0x80;
    @memcpy(payload[1..33], priv);
    var plen: usize = 33;
    if (comprimida) {
        payload[33] = 0x01;
        plen = 34;
    }
    return base58.checkEncode(payload[0..plen], out);
}

/// Dirección del tipo pedido. `out` debe medir >= 66.
pub fn derivarTipo(priv: *const [32]u8, tipo: Tipo, out: []u8) ![]u8 {
    const pk = pubkeyDe(priv);
    return switch (tipo) {
        .btc_p2pkh => btc.p2pkh(&pk.comp, out),
        .btc_p2sh_p2wpkh => btc.p2sh_p2wpkh(&pk.comp, out),
        .btc_p2wpkh => btc.p2wpkh(&pk.comp, out),
        .btc_p2tr => btc.p2tr(&pk.comp, out),
        .eth => eth.ethAddress(&pk.uncomp, out),
    };
}

/// Todo (2 pubkeys, 2 WIF, 5 direcciones).
pub fn derivarTodo(priv: *const [32]u8) !Clave {
    var c: Clave = undefined;
    c.priv = priv.*;
    const pk = pubkeyDe(priv);
    c.pub_comprimida = pk.comp;
    c.pub_sin_comprimir = pk.uncomp;
    c.wif_comp_len = (try wifDe(priv, true, &c.wif_comp)).len;
    c.wif_uncomp_len = (try wifDe(priv, false, &c.wif_uncomp)).len;
    c.dir.p2pkh_len = (try btc.p2pkh(&pk.comp, &c.dir.p2pkh)).len;
    c.dir.p2sh_len = (try btc.p2sh_p2wpkh(&pk.comp, &c.dir.p2sh)).len;
    c.dir.p2wpkh_len = (try btc.p2wpkh(&pk.comp, &c.dir.p2wpkh)).len;
    c.dir.p2tr_len = (try btc.p2tr(&pk.comp, &c.dir.p2tr)).len;
    c.dir.eth_len = (try eth.ethAddress(&pk.uncomp, &c.dir.eth)).len;
    return c;
}

/// Versión ligera: una sola dirección + una pubkey + un WIF (para lotes).
pub const Ligera = struct {
    priv: [32]u8,
    pubkey: [65]u8 = undefined,
    pub_len: usize = 0,
    wif: [54]u8 = undefined,
    wif_len: usize = 0,
    dir: [MAX_DIR]u8 = undefined,
    dir_len: usize = 0,
};

pub fn derivarLigera(priv: *const [32]u8, tipo: Tipo, comprimida: bool, out: *Ligera) !void {
    out.priv = priv.*;
    const pk = pubkeyDe(priv);
    if (comprimida) {
        @memcpy(out.pubkey[0..33], &pk.comp);
        out.pub_len = 33;
    } else {
        @memcpy(out.pubkey[0..65], &pk.uncomp);
        out.pub_len = 65;
    }
    out.wif_len = (try wifDe(priv, comprimida, &out.wif)).len;
    const d = try derivarTipo(priv, tipo, out.dir[0..]);
    out.dir_len = d.len;
}

/// Acepta hex (64 o flexible), decimal o WIF.
pub fn parseClave(s: []const u8) ![32]u8 {
    const t = std.mem.trim(u8, s, " \t\r\n");
    if (t.len == 0) return error.ClaveInvalida;

    // WIF: '5' (sin comprimir) / 'K','L' (comprimido), 51-52 chars.
    if ((t[0] == '5' or t[0] == 'K' or t[0] == 'L') and (t.len == 51 or t.len == 52)) {
        return parseWif(t) catch return error.ClaveInvalida;
    }

    const u = hexu.trim0x(t);
    if (u.len == 64 and hexu.isAllHex(u)) {
        const k = try hexu.parse32(u);
        if (!valida(&k)) return error.ClaveInvalida;
        return k;
    }
    if (hexu.isAllDigit(t)) {
        var b: [32]u8 = undefined;
        try hexu.decToBytes(t, &b);
        if (!valida(&b)) return error.ClaveInvalida;
        return b;
    }
    if (hexu.isAllHex(u) and u.len <= 64) {
        const k = try hexu.parseBytes32Flex(u);
        if (!valida(&k)) return error.ClaveInvalida;
        return k;
    }
    return error.ClaveInvalida;
}

fn parseWif(t: []const u8) ![32]u8 {
    var buf: [64]u8 = undefined;
    const payload = base58.checkDecode(t, &buf) catch return error.WifInvalido;
    if (payload.len != 33 and payload.len != 34) return error.WifInvalido;
    if (payload[0] != 0x80) return error.WifInvalido;
    if (payload.len == 34 and payload[33] != 0x01) return error.WifInvalido;
    var out: [32]u8 = undefined;
    @memcpy(&out, payload[1..33]);
    if (!valida(&out)) return error.ClaveInvalida;
    return out;
}

/// Punto (Jacobiano) desde pubkey hex: 33 comprimida, 65 (04..) o 64 cruda.
pub fn parsePubkey(s: []const u8) !secp.Point {
    const t = hexu.trim0x(std.mem.trim(u8, s, " \t\r\n"));
    if (!hexu.isAllHex(t)) return error.PubkeyInvalida;

    if (t.len == 66) {
        const b = try hexu.parse32(t[2..66]);
        const prefix = hexu.hexVal(t[0]).? << 4 | hexu.hexVal(t[1]).?;
        if (prefix != 0x02 and prefix != 0x03) return error.PubkeyInvalida;
        const x = BigInt256.fromBytes(&b);
        var y = x.liftX() catch return error.PuntoInvalido;
        if ((y.isOdd() and prefix == 0x02) or (!y.isOdd() and prefix == 0x03)) {
            y = BigInt256.P.sub(y).result;
        }
        return secp.Point{ .x = x, .y = y, .z = BigInt256.one };
    }

    if (t.len == 130) {
        if (t[0] != '0' or t[1] != '4') return error.PubkeyInvalida;
        const bx = try hexu.parse32(t[2..66]);
        const by = try hexu.parse32(t[66..130]);
        return secp.Point{ .x = BigInt256.fromBytes(&bx), .y = BigInt256.fromBytes(&by), .z = BigInt256.one };
    }

    if (t.len == 128) {
        const bx = try hexu.parse32(t[0..64]);
        const by = try hexu.parse32(t[64..128]);
        return secp.Point{ .x = BigInt256.fromBytes(&bx), .y = BigInt256.fromBytes(&by), .z = BigInt256.one };
    }

    return error.PubkeyInvalida;
}

/// Rango [2^(bits-1), 2^bits - 1] (convención de los puzzles de Bitcoin).
pub fn rangoDeBits(bits: u32) !struct { min: BigInt256, max: BigInt256 } {
    if (bits < 2 or bits > 256) return error.RangoInvalido;
    if (bits == 256) {
        return .{
            .min = BigInt256.one.shiftLeft(255),
            .max = BigInt256{ .limbs = .{ 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF } },
        };
    }
    const min = BigInt256.one.shiftLeft(@intCast(bits - 1));
    const max = BigInt256.one.shiftLeft(@intCast(bits)).sub(BigInt256.one).result;
    return .{ .min = min, .max = max };
}

// ---------- tests (vectores conocidos) ----------

fn hexDe(b: []const u8, out: []u8) []const u8 {
    return hexu.bytesToHexInto(b, out);
}

test "derivar clave=1: pubkeys, WIF y direcciones conocidas" {
    const priv = try parseClave("0000000000000000000000000000000000000000000000000000000000000001");
    const c = try derivarTodo(&priv);

    var hb: [140]u8 = undefined;
    try std.testing.expectEqualStrings(
        "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
        hexDe(&c.pub_comprimida, &hb),
    );
    try std.testing.expectEqualStrings(
        "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8",
        hexDe(&c.pub_sin_comprimir, &hb),
    );
    try std.testing.expectEqualStrings("KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn", c.wif_comp[0..c.wif_comp_len]);
    try std.testing.expectEqualStrings("5HpHagT65TZzG1PH3CSu63k8DbpvD8s5ip4nEB3kEsreAnchuDf", c.wif_uncomp[0..c.wif_uncomp_len]);
    try std.testing.expectEqualStrings("1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", c.dir.p2pkh[0..c.dir.p2pkh_len]);
    try std.testing.expectEqualStrings("3JvL6Ymt8MVWiCNHC7oWU6nLeHNJKLZGLN", c.dir.p2sh[0..c.dir.p2sh_len]);
    try std.testing.expectEqualStrings("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", c.dir.p2wpkh[0..c.dir.p2wpkh_len]);
    try std.testing.expectEqualStrings("bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5pmedqhyptwy6lm87hf5sspknck9", c.dir.p2tr[0..c.dir.p2tr_len]);
    try std.testing.expectEqualStrings("0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf", c.dir.eth[0..c.dir.eth_len]);
}

test "parseClave acepta hex, 0x, decimal y WIF (ida y vuelta)" {
    const canon = "0000000000000000000000000000000000000000000000000000000000000001";
    const variantes = [_][]const u8{
        canon,
        "0x0000000000000000000000000000000000000000000000000000000000000001",
        "1",
        "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn",
        "5HpHagT65TZzG1PH3CSu63k8DbpvD8s5ip4nEB3kEsreAnchuDf",
    };
    for (variantes) |v| {
        const p = try parseClave(v);
        var hb: [64]u8 = undefined;
        try std.testing.expectEqualStrings(canon, hexDe(&p, &hb));
    }
}

test "parseClave rechaza cero, N y basura" {
    try std.testing.expectError(error.ClaveInvalida, parseClave("0"));
    try std.testing.expectError(error.ClaveInvalida, parseClave("zzz"));
    // N (orden de la curva) no es una clave valida.
    try std.testing.expectError(error.ClaveInvalida, parseClave("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"));
}

test "rangoDeBits(20) = [2^19, 2^20-1]" {
    const r = try rangoDeBits(20);
    var hb: [64]u8 = undefined;
    try std.testing.expectEqualStrings("80000", hexu.bigToHexTrim(r.min, &hb));
    try std.testing.expectEqualStrings("fffff", hexu.bigToHexTrim(r.max, &hb));
    try std.testing.expectError(error.RangoInvalido, rangoDeBits(1));
    try std.testing.expectError(error.RangoInvalido, rangoDeBits(257));
}

test "parsePubkey comprimida y sin comprimir dan el mismo punto" {
    const priv = try parseClave("f4240");
    const pk = pubkeyDe(&priv);
    var hc: [140]u8 = undefined;
    var hu: [140]u8 = undefined;
    const c_hex = hexu.bytesToHexInto(&pk.comp, &hc);
    const u_hex = hexu.bytesToHexInto(&pk.uncomp, &hu);
    const a = try parsePubkey(c_hex);
    const b = try parsePubkey(u_hex);
    try std.testing.expectEqualSlices(u64, &a.x.limbs, &b.x.limbs);
    try std.testing.expectEqualSlices(u64, &a.y.limbs, &b.y.limbs);
}

test "derivarLigera coincide con derivarTodo" {
    const priv = try parseClave("f4240");
    var l: Ligera = undefined;
    try derivarLigera(&priv, .btc_p2pkh, true, &l);
    const c = try derivarTodo(&priv);
    try std.testing.expectEqualStrings(c.dir.p2pkh[0..c.dir.p2pkh_len], l.dir[0..l.dir_len]);
    try std.testing.expectEqualStrings(c.wif_comp[0..c.wif_comp_len], l.wif[0..l.wif_len]);
    try std.testing.expectEqualSlices(u8, &c.pub_comprimida, l.pubkey[0..l.pub_len]);
}

test "parseTipo: alias btc-* y sin distinguir mayusculas" {
    try std.testing.expectEqual(Tipo.btc_p2pkh, parseTipo("p2pkh").?);
    try std.testing.expectEqual(Tipo.btc_p2pkh, parseTipo("btc-p2pkh").?);
    try std.testing.expectEqual(Tipo.btc_p2pkh, parseTipo("BTC-P2PKH").?);
    try std.testing.expectEqual(Tipo.btc_p2pkh, parseTipo("legacy").?);
    try std.testing.expectEqual(Tipo.btc_p2sh_p2wpkh, parseTipo("btc-p2sh").?);
    try std.testing.expectEqual(Tipo.btc_p2wpkh, parseTipo("btc-segwit").?);
    try std.testing.expectEqual(Tipo.btc_p2wpkh, parseTipo("Bech32").?);
    try std.testing.expectEqual(Tipo.btc_p2tr, parseTipo("btc-taproot").?);
    try std.testing.expectEqual(Tipo.eth, parseTipo("ETH").?);
    try std.testing.expectEqual(Tipo.eth, parseTipo("ethereum").?);
    try std.testing.expect(parseTipo("btc-p2xxx") == null);
    try std.testing.expect(parseTipo("") == null);
}

test "parseModo: alias empieza/termina/contiene y mayusculas" {
    try std.testing.expectEqual(Modo.starts_with, parseModo("empieza").?);
    try std.testing.expectEqual(Modo.starts_with, parseModo("PREFIJO").?);
    try std.testing.expectEqual(Modo.ends_with, parseModo("termina").?);
    try std.testing.expectEqual(Modo.ends_with, parseModo("suffix").?);
    try std.testing.expectEqual(Modo.contains, parseModo("contiene").?);
    try std.testing.expectEqual(Modo.contains, parseModo("CONTAINS").?);
    try std.testing.expect(parseModo("en-medio") == null);
}

test "alfabetoTipo describe el alfabeto de cada tipo" {
    try std.testing.expect(std.mem.indexOf(u8, alfabetoTipo(.eth), "hex") != null);
    try std.testing.expect(std.mem.indexOf(u8, alfabetoTipo(.btc_p2pkh), "Base58") != null);
    try std.testing.expect(std.mem.indexOf(u8, alfabetoTipo(.btc_p2wpkh), "Bech32") != null);
}
