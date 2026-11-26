// Mnemónicos BIP-39: generación aleatoria y derivación BIP-32/44 a direcciones.
//
// Reutiliza `secp.bip39` (entropía <-> frase y PBKDF2-HMAC-SHA512) y
// `secp.bip32` (CKD + parser de rutas). Aquí solo viven las reglas del MCP:
// cuántas palabras admite, qué ruta estándar corresponde a cada tipo y los
// topes de entrada. Sin IO propio: el RNG y la respuesta los pone el llamador.

const std = @import("std");
const secp = @import("secp");
const clave = @import("clave.zig");

const bip39 = secp.bip39;
const bip32 = secp.bip32;

pub const Tipo = clave.Tipo;

/// Orden estable de los tipos cuando se piden "todos".
pub const TODOS = [_]Tipo{ .btc_p2pkh, .btc_p2sh_p2wpkh, .btc_p2wpkh, .btc_p2tr, .eth };

pub const MAX_MNEMONICO: usize = 24 * 10 + 24; // 24 palabras (español NFKD <=10 B) + espacios + margen
pub const MAX_RUTA: usize = 64;
pub const MAX_PASSPHRASE: usize = 200;
pub const MAX_CANTIDAD: u32 = 20;
pub const MAX_INDICE: i64 = 0x7fffffff; // cota segura (evita overflow del bit endurecido)

/// Bytes de entropía para 12/15/18/21/24 palabras (BIP-39).
pub fn entropiaBytes(palabras: u32) ?usize {
    return switch (palabras) {
        12 => 16,
        15 => 20,
        18 => 24,
        21 => 28,
        24 => 32,
        else => null,
    };
}

/// Palabras BIP-39 según los bytes de entropía.
pub fn palabrasDeEntropia(ent: usize) ?u32 {
    return switch (ent) {
        16 => 12,
        20 => 15,
        24 => 18,
        28 => 21,
        32 => 24,
        else => null,
    };
}

/// BIP-44/49/84/86: propósito endurecido y coin type por tipo de dirección.
pub fn proposito(t: Tipo) struct { purpose: u32, coin: u32 } {
    // coin = 0 (BTC) para todo el árbol de Bitcoin; 60 (ETH) usa BIP-44.
    return switch (t) {
        .btc_p2pkh => .{ .purpose = 44, .coin = 0 },
        .btc_p2sh_p2wpkh => .{ .purpose = 49, .coin = 0 },
        .btc_p2wpkh => .{ .purpose = 84, .coin = 0 },
        .btc_p2tr => .{ .purpose = 86, .coin = 0 },
        .eth => .{ .purpose = 44, .coin = 60 },
    };
}

/// "todos" (los 5) o un tipo concreto (con alias).
pub const Seleccion = struct { todos: bool, uno: Tipo };

/// Idioma de la wordlist BIP-39 que expone el MCP.
pub const Idioma = enum { en, es };

/// "en"/"ingles"/"inglés" -> .en ; "es"/"espanol"/"español" -> .es.
pub fn parseIdioma(s: []const u8) ?Idioma {
    if (std.ascii.eqlIgnoreCase(s, "en") or
        std.ascii.eqlIgnoreCase(s, "ingles") or
        std.ascii.eqlIgnoreCase(s, "inglés")) return .en;
    if (std.ascii.eqlIgnoreCase(s, "es") or
        std.ascii.eqlIgnoreCase(s, "espanol") or
        std.ascii.eqlIgnoreCase(s, "español")) return .es;
    return null;
}

fn lang(i: Idioma) bip39.Lang {
    return switch (i) {
        .en => .en,
        .es => .es,
    };
}

pub fn seleccion(s: []const u8) ?Seleccion {
    if (std.ascii.eqlIgnoreCase(s, "todos") or std.ascii.eqlIgnoreCase(s, "all") or std.ascii.eqlIgnoreCase(s, "todas"))
        return .{ .todos = true, .uno = .btc_p2pkh };
    const t = clave.parseTipo(s) orelse return null;
    return .{ .todos = false, .uno = t };
}

/// Ruta estándar BIP-44 del tipo, escrita en `buf`.
pub fn rutaEstandar(t: Tipo, cuenta: u32, cambio: u32, indice: u32, buf: []u8) ?[]const u8 {
    const p = proposito(t);
    return std.fmt.bufPrint(buf, "m/{d}'/{d}'/{d}'/{d}/{d}", .{ p.purpose, p.coin, cuenta, cambio, indice }) catch null;
}

// ---------- BIP-39 (frase <-> entropía <-> seed) ----------

/// Frase BIP-39 desde entropía cruda (16/20/24/28/32 bytes). Inglés (compat).
pub fn fraseDeEntropia(entropia: []const u8, out: []u8) ![]u8 {
    return fraseDeEntropiaIdioma(.en, entropia, out);
}

/// Frase BIP-39 desde entropía cruda en el idioma dado.
pub fn fraseDeEntropiaIdioma(idioma: Idioma, entropia: []const u8, out: []u8) ![]u8 {
    return bip39.entropyToMnemonicLang(lang(idioma), entropia, out);
}

/// Entropía cruda desde la frase (valida palabras y checksum). Inglés (compat).
pub fn entropiaDeFrase(frase: []const u8, out: []u8) ![]u8 {
    return entropiaDeFraseIdioma(.en, frase, out);
}

/// Entropía cruda desde la frase en el idioma dado (valida palabras y checksum).
pub fn entropiaDeFraseIdioma(idioma: Idioma, frase: []const u8, out: []u8) ![]u8 {
    return bip39.mnemonicToEntropyLang(lang(idioma), frase, out);
}

pub fn validaFrase(frase: []const u8) bool {
    return validaFraseIdioma(.en, frase);
}

pub fn validaFraseIdioma(idioma: Idioma, frase: []const u8) bool {
    return bip39.validateMnemonicLang(lang(idioma), frase);
}

/// Frase ya decodificada: idioma (detectado) + su entropía cruda.
pub const FraseDecodificada = struct { idioma: Idioma, entropia: []u8 };

/// Decodifica la frase (valida palabras + checksum) y devuelve el idioma y la
/// entropía. Si `explicito` es null, AUTODETECTA probando `en` y luego `es`.
/// Si ambos fallan devuelve el error del inglés (checksum/palabra), que es el
/// mensaje más útil por ser el idioma por defecto.
pub fn decodificarFrase(frase: []const u8, explicito: ?Idioma, out: []u8) !FraseDecodificada {
    if (explicito) |i| {
        const ent = try entropiaDeFraseIdioma(i, frase, out);
        return .{ .idioma = i, .entropia = ent };
    }
    if (entropiaDeFraseIdioma(.en, frase, out)) |ent| {
        return .{ .idioma = .en, .entropia = ent };
    } else |err_en| {
        if (entropiaDeFraseIdioma(.es, frase, out)) |ent| {
            return .{ .idioma = .es, .entropia = ent };
        } else |_| return err_en;
    }
}

/// Seed BIP-39 de 64 bytes (PBKDF2-HMAC-SHA512, 2048 iteraciones).
pub fn seedDeFrase(frase: []const u8, passphrase: []const u8) [64]u8 {
    var s: [64]u8 = undefined;
    bip39.mnemonicToSeed(frase, passphrase, &s);
    return s;
}

// ---------- BIP-32/44 (seed -> dirección) ----------

/// Una dirección derivada: clave ligera (priv/pub/dir/wif) + su ruta.
pub const Derivada = struct {
    tipo: Tipo,
    ruta: [MAX_RUTA]u8 = undefined,
    ruta_len: usize = 0,
    l: clave.Ligera = undefined,
};

fn hoja(seed: []const u8, ruta: []const u8) !secp.ExtendedKey {
    const master = try bip32.fromSeed(seed);
    return bip32.derivePath(&master, ruta);
}

/// Clave privada (32 B) de la hoja `ruta`. Para `derivar` desde un mnemónico.
pub fn privadaDeRuta(seed: []const u8, ruta: []const u8, out: *[32]u8) !void {
    if (ruta.len == 0 or ruta.len > MAX_RUTA) return error.RutaInvalida;
    const leaf = try hoja(seed, ruta);
    const priv = leaf.getPrivateKey() orelse return error.ClaveInvalida;
    out.* = priv;
}

/// Deriva `ruta` (texto BIP-32, p. ej. "m/84'/0'/0'/0/0") y arma la dirección
/// del tipo `t` en `out`.
pub fn derivarRuta(seed: []const u8, ruta: []const u8, t: Tipo, out: *Derivada) !void {
    if (ruta.len == 0 or ruta.len > MAX_RUTA) return error.RutaInvalida;
    const leaf = try hoja(seed, ruta);
    const priv = leaf.getPrivateKey() orelse return error.ClaveInvalida;
    try clave.derivarLigera(&priv, t, true, &out.l);
    @memcpy(out.ruta[0..ruta.len], ruta);
    out.ruta_len = ruta.len;
    out.tipo = t;
}

/// Deriva el tipo `t` por su ruta estándar BIP-44/49/84/86.
pub fn derivarEstandar(seed: []const u8, t: Tipo, cuenta: u32, cambio: u32, indice: u32, out: *Derivada) !void {
    var rb: [MAX_RUTA]u8 = undefined;
    const ruta = rutaEstandar(t, cuenta, cambio, indice, &rb) orelse return error.RutaInvalida;
    return derivarRuta(seed, ruta, t, out);
}

// ---------- tests ----------

test "entropiaBytes <-> palabrasDeEntropia" {
    try std.testing.expectEqual(@as(?usize, 16), entropiaBytes(12));
    try std.testing.expectEqual(@as(?usize, 32), entropiaBytes(24));
    try std.testing.expectEqual(@as(?u32, 15), palabrasDeEntropia(20));
    try std.testing.expect(entropiaBytes(13) == null);
    try std.testing.expect(palabrasDeEntropia(17) == null);
}

test "BIP-39: vector oficial (entropia cero -> 'abandon ... about')" {
    const ent: [16]u8 = @splat(0);
    var mbuf: [MAX_MNEMONICO]u8 = undefined;
    const frase = try fraseDeEntropia(&ent, &mbuf);
    try std.testing.expectEqualStrings(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        frase,
    );

    // Ida y vuelta: la entropía decodificada coincide.
    var ebuf: [32]u8 = undefined;
    const back = try entropiaDeFrase(frase, &ebuf);
    try std.testing.expectEqualSlices(u8, &ent, back);
    try std.testing.expect(validaFrase(frase));

    // Vector oficial BIP-39 con frase de paso "TREZOR".
    const seed = seedDeFrase(frase, "TREZOR");
    var hex: [128]u8 = undefined;
    const HEX = "0123456789abcdef";
    for (seed, 0..) |b, i| {
        hex[i * 2] = HEX[b >> 4];
        hex[i * 2 + 1] = HEX[b & 0x0f];
    }
    try std.testing.expectEqualStrings(
        "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04",
        &hex,
    );
}

test "parseIdioma: alias y errores" {
    try std.testing.expectEqual(Idioma.en, parseIdioma("EN").?);
    try std.testing.expectEqual(Idioma.en, parseIdioma("ingles").?);
    try std.testing.expectEqual(Idioma.en, parseIdioma("inglés").?);
    try std.testing.expectEqual(Idioma.es, parseIdioma("es").?);
    try std.testing.expectEqual(Idioma.es, parseIdioma("Espanol").?);
    try std.testing.expectEqual(Idioma.es, parseIdioma("español").?);
    try std.testing.expect(parseIdioma("de") == null);
    try std.testing.expect(parseIdioma("") == null);
}

test "BIP-39 es: vector cero -> abaco...abierto + seed TREZOR" {
    const ent: [16]u8 = @splat(0);
    var mbuf: [MAX_MNEMONICO]u8 = undefined;
    const frase = try fraseDeEntropiaIdioma(.es, &ent, &mbuf);
    try std.testing.expectEqualStrings(
        "a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco " ++
            "a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco abierto",
        frase,
    );

    // Ida y vuelta y validación en español; no valida en inglés.
    var ebuf: [32]u8 = undefined;
    const back = try entropiaDeFraseIdioma(.es, frase, &ebuf);
    try std.testing.expectEqualSlices(u8, &ent, back);
    try std.testing.expect(validaFraseIdioma(.es, frase));
    try std.testing.expect(!validaFraseIdioma(.en, frase));

    // Seed oficial (verificada con la librería de referencia `mnemonic`).
    const seed = seedDeFrase(frase, "TREZOR");
    var hex: [128]u8 = undefined;
    const HEX = "0123456789abcdef";
    for (seed, 0..) |b, i| {
        hex[i * 2] = HEX[b >> 4];
        hex[i * 2 + 1] = HEX[b & 0x0f];
    }
    try std.testing.expectEqualStrings(
        "29a2ee16de47d07025de37e7d9c596869439f9bcd26a702d2bae64db2bf0f68383841c5444b5b3bd39dd720d2ebe59969e110e5955c8e6d32c6c3294fd87439b",
        &hex,
    );
}

test "BIP-39 es: 24 palabras caben en MAX_MNEMONICO" {
    const ent: [32]u8 = @splat(0);
    var mbuf: [MAX_MNEMONICO]u8 = undefined;
    const frase = try fraseDeEntropiaIdioma(.es, &ent, &mbuf);
    try std.testing.expect((frase.len > 0) and (frase.len < MAX_MNEMONICO));
    try std.testing.expect(validaFraseIdioma(.es, frase));
}

test "BIP-32: vector 1 (m/0' de la semilla de prueba)" {
    const seed = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    const leaf = try hoja(&seed, "m/0'");
    const priv = leaf.getPrivateKey().?;
    var hex: [64]u8 = undefined;
    const HEX = "0123456789abcdef";
    for (priv, 0..) |b, i| {
        hex[i * 2] = HEX[b >> 4];
        hex[i * 2 + 1] = HEX[b & 0x0f];
    }
    try std.testing.expectEqualStrings("edb2e14f9ee77d26dd93b4ecede8d16ed408ce149b6cd80b0715a2d911a0afea", &hex);
}

test "BIP-44: mnemónico de prueba -> 1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA" {
    const frase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    const seed = seedDeFrase(frase, "");
    var d: Derivada = undefined;
    try derivarEstandar(&seed, .btc_p2pkh, 0, 0, 0, &d);
    try std.testing.expectEqualStrings("m/44'/0'/0'/0/0", d.ruta[0..d.ruta_len]);
    try std.testing.expectEqualStrings("1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA", d.l.dir[0..d.l.dir_len]);
}

test "rutas estándar por tipo y economía de ETH" {
    var b: [MAX_RUTA]u8 = undefined;
    try std.testing.expectEqualStrings("m/49'/0'/0'/0/0", rutaEstandar(.btc_p2sh_p2wpkh, 0, 0, 0, &b).?);
    try std.testing.expectEqualStrings("m/84'/0'/0'/1/7", rutaEstandar(.btc_p2wpkh, 0, 1, 7, &b).?);
    try std.testing.expectEqualStrings("m/86'/0'/0'/0/0", rutaEstandar(.btc_p2tr, 0, 0, 0, &b).?);
    try std.testing.expectEqualStrings("m/44'/60'/0'/0/0", rutaEstandar(.eth, 0, 0, 0, &b).?);
}

test "derivación reproducible y distinta por índice/cambio/cuenta" {
    const seed = seedDeFrase("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", "");
    var a: Derivada = undefined;
    var b: Derivada = undefined;
    try derivarEstandar(&seed, .btc_p2wpkh, 0, 0, 0, &a);
    try derivarEstandar(&seed, .btc_p2wpkh, 0, 0, 0, &b);
    try std.testing.expectEqualSlices(u8, a.l.dir[0..a.l.dir_len], b.l.dir[0..b.l.dir_len]);

    try derivarEstandar(&seed, .btc_p2wpkh, 0, 0, 1, &b);
    try std.testing.expect(!std.mem.eql(u8, a.l.dir[0..a.l.dir_len], b.l.dir[0..b.l.dir_len]));
    try derivarEstandar(&seed, .btc_p2wpkh, 0, 1, 0, &b);
    try std.testing.expect(!std.mem.eql(u8, a.l.dir[0..a.l.dir_len], b.l.dir[0..b.l.dir_len]));
    try derivarEstandar(&seed, .btc_p2wpkh, 1, 0, 0, &b);
    try std.testing.expect(!std.mem.eql(u8, a.l.dir[0..a.l.dir_len], b.l.dir[0..b.l.dir_len]));
}

test "seleccion: 'todos' y alias" {
    try std.testing.expect(seleccion("todos").?.todos);
    try std.testing.expect(seleccion("TODOS").?.todos);
    try std.testing.expectEqual(Tipo.eth, seleccion("ethereum").?.uno);
    try std.testing.expectEqual(Tipo.btc_p2tr, seleccion("btc-taproot").?.uno);
    try std.testing.expect(seleccion("nope") == null);
}

const FRASE_EN = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const FRASE_ES = "a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco " ++
    "a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco a\xcc\x81baco abierto";

test "decodificarFrase: explícito estricto y autodetección en|es" {
    var buf: [32]u8 = undefined;

    // Autodetección: cada frase se reconoce sin decir el idioma.
    const d_en = try decodificarFrase(FRASE_EN, null, &buf);
    try std.testing.expectEqual(Idioma.en, d_en.idioma);
    try std.testing.expectEqual(@as(usize, 16), d_en.entropia.len);

    const d_es = try decodificarFrase(FRASE_ES, null, &buf);
    try std.testing.expectEqual(Idioma.es, d_es.idioma);

    // Explícito (estricto, sin fallback): el idioma correcto funciona...
    try std.testing.expectEqual(Idioma.en, (try decodificarFrase(FRASE_EN, .en, &buf)).idioma);
    try std.testing.expectEqual(Idioma.es, (try decodificarFrase(FRASE_ES, .es, &buf)).idioma);

    // ...y el incorrecto falla (no se autodetecta si diste idioma).
    try std.testing.expectError(error.WordNotFound, decodificarFrase(FRASE_ES, .en, &buf));

    // Checksum roto en inglés: se reporta el error del inglés (mensaje útil).
    const mala = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon";
    try std.testing.expectError(error.InvalidChecksum, decodificarFrase(mala, null, &buf));
    try std.testing.expectError(error.InvalidChecksum, decodificarFrase(mala, .en, &buf));

    // Basura corta.
    try std.testing.expectError(error.InvalidWordCount, decodificarFrase("hola mundo", null, &buf));
}

test "privadaDeRuta coincide con derivarEstandar" {
    const seed = seedDeFrase(FRASE_EN, "");
    var d: Derivada = undefined;
    try derivarEstandar(&seed, .btc_p2tr, 0, 0, 7, &d);

    var rb: [MAX_RUTA]u8 = undefined;
    const ruta = rutaEstandar(.btc_p2tr, 0, 0, 7, &rb).?;
    var priv: [32]u8 = undefined;
    try privadaDeRuta(&seed, ruta, &priv);
    try std.testing.expectEqualSlices(u8, &d.l.priv, &priv);

    try std.testing.expectError(error.RutaInvalida, privadaDeRuta(&seed, "", &priv));
}
