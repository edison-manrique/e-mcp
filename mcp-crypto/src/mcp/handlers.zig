// Handlers de herramientas MCP (1 por herramienta). Cada uno:
//   1. lee y valida parámetros,
//   2. llama al dominio (`bc/`),
//   3. arma el JSON (`core/jsonw.zig`) y lo envía (`core/proto.zig`).
//
// Agregar una herramienta = handler aquí + LIST_* + 1 línea en `mcp/tools.zig`.

const std = @import("std");
const Io = std.Io;
const proto = @import("../core/proto.zig");
const jsonw = @import("../core/jsonw.zig");
const bc = @import("../bc/tool.zig");
const ayuda = @import("../ayuda.zig");

const clave = bc.clave;
const vanity = bc.vanity;
const puzzle = bc.puzzle;
const seed = bc.entropy;
const punto = bc.punto;
const aead = bc.aead;
const secp = bc.secp;
const BigInt256 = bc.secp.BigInt256;

fn err(ctx: proto.Ctx, e: anyerror) Io.Writer.Error!void {
    try proto.sendToolError(ctx.out, ctx.id, bc.msgFor(e));
}

/// Error de patrón con el alfabeto del tipo concreto (mejor que el genérico).
fn errPatron(ctx: proto.Ctx, tipo: clave.Tipo, e: anyerror) Io.Writer.Error!void {
    var buf: [320]u8 = undefined;
    const msg = switch (e) {
        error.InvalidBase58Char, error.InvalidBech32Char, error.InvalidHexChar => std.fmt.bufPrint(
            &buf,
            "Patrón inválido para {s}: usa {s}.",
            .{ clave.tipoNombre(tipo), clave.alfabetoTipo(tipo) },
        ) catch bc.msgFor(e),
        else => bc.msgFor(e),
    };
    try proto.sendToolError(ctx.out, ctx.id, msg);
}

fn sendJson(ctx: proto.Ctx, text: []const u8) Io.Writer.Error!void {
    try proto.sendToolText(ctx.out, ctx.id, text);
}

fn modoNombre(m: clave.Modo) []const u8 {
    return switch (m) {
        .starts_with => "prefijo",
        .ends_with => "sufijo",
        .contains => "contiene",
    };
}

// ---------- derivar ----------

pub fn runDerivar(ctx: proto.Ctx) Io.Writer.Error!void {
    // `tipo` aquí elige la RUTA estándar cuando el origen es un mnemónico
    // (p2pkh m/44', p2sh m/49', p2wpkh m/84', p2tr m/86', eth m/44'/60').
    const tipo = clave.parseTipo(proto.argStr(ctx.args, "tipo", "p2pkh")) orelse return err(ctx, error.TipoInvalido);

    var idioma_arg: ?bc.mnemo.Idioma = null;
    if (proto.argStrOpt(ctx.args, "idioma")) |s|
        idioma_arg = bc.mnemo.parseIdioma(s) orelse return err(ctx, error.IdiomaInvalido);

    const cuenta = leerIndice(ctx.args, "cuenta", error.RangoInvalido) catch |e| return err(ctx, e);
    const cambio = leerIndice(ctx.args, "cambio", error.RangoInvalido) catch |e| return err(ctx, e);
    const indice = leerIndice(ctx.args, "indice", error.RangoInvalido) catch |e| return err(ctx, e);

    const ruta = proto.argStrOpt(ctx.args, "ruta");
    if (ruta) |r| {
        if (r.len == 0 or r.len > bc.mnemo.MAX_RUTA) return err(ctx, error.RutaInvalida);
    }

    var priv: [32]u8 = undefined;
    var origen: ?jsonw.OrigenMnem = null;
    var ruta_buf: [bc.mnemo.MAX_RUTA]u8 = undefined;

    if (proto.argStrOpt(ctx.args, "mnemonico") orelse proto.argStrOpt(ctx.args, "frase")) |frase| {
        if (frase.len == 0 or frase.len > bc.mnemo.MAX_MNEMONICO) return err(ctx, error.MnemonicoInvalido);
        const passphrase = proto.argStrOpt(ctx.args, "passphrase") orelse "";
        if (passphrase.len > bc.mnemo.MAX_PASSPHRASE) return err(ctx, error.PassphraseInvalida);

        var ebuf: [32]u8 = undefined;
        const dec = bc.mnemo.decodificarFrase(frase, idioma_arg, &ebuf) catch |e| return err(ctx, e);
        const ruta_txt: []const u8 = if (ruta) |r|
            r
        else
            bc.mnemo.rutaEstandar(tipo, cuenta, cambio, indice, &ruta_buf) orelse return err(ctx, error.RutaInvalida);

        const seedv = bc.mnemo.seedDeFrase(frase, passphrase);
        bc.mnemo.privadaDeRuta(&seedv, ruta_txt, &priv) catch |e| return err(ctx, e);
        origen = .{ .frase = frase, .idioma = dec.idioma, .passphrase = passphrase.len > 0, .ruta = ruta_txt };
    } else {
        const s = proto.argStrOpt(ctx.args, "clave") orelse
            return proto.sendToolError(ctx.out, ctx.id, "Falta 'clave' (hex de 64, decimal o WIF) o 'mnemonico'/'frase'.");
        if (s.len == 0 or s.len > bc.MAX_TEXTO)
            return proto.sendToolError(ctx.out, ctx.id, "Invalid params: 'clave' vacía o demasiado larga.");
        priv = clave.parseClave(s) catch |e| return err(ctx, e);
    }

    const c = clave.derivarTodo(&priv) catch |e| return err(ctx, e);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writeDerivar(&aw.writer, &c, origen) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- generar ----------

pub fn runGenerar(ctx: proto.Ctx) Io.Writer.Error!void {
    const tipo_s = proto.argStr(ctx.args, "tipo", "p2pkh");
    const tipo = clave.parseTipo(tipo_s) orelse return err(ctx, error.TipoInvalido);

    const cantidad_i = proto.argInt(ctx.args, "cantidad") orelse 1;
    if (cantidad_i < 1 or cantidad_i > bc.MAX_CANTIDAD) return err(ctx, error.CantidadInvalida);
    const cantidad: usize = @intCast(cantidad_i);

    const comprimida = proto.argBool(ctx.args, "comprimida", true);
    const semilla = proto.argStrOpt(ctx.args, "semilla");
    const semilla_hex = proto.argStrOpt(ctx.args, "semilla_hex");
    if (semilla) |s| {
        if (s.len > bc.MAX_SEMILLA) return err(ctx, error.LongitudInvalida);
    }

    var sem: seed.Origen = undefined;
    seed.resolver(ctx.io, &sem, semilla, semilla_hex);

    var rng = bc.secp.rng.ChaCha20Rng.init(.{
        .manual_seed_hex = sem.semillaHex(),
        .extra_entropy = sem.extraEntropia(),
        .thread_id = 0,
    });

    const items = ctx.arena.alloc(clave.Ligera, cantidad) catch |e| return err(ctx, e);
    for (items) |*it| {
        const sc = rng.generateScalar256();
        var b: [32]u8 = undefined;
        sc.toBytes(&b);
        clave.derivarLigera(&b, tipo, comprimida, it) catch |e| return err(ctx, e);
    }

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writeGenerar(&aw.writer, items, clave.tipoNombre(tipo), comprimida, sem.info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- vanity ----------

pub fn runVanity(ctx: proto.Ctx) Io.Writer.Error!void {
    const tipo_s = proto.argStr(ctx.args, "tipo", "p2pkh");
    const tipo = clave.parseTipo(tipo_s) orelse return err(ctx, error.TipoInvalido);

    var pat_buf: [bc.MAX_PATRONES][]const u8 = undefined;
    var n: usize = 0;
    if (proto.argArray(ctx.args, "patrones")) |arr| {
        for (arr.items) |it| {
            if (n >= bc.MAX_PATRONES) return err(ctx, error.PatronInvalido);
            if (it != .string) return err(ctx, error.PatronInvalido);
            pat_buf[n] = it.string;
            n += 1;
        }
    } else if (proto.argStrOpt(ctx.args, "patron")) |p| {
        pat_buf[0] = p;
        n = 1;
    }
    if (n == 0) return err(ctx, error.SinPatrones);
    for (pat_buf[0..n]) |p| {
        if (p.len == 0) return err(ctx, error.SinPatrones);
        if (p.len > bc.MAX_PATRON) return err(ctx, error.PatronInvalido);
    }

    const modo = clave.parseModo(proto.argStr(ctx.args, "modo", "prefijo")) orelse return err(ctx, error.ModoInvalido);
    const sensible = proto.argBool(ctx.args, "sensible", proto.argBool(ctx.args, "mayusculas", false));

    const cantidad_i = proto.argInt(ctx.args, "cantidad") orelse 1;
    if (cantidad_i < 1 or cantidad_i > bc.MAX_CANTIDAD) return err(ctx, error.CantidadInvalida);
    const cantidad: u32 = @intCast(cantidad_i);

    const seg_i = proto.argInt(ctx.args, "segundos") orelse proto.argInt(ctx.args, "max_time") orelse bc.DEF_SEGUNDOS_VANITY;
    if (seg_i < 1 or seg_i > bc.MAX_SEGUNDOS) return err(ctx, error.TiempoInvalido);
    const segundos: u32 = @intCast(seg_i);

    var max_int: u64 = 0;
    if (proto.argInt(ctx.args, "max_intentos")) |mi| {
        if (mi < 0) return err(ctx, error.CantidadInvalida);
        max_int = @intCast(mi);
    }

    const hilos_i = proto.argInt(ctx.args, "hilos") orelse 0;
    if (hilos_i < 0 or hilos_i > bc.MAX_HILOS) return err(ctx, error.HilosInvalidos);

    const semilla = proto.argStrOpt(ctx.args, "semilla");
    const semilla_hex = proto.argStrOpt(ctx.args, "semilla_hex");
    if (semilla) |s| {
        if (s.len > bc.MAX_SEMILLA) return err(ctx, error.LongitudInvalida);
    }
    var sem: seed.Origen = undefined;
    seed.resolver(ctx.io, &sem, semilla, semilla_hex);

    const pet = vanity.Pet{
        .tipo = tipo,
        .patrones = pat_buf[0..n],
        .modo = modo,
        .sensible = sensible,
        .cantidad = cantidad,
        .segundos = segundos,
        .max_intentos = max_int,
        .hilos = @intCast(hilos_i),
        .semilla_hex = sem.semillaHex(),
        .extra_entropy = sem.extraEntropia(),
    };

    const out = ctx.arena.alloc(vanity.Hallazgo, cantidad) catch |e| return err(ctx, e);
    const res = vanity.buscar(ctx.io, ctx.arena, &pet, out) catch |e| return errPatron(ctx, tipo, e);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    const patron_txt: []const u8 = if (n == 1) pat_buf[0] else "<multi>";
    jsonw.writeVanity(&aw.writer, clave.tipoNombre(tipo), patron_txt, modoNombre(modo), cantidad, res, out[0..res.encontrados], pat_buf[0..n], sem.info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- puzzle ----------

fn parseRango(r: []const u8) !struct { min: BigInt256, max: BigInt256 } {
    const idx = std.mem.indexOfScalar(u8, r, ':') orelse return error.RangoInvalido;
    const a = std.mem.trim(u8, r[0..idx], " \t");
    const b = std.mem.trim(u8, r[idx + 1 ..], " \t");
    if (a.len == 0 or b.len == 0) return error.RangoInvalido;
    const min = try bc.hex.parseBigIntAny(a);
    const max = try bc.hex.parseBigIntAny(b);
    if (min.isGreaterOrEqual(max)) return error.RangoInvalido;
    return .{ .min = min, .max = max };
}

pub fn runPuzzle(ctx: proto.Ctx) Io.Writer.Error!void {
    const pk_s = proto.argStrOpt(ctx.args, "pubkey") orelse proto.argStrOpt(ctx.args, "clave_publica") orelse
        return proto.sendToolError(ctx.out, ctx.id, "Falta 'pubkey' (33 o 65 bytes hex). Ej: 02abc...");
    const target = clave.parsePubkey(pk_s) catch |e| return err(ctx, e);

    var min: BigInt256 = undefined;
    var max: BigInt256 = undefined;
    var bits: ?u32 = null;

    if (proto.argStrOpt(ctx.args, "rango")) |r| {
        const rr = parseRango(r) catch |e| return err(ctx, e);
        min = rr.min;
        max = rr.max;
    } else if (proto.argInt(ctx.args, "bits")) |b| {
        if (b < 2 or b > 256) return err(ctx, error.RangoInvalido);
        bits = @intCast(b);
        const rr = clave.rangoDeBits(bits.?) catch |e| return err(ctx, e);
        min = rr.min;
        max = rr.max;
    } else {
        return proto.sendToolError(ctx.out, ctx.id, "Falta 'bits' (2-256) o 'rango' (\"min:max\" hex).");
    }

    const seg_i = proto.argInt(ctx.args, "segundos") orelse proto.argInt(ctx.args, "max_time") orelse bc.DEF_SEGUNDOS_PUZZLE;
    if (seg_i < 1 or seg_i > bc.MAX_SEGUNDOS) return err(ctx, error.TiempoInvalido);
    const segundos: u32 = @intCast(seg_i);

    var max_it: u64 = 0;
    if (proto.argInt(ctx.args, "max_iteraciones")) |mi| {
        if (mi < 0) return err(ctx, error.CantidadInvalida);
        max_it = @intCast(mi);
    }

    const hilos_i = proto.argInt(ctx.args, "hilos") orelse 0;
    if (hilos_i < 0 or hilos_i > bc.MAX_HILOS) return err(ctx, error.HilosInvalidos);

    var dist_bits: u32 = 0;
    if (proto.argInt(ctx.args, "dist_bits")) |d| {
        if (d < 0 or d > 32) return err(ctx, error.RangoInvalido);
        dist_bits = @intCast(d);
    }
    var jump_size: u32 = 0;
    if (proto.argInt(ctx.args, "jump_size")) |j| {
        if (j != 0 and (j < 8 or j > 1024)) return err(ctx, error.RangoInvalido);
        jump_size = @intCast(j);
    }

    const semilla = proto.argStrOpt(ctx.args, "semilla");
    const semilla_hex = proto.argStrOpt(ctx.args, "semilla_hex");
    if (semilla) |s| {
        if (s.len > bc.MAX_SEMILLA) return err(ctx, error.LongitudInvalida);
    }
    var sem: seed.Origen = undefined;
    seed.resolver(ctx.io, &sem, semilla, semilla_hex);

    const pet = puzzle.Pet{
        .target = target,
        .min = min,
        .max = max,
        .segundos = segundos,
        .max_iteraciones = max_it,
        .hilos = @intCast(hilos_i),
        .dist_bits = dist_bits,
        .jump_size = jump_size,
        .semilla_hex = sem.hexSiempre(),
    };

    const res = puzzle.resolver(ctx.io, ctx.arena, &pet) catch |e| return err(ctx, e);

    var cvar: clave.Clave = undefined;
    var have_c = false;
    if (res.encontrada) {
        cvar = clave.derivarTodo(&res.clave) catch undefined;
        have_c = true;
    }

    var hmin: [64]u8 = undefined;
    var hmax: [64]u8 = undefined;
    const smin = bc.hex.bigToHexTrim(min, &hmin);
    const smax = bc.hex.bigToHexTrim(max, &hmax);
    var rt: [140]u8 = undefined;
    const rango_txt = std.fmt.bufPrint(&rt, "{s}:{s}", .{ smin, smax }) catch "?";

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePuzzle(&aw.writer, rango_txt, bits, res, if (have_c) &cvar else null, sem.info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- mnemonico ----------

/// Lee el índice (cuenta/cambio/indice) aplicando la cota segura.
fn leerIndice(args: ?std.json.Value, key: []const u8, e: anyerror) !u32 {
    const v = proto.argInt(args, key) orelse return 0;
    if (v < 0 or v > bc.mnemo.MAX_INDICE) return e;
    return @intCast(v);
}

pub fn runMnemonico(ctx: proto.Ctx) Io.Writer.Error!void {
    const tipo_s = proto.argStr(ctx.args, "tipo", "todos");
    const sel = bc.mnemo.seleccion(tipo_s) orelse return err(ctx, error.TipoInvalido);

    const passphrase = proto.argStrOpt(ctx.args, "passphrase") orelse "";
    if (passphrase.len > bc.mnemo.MAX_PASSPHRASE) return err(ctx, error.PassphraseInvalida);

    var idioma_arg: ?bc.mnemo.Idioma = null;
    if (proto.argStrOpt(ctx.args, "idioma")) |s| {
        idioma_arg = bc.mnemo.parseIdioma(s) orelse return err(ctx, error.IdiomaInvalido);
    }
    // Generación: idioma por defecto `en`. Derivación: si no lo dices, se
    // autodetecta (prueba `en` y luego `es`).
    const idioma: bc.mnemo.Idioma = idioma_arg orelse .en;

    const cuenta = leerIndice(ctx.args, "cuenta", error.RangoInvalido) catch |e| return err(ctx, e);
    const cambio = leerIndice(ctx.args, "cambio", error.RangoInvalido) catch |e| return err(ctx, e);
    const indice = leerIndice(ctx.args, "indice", error.RangoInvalido) catch |e| return err(ctx, e);

    const ruta = proto.argStrOpt(ctx.args, "ruta");
    if (ruta) |r| {
        if (r.len == 0 or r.len > bc.mnemo.MAX_RUTA) return err(ctx, error.RutaInvalida);
    }

    var tipos: [bc.mnemo.TODOS.len]clave.Tipo = undefined;
    var n_tipos: usize = 0;
    if (sel.todos) {
        for (bc.mnemo.TODOS) |t| {
            tipos[n_tipos] = t;
            n_tipos += 1;
        }
    } else {
        tipos[0] = sel.uno;
        n_tipos = 1;
    }
    const tipo_txt: []const u8 = if (sel.todos) "todos" else clave.tipoNombre(sel.uno);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();

    // (a) Derivar desde una frase dada.
    if (proto.argStrOpt(ctx.args, "mnemonico") orelse proto.argStrOpt(ctx.args, "frase")) |frase| {
        if (frase.len == 0 or frase.len > bc.mnemo.MAX_MNEMONICO) return err(ctx, error.MnemonicoInvalido);
        var ebuf: [32]u8 = undefined;
        const dec = bc.mnemo.decodificarFrase(frase, idioma_arg, &ebuf) catch |e| return err(ctx, e);
        const ent = dec.entropia;
        const seedv = bc.mnemo.seedDeFrase(frase, passphrase);

        const dirs = ctx.arena.alloc(bc.mnemo.Derivada, n_tipos) catch |e| return err(ctx, e);
        for (tipos[0..n_tipos], 0..) |t, k| {
            if (ruta) |r|
                bc.mnemo.derivarRuta(&seedv, r, t, &dirs[k]) catch |e| return err(ctx, e)
            else
                bc.mnemo.derivarEstandar(&seedv, t, cuenta, cambio, indice, &dirs[k]) catch |e| return err(ctx, e);
        }

        const palabras = bc.mnemo.palabrasDeEntropia(ent.len) orelse 12;
        const items = [_]jsonw.ItemMnem{.{ .frase = frase, .entropia = ent, .seed = &seedv, .dirs = dirs }};
        jsonw.writeMnemonico(&aw.writer, palabras, passphrase.len > 0, tipo_txt, dec.idioma, null, &items) catch |e| return err(ctx, e);
        return sendJson(ctx, aw.written());
    }

    // (b) Generar N mnemónicos aleatorios (o deterministas con semilla).
    const palabras_i = proto.argInt(ctx.args, "palabras") orelse 12;
    if (palabras_i < 0) return err(ctx, error.PalabrasInvalidas);
    const palabras: u32 = @intCast(palabras_i);
    const eb = bc.mnemo.entropiaBytes(palabras) orelse return err(ctx, error.PalabrasInvalidas);

    const cant_i = proto.argInt(ctx.args, "cantidad") orelse 1;
    if (cant_i < 1 or cant_i > bc.mnemo.MAX_CANTIDAD)
        return proto.sendToolError(ctx.out, ctx.id, "Cantidad inválida para mnemónico (1-20).");
    const cant: usize = @intCast(cant_i);

    const semilla = proto.argStrOpt(ctx.args, "semilla");
    const semilla_hex = proto.argStrOpt(ctx.args, "semilla_hex");
    if (semilla) |s| {
        if (s.len > bc.MAX_SEMILLA) return err(ctx, error.LongitudInvalida);
    }
    var sem: seed.Origen = undefined;
    seed.resolver(ctx.io, &sem, semilla, semilla_hex);

    var rng = bc.secp.rng.ChaCha20Rng.init(.{
        .manual_seed_hex = sem.semillaHex(),
        .extra_entropy = sem.extraEntropia(),
        .thread_id = 0,
    });

    const frases = ctx.arena.alloc([bc.mnemo.MAX_MNEMONICO]u8, cant) catch |e| return err(ctx, e);
    const ents = ctx.arena.alloc([32]u8, cant) catch |e| return err(ctx, e);
    const seeds = ctx.arena.alloc([64]u8, cant) catch |e| return err(ctx, e);
    const all_dirs = ctx.arena.alloc(bc.mnemo.Derivada, cant * n_tipos) catch |e| return err(ctx, e);
    const items = ctx.arena.alloc(jsonw.ItemMnem, cant) catch |e| return err(ctx, e);

    for (0..cant) |i| {
        rng.fillBytes(ents[i][0..eb]);
        const frase = bc.mnemo.fraseDeEntropiaIdioma(idioma, ents[i][0..eb], &frases[i]) catch |e| return err(ctx, e);
        seeds[i] = bc.mnemo.seedDeFrase(frase, passphrase);
        const base = i * n_tipos;
        for (tipos[0..n_tipos], 0..) |t, k| {
            if (ruta) |r|
                bc.mnemo.derivarRuta(&seeds[i], r, t, &all_dirs[base + k]) catch |e| return err(ctx, e)
            else
                bc.mnemo.derivarEstandar(&seeds[i], t, cuenta, cambio, indice, &all_dirs[base + k]) catch |e| return err(ctx, e);
        }
        items[i] = .{
            .frase = frase,
            .entropia = ents[i][0..eb],
            .seed = &seeds[i],
            .dirs = all_dirs[base .. base + n_tipos],
        };
    }

    jsonw.writeMnemonico(&aw.writer, palabras, passphrase.len > 0, tipo_txt, idioma, sem.info, items) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- entropia (health check) ----------

pub fn runEntropia(ctx: proto.Ctx) Io.Writer.Error!void {
    const s = seed.salud(ctx.io);
    var ftxt: [192]u8 = undefined;
    const fuentes = s.fuentes.lista(&ftxt);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writeEntropia(&aw.writer, s, fuentes) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- firmar / verificar (Schnorr BIP-340) ----------

/// Lee 'mensaje'/'mensaje_hex' a bytes crudos en `buf`.
fn leerMensaje(ctx: proto.Ctx, buf: []u8) Io.Writer.Error!?[]const u8 {
    return bc.firma.mensajeBytes(
        proto.argStrOpt(ctx.args, "mensaje"),
        proto.argStrOpt(ctx.args, "mensaje_hex"),
        buf,
    ) catch |e| {
        try err(ctx, e);
        return null;
    };
}

pub fn runFirmar(ctx: proto.Ctx) Io.Writer.Error!void {
    const s = proto.argStrOpt(ctx.args, "clave") orelse
        return proto.sendToolError(ctx.out, ctx.id, "Falta 'clave' (hex de 64, decimal o WIF).");
    if (s.len == 0 or s.len > bc.MAX_TEXTO)
        return proto.sendToolError(ctx.out, ctx.id, "Invalid params: 'clave' vacía o demasiado larga.");
    const priv = clave.parseClave(s) catch |e| return err(ctx, e);

    var msgbuf: [bc.firma.MAX_MENSAJE]u8 = undefined;
    const msg = (try leerMensaje(ctx, &msgbuf)) orelse return;

    // `aux`: explícita (hex de 32 B) o derivada del motor de entropía.
    var aux: [32]u8 = undefined;
    var info: ?bc.entropy.Info = null;
    if (proto.argStrOpt(ctx.args, "aux")) |aux_s| {
        aux = bc.firma.parseHexExact(32, aux_s) catch |e| return err(ctx, e);
    } else {
        const semilla = proto.argStrOpt(ctx.args, "semilla");
        const semilla_hex = proto.argStrOpt(ctx.args, "semilla_hex");
        if (semilla) |sv| {
            if (sv.len > bc.MAX_SEMILLA) return err(ctx, error.LongitudInvalida);
        }
        var sem: seed.Origen = undefined;
        seed.resolver(ctx.io, &sem, semilla, semilla_hex);
        var rng = bc.secp.rng.ChaCha20Rng.init(.{
            .manual_seed_hex = sem.semillaHex(),
            .extra_entropy = sem.extraEntropia(),
            .thread_id = 0,
        });
        rng.fillBytes(&aux);
        info = sem.info;
    }

    const res = bc.firma.firmar(msg, &priv, &aux) catch |e| return err(ctx, e);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writeFirmar(&aw.writer, res, &aux, msg, info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

pub fn runVerificar(ctx: proto.Ctx) Io.Writer.Error!void {
    const pk_s = proto.argStrOpt(ctx.args, "pubkey") orelse proto.argStrOpt(ctx.args, "clave_publica") orelse
        return proto.sendToolError(ctx.out, ctx.id, "Falta 'pubkey' (x-only de 32 B o comprimida de 33 B).");
    const pubkey = bc.firma.parseXOnly(pk_s) catch |e| return err(ctx, e);

    const firma_s = proto.argStrOpt(ctx.args, "firma") orelse
        return proto.sendToolError(ctx.out, ctx.id, "Falta 'firma' (hex de 64 bytes).");
    const firma = bc.firma.parseHexExact(64, firma_s) catch |e| return err(ctx, e);

    var msgbuf: [bc.firma.MAX_MENSAJE]u8 = undefined;
    const msg = (try leerMensaje(ctx, &msgbuf)) orelse return;

    const valida = bc.firma.verificar(msg, &pubkey, &firma);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writeVerificar(&aw.writer, valida, &pubkey, msg, &firma) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- aritmética de puntos (secp256k1) ----------

fn primerStr(args: ?std.json.Value, keys: []const []const u8) ?[]const u8 {
    for (keys) |k| {
        if (proto.argStrOpt(args, k)) |v| return v;
    }
    return null;
}

/// Lee una pubkey (x-only/33/65) o el literal "G"/"generador". Envía el error
/// al cliente y devuelve null si falta o es inválida.
fn leerPunto(ctx: proto.Ctx, keys: []const []const u8, nombre: []const u8, y_impar: bool) Io.Writer.Error!?secp.Point {
    const s = primerStr(ctx.args, keys) orelse {
        var b: [192]u8 = undefined;
        const m = std.fmt.bufPrint(&b, "Falta '{s}' (pubkey hex x-only de 64, comprimida de 66 o sin comprimir de 130; o 'generador').", .{nombre}) catch "Falta pubkey.";
        try proto.sendToolError(ctx.out, ctx.id, m);
        return null;
    };
    if (s.len == 0 or s.len > bc.MAX_TEXTO) {
        try err(ctx, error.LongitudInvalida);
        return null;
    }
    if (std.ascii.eqlIgnoreCase(s, "g") or std.ascii.eqlIgnoreCase(s, "generador")) return secp.Point.G;
    const af = punto.parsePunto(s, y_impar) catch |e| {
        try err(ctx, e);
        return null;
    };
    return punto.aPoint(af);
}

pub fn runPuntoMul(ctx: proto.Ctx) Io.Writer.Error!void {
    const y_impar = proto.argBool(ctx.args, "y_impar", false);

    // Sin 'pubkey' el punto base es el generador G (k*G).
    var base: secp.Point = secp.Point.G;
    if (primerStr(ctx.args, &.{ "pubkey", "p", "punto" }) != null) {
        base = (try leerPunto(ctx, &.{ "pubkey", "p", "punto" }, "pubkey", y_impar)) orelse return;
    }

    const esc_s = primerStr(ctx.args, &.{ "escalar", "k" }) orelse {
        try proto.sendToolError(ctx.out, ctx.id, "Falta 'escalar' (hex o decimal, 1..N-1; si solo tiene dígitos se lee como decimal, prefija 0x para hex).");
        return;
    };
    if (esc_s.len == 0 or esc_s.len > bc.MAX_TEXTO) return err(ctx, error.LongitudInvalida);
    const k = punto.parseEscalar(esc_s) catch |e| return err(ctx, e);

    var info: punto.Info = undefined;
    punto.infoDe(punto.multiplicar(base, k), &info);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePuntoMul(&aw.writer, &info, k) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

pub fn runPuntoAdd(ctx: proto.Ctx) Io.Writer.Error!void {
    const y_impar = proto.argBool(ctx.args, "y_impar", false);
    const a = (try leerPunto(ctx, &.{ "pubkey_a", "a" }, "pubkey_a", y_impar)) orelse return;
    const b = (try leerPunto(ctx, &.{ "pubkey_b", "b" }, "pubkey_b", y_impar)) orelse return;

    var info: punto.Info = undefined;
    punto.infoDe(punto.sumar(a, b), &info);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePuntoOp(&aw.writer, "punto_add", &info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

pub fn runPuntoSub(ctx: proto.Ctx) Io.Writer.Error!void {
    const y_impar = proto.argBool(ctx.args, "y_impar", false);
    const a = (try leerPunto(ctx, &.{ "pubkey_a", "a" }, "pubkey_a", y_impar)) orelse return;
    const b = (try leerPunto(ctx, &.{ "pubkey_b", "b" }, "pubkey_b", y_impar)) orelse return;

    var info: punto.Info = undefined;
    punto.infoDe(punto.restar(a, b), &info);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePuntoOp(&aw.writer, "punto_sub", &info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

pub fn runPuntoNeg(ctx: proto.Ctx) Io.Writer.Error!void {
    const y_impar = proto.argBool(ctx.args, "y_impar", false);
    const a = (try leerPunto(ctx, &.{ "pubkey", "p", "punto" }, "pubkey", y_impar)) orelse return;

    var info: punto.Info = undefined;
    punto.infoDe(punto.negar(a), &info);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePuntoOp(&aw.writer, "punto_neg", &info) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

pub fn runPuntoDiv(ctx: proto.Ctx) Io.Writer.Error!void {
    const y_impar = proto.argBool(ctx.args, "y_impar", false);
    const a = (try leerPunto(ctx, &.{ "pubkey", "p", "punto" }, "pubkey", y_impar)) orelse return;

    var dbuf: [80]u8 = undefined;
    var div_txt: []const u8 = "2";
    if (primerStr(ctx.args, &.{ "divisor", "m" })) |s| {
        div_txt = s;
    } else if (proto.argInt(ctx.args, "divisor")) |n| {
        if (n <= 0) return err(ctx, error.RangoInvalido);
        div_txt = std.fmt.bufPrint(&dbuf, "{d}", .{n}) catch "2";
    }
    if (div_txt.len == 0 or div_txt.len > bc.MAX_TEXTO) return err(ctx, error.LongitudInvalida);
    const m = punto.parseEscalar(div_txt) catch |e| return err(ctx, e);

    const r = punto.dividir(a, m);
    const verificado = punto.iguales(punto.multiplicar(r, m), a);
    var info: punto.Info = undefined;
    punto.infoDe(r, &info);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePuntoDiv(&aw.writer, &info, m, verificado) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

/// Hexágono GLV: 3 X {X, βX, β²X} y 6 vértices {±P, ±λP, ±λ²P}.
/// Con `escalar` añade los 6 escalares y verifica las relaciones.
pub fn runHexagono(ctx: proto.Ctx) Io.Writer.Error!void {
    const y_impar = proto.argBool(ctx.args, "y_impar", false);

    var k: ?secp.Scalar256 = null;
    if (primerStr(ctx.args, &.{ "escalar", "k" })) |esc_s| {
        if (esc_s.len == 0 or esc_s.len > bc.MAX_TEXTO) return err(ctx, error.LongitudInvalida);
        k = punto.parseEscalar(esc_s) catch |e| return err(ctx, e);
    }

    const pk_s = primerStr(ctx.args, &.{ "pubkey", "p", "punto" });
    var base: secp.Point = undefined;
    if (pk_s) |s| {
        if (s.len == 0 or s.len > bc.MAX_TEXTO) return err(ctx, error.LongitudInvalida);
        base = if (std.ascii.eqlIgnoreCase(s, "g") or std.ascii.eqlIgnoreCase(s, "generador"))
            secp.Point.G
        else
            punto.aPoint(punto.parsePunto(s, y_impar) catch |e| return err(ctx, e));

        // Si vienen ambos, deben describir el mismo punto.
        if (k) |kk| {
            if (!punto.iguales(base, punto.multiplicarG(kk))) return err(ctx, error.PuntoInvalido);
        }
    } else if (k) |kk| {
        base = punto.multiplicarG(kk);
    } else {
        try proto.sendToolError(ctx.out, ctx.id, "Falta 'pubkey' o 'escalar' (al menos uno).");
        return;
    }

    const hexa = punto.hexagono(base, k);

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writeHexagono(&aw.writer, &hexa) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- cifrar / descifrar / poly1305 ----------

const Algo = aead.Algoritmo;
const parseAlgo = aead.parseAlgoritmo;
const algoNombre = aead.nombreAlgoritmo;
const esX = aead.esX;
const esAead = aead.esAead;

fn leerExacto(comptime n: usize, s: []const u8) ![n]u8 {
    const t = bc.hex.trim0x(std.mem.trim(u8, s, " \t\r\n"));
    if (t.len != 2 * n) return error.LongitudInvalida;
    var out: [n]u8 = undefined;
    for (0..n) |i| {
        const hi = bc.hex.hexVal(t[2 * i]) orelse return error.HexInvalido;
        const lo = bc.hex.hexVal(t[2 * i + 1]) orelse return error.HexInvalido;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn leerHexAlloc(ctx: proto.Ctx, s: []const u8, max: usize) ![]const u8 {
    const t = bc.hex.trim0x(std.mem.trim(u8, s, " \t\r\n"));
    if (t.len % 2 != 0) return error.HexInvalido;
    const n = t.len / 2;
    if (n > max) return error.EntradaInvalida;
    const out = try ctx.arena.alloc(u8, n);
    for (0..n) |i| {
        const hi = bc.hex.hexVal(t[2 * i]) orelse return error.HexInvalido;
        const lo = bc.hex.hexVal(t[2 * i + 1]) orelse return error.HexInvalido;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

/// Lee `text_key` (UTF-8) o `hex_key` (hex, prioritario). `required` decide
/// si la ausencia es error; si no, devuelve un slice vacío.
fn leerBytes(
    ctx: proto.Ctx,
    text_key: []const u8,
    hex_key: []const u8,
    max: usize,
    required: bool,
    falta: []const u8,
) Io.Writer.Error!?[]const u8 {
    if (proto.argStrOpt(ctx.args, hex_key)) |s| {
        return leerHexAlloc(ctx, s, max) catch |e| {
            try err(ctx, e);
            return null;
        };
    }
    if (proto.argStrOpt(ctx.args, text_key)) |s| {
        if (s.len > max) {
            try err(ctx, error.EntradaInvalida);
            return null;
        }
        const out = ctx.arena.alloc(u8, s.len) catch |e| {
            try err(ctx, e);
            return null;
        };
        @memcpy(out, s);
        return out;
    }
    if (required) {
        try proto.sendToolError(ctx.out, ctx.id, falta);
        return null;
    }
    return "";
}

fn rellenarAleatorio(ctx: proto.Ctx, out: []u8) void {
    var sem: seed.Origen = undefined;
    seed.resolver(ctx.io, &sem, null, null);
    var rng = bc.secp.rng.ChaCha20Rng.init(.{
        .manual_seed_hex = sem.semillaHex(),
        .extra_entropy = sem.extraEntropia(),
        .thread_id = 0,
    });
    rng.fillBytes(out);
}

fn leerClave(ctx: proto.Ctx, generada: *bool, permitir_generar: bool) Io.Writer.Error!?[32]u8 {
    if (proto.argStrOpt(ctx.args, "clave")) |s| {
        return leerExacto(32, s) catch |e| {
            try err(ctx, e);
            return null;
        };
    }
    if (!permitir_generar) {
        try proto.sendToolError(ctx.out, ctx.id, "Falta 'clave' (32 bytes en hex).");
        return null;
    }
    var k: [32]u8 = undefined;
    rellenarAleatorio(ctx, &k);
    generada.* = true;
    return k;
}

/// Nonce de 12 B (ChaCha20) o 24 B (XChaCha20), o aleatorio si falta.
fn leerNonce12(ctx: proto.Ctx, generado: *bool, permitir_generar: bool) Io.Writer.Error!?[12]u8 {
    if (proto.argStrOpt(ctx.args, "nonce")) |s| {
        return leerExacto(12, s) catch |e| {
            try err(ctx, e);
            return null;
        };
    }
    if (!permitir_generar) {
        try proto.sendToolError(ctx.out, ctx.id, "Falta 'nonce' (12 bytes en hex).");
        return null;
    }
    var n: [12]u8 = undefined;
    rellenarAleatorio(ctx, &n);
    generado.* = true;
    return n;
}

fn leerNonce24(ctx: proto.Ctx, generado: *bool, permitir_generar: bool) Io.Writer.Error!?[24]u8 {
    if (proto.argStrOpt(ctx.args, "nonce")) |s| {
        return leerExacto(24, s) catch |e| {
            try err(ctx, e);
            return null;
        };
    }
    if (!permitir_generar) {
        try proto.sendToolError(ctx.out, ctx.id, "Falta 'nonce' (24 bytes en hex).");
        return null;
    }
    var n: [24]u8 = undefined;
    rellenarAleatorio(ctx, &n);
    generado.* = true;
    return n;
}

fn leerHilosCrypto(ctx: proto.Ctx) Io.Writer.Error!?usize {
    const h = proto.argInt(ctx.args, "hilos") orelse 0;
    if (h < 0 or h > bc.MAX_HILOS) {
        try err(ctx, error.HilosInvalidos);
        return null;
    }
    return @intCast(h);
}

fn entradaMixta(ctx: proto.Ctx) Io.Writer.Error!void {
    try proto.sendToolError(ctx.out, ctx.id, "Usa 'ruta' (archivo) o los campos de texto/ciphertext, no ambos.");
}

fn elegirSalida(ctx: proto.Ctx, ruta: []const u8, cifrando: bool) Io.Writer.Error!?[]const u8 {
    if (proto.argStrOpt(ctx.args, "salida")) |s| {
        if (s.len > 0) return s;
    }
    return bc.filecrypto.salidaPorDefecto(ctx.arena, ruta, cifrando) catch |e| {
        try err(ctx, e);
        return null;
    };
}

pub fn runCifrar(ctx: proto.Ctx) Io.Writer.Error!void {
    const algo = parseAlgo(proto.argStr(ctx.args, "algoritmo", "xchacha20poly1305")) orelse
        return err(ctx, error.AlgoritmoInvalido);

    var clave_gen = false;
    const key = (try leerClave(ctx, &clave_gen, true)) orelse return;

    const aad = (try leerBytes(ctx, "aad", "aad_hex", bc.MAX_AEAD_BYTES, false, "")) orelse return;
    if (!esAead(algo) and aad.len > 0) return err(ctx, error.AadSinAead);

    const hilos = (try leerHilosCrypto(ctx)) orelse return;

    if (proto.argStrOpt(ctx.args, "ruta")) |ruta| {
        if (ruta.len == 0) return err(ctx, error.RutaArchivoInvalida);
        if (proto.argStrOpt(ctx.args, "texto") != null or proto.argStrOpt(ctx.args, "texto_hex") != null) {
            return entradaMixta(ctx);
        }
        const salida = (try elegirSalida(ctx, ruta, true)) orelse return;
        var nonce_gen = false;
        var nonce_buf: [24]u8 = undefined;
        var nonce_slice: []const u8 = undefined;
        if (esX(algo)) {
            const n = (try leerNonce24(ctx, &nonce_gen, true)) orelse return;
            nonce_buf = n;
            nonce_slice = nonce_buf[0..24];
        } else {
            const n = (try leerNonce12(ctx, &nonce_gen, true)) orelse return;
            @memcpy(nonce_buf[0..12], &n);
            nonce_slice = nonce_buf[0..12];
        }
        const res = bc.filecrypto.cifrarArchivo(ctx.io, ctx.arena, ruta, salida, algo, &key, nonce_slice, aad, hilos) catch |e| return err(ctx, e);
        var aw: Io.Writer.Allocating = .init(ctx.arena);
        defer aw.deinit();
        jsonw.writeCifrarArchivo(&aw.writer, &res, clave_gen, nonce_gen) catch |e| return err(ctx, e);
        return sendJson(ctx, aw.written());
    }

    const pt = (try leerBytes(ctx, "texto", "texto_hex", bc.MAX_AEAD_BYTES, true, "Falta 'texto' o 'texto_hex'.")) orelse return;

    const ct = ctx.arena.alloc(u8, pt.len) catch |e| return err(ctx, e);
    var tag: [16]u8 = undefined;
    var nonce_gen = false;

    if (esX(algo)) {
        const nonce = (try leerNonce24(ctx, &nonce_gen, true)) orelse return;
        if (esAead(algo)) {
            aead.xchacha20poly1305_encrypt(&key, &nonce, aad, pt, ct, &tag) catch |e| return err(ctx, e);
        } else {
            aead.xchacha20_xor(&key, &nonce, 0, pt, ct) catch |e| return err(ctx, e);
        }
        var aw: Io.Writer.Allocating = .init(ctx.arena);
        defer aw.deinit();
        jsonw.writeCifrar(&aw.writer, algoNombre(algo), &key, &nonce, aad, ct, if (esAead(algo)) &tag else null, clave_gen, nonce_gen) catch |e| return err(ctx, e);
        return sendJson(ctx, aw.written());
    } else {
        const nonce = (try leerNonce12(ctx, &nonce_gen, true)) orelse return;
        if (esAead(algo)) {
            aead.chacha20poly1305_encrypt(&key, &nonce, aad, pt, ct, &tag) catch |e| return err(ctx, e);
        } else {
            aead.chacha20_xor(&key, &nonce, 0, pt, ct) catch |e| return err(ctx, e);
        }
        var aw: Io.Writer.Allocating = .init(ctx.arena);
        defer aw.deinit();
        jsonw.writeCifrar(&aw.writer, algoNombre(algo), &key, &nonce, aad, ct, if (esAead(algo)) &tag else null, clave_gen, nonce_gen) catch |e| return err(ctx, e);
        return sendJson(ctx, aw.written());
    }
}

pub fn runDescifrar(ctx: proto.Ctx) Io.Writer.Error!void {
    var clave_gen = false;
    const key = (try leerClave(ctx, &clave_gen, false)) orelse return;

    const aad = (try leerBytes(ctx, "aad", "aad_hex", bc.MAX_AEAD_BYTES, false, "")) orelse return;

    const hilos = (try leerHilosCrypto(ctx)) orelse return;

    if (proto.argStrOpt(ctx.args, "ruta")) |ruta| {
        if (ruta.len == 0) return err(ctx, error.RutaArchivoInvalida);
        if (proto.argStrOpt(ctx.args, "combinado_hex") != null or
            proto.argStrOpt(ctx.args, "ciphertext") != null or
            proto.argStrOpt(ctx.args, "ciphertext_hex") != null or
            proto.argStrOpt(ctx.args, "tag") != null or
            proto.argStrOpt(ctx.args, "tag_hex") != null or
            proto.argStrOpt(ctx.args, "texto") != null or
            proto.argStrOpt(ctx.args, "texto_hex") != null)
        {
            return entradaMixta(ctx);
        }
        const salida = (try elegirSalida(ctx, ruta, false)) orelse return;
        var algo_esp: ?aead.Algoritmo = null;
        if (proto.argStrOpt(ctx.args, "algoritmo")) |s| {
            algo_esp = parseAlgo(s) orelse return err(ctx, error.AlgoritmoInvalido);
        }
        var nonce_esp: ?[]const u8 = null;
        if (proto.argStrOpt(ctx.args, "nonce")) |s| {
            nonce_esp = leerHexAlloc(ctx, s, aead.XNONCE_BYTES) catch |e| return err(ctx, e);
        }
        const res = bc.filecrypto.descifrarArchivo(ctx.io, ctx.arena, ruta, salida, &key, algo_esp, nonce_esp, aad, hilos) catch |e| return err(ctx, e);
        var aw: Io.Writer.Allocating = .init(ctx.arena);
        defer aw.deinit();
        jsonw.writeDescifrarArchivo(&aw.writer, &res) catch |e| return err(ctx, e);
        return sendJson(ctx, aw.written());
    }

    const algo = parseAlgo(proto.argStr(ctx.args, "algoritmo", "xchacha20poly1305")) orelse
        return err(ctx, error.AlgoritmoInvalido);
    if (!esAead(algo) and aad.len > 0) return err(ctx, error.AadSinAead);

    var ct: []const u8 = undefined;
    var tag: [16]u8 = undefined;
    if (esAead(algo)) {
        if (proto.argStrOpt(ctx.args, "combinado_hex")) |s| {
            const all = leerHexAlloc(ctx, s, bc.MAX_AEAD_BYTES + 16) catch |e| return err(ctx, e);
            if (all.len < 16) return err(ctx, error.TagInvalido);
            ct = all[0 .. all.len - 16];
            @memcpy(&tag, all[all.len - 16 ..]);
        } else {
            ct = (try leerBytes(ctx, "ciphertext", "ciphertext_hex", bc.MAX_AEAD_BYTES, true, "Falta 'combinado_hex' o 'ciphertext_hex' (+ 'tag').")) orelse return;
            const tag_s = proto.argStrOpt(ctx.args, "tag") orelse proto.argStrOpt(ctx.args, "tag_hex") orelse
                return proto.sendToolError(ctx.out, ctx.id, "Falta 'tag' (16 bytes hex) o usa 'combinado_hex'.");
            tag = leerExacto(16, tag_s) catch |e| return err(ctx, e);
        }
    } else {
        ct = (try leerBytes(ctx, "ciphertext", "ciphertext_hex", bc.MAX_AEAD_BYTES, true, "Falta 'ciphertext_hex'.")) orelse return;
    }

    const pt = ctx.arena.alloc(u8, ct.len) catch |e| return err(ctx, e);
    var nonce_gen = false;
    var valido: ?bool = null;

    if (esX(algo)) {
        const nonce = (try leerNonce24(ctx, &nonce_gen, false)) orelse return;
        if (esAead(algo)) {
            valido = aead.xchacha20poly1305_decrypt(&key, &nonce, aad, ct, &tag, pt) catch |e| return err(ctx, e);
        } else {
            aead.xchacha20_xor(&key, &nonce, 0, ct, pt) catch |e| return err(ctx, e);
        }
    } else {
        const nonce = (try leerNonce12(ctx, &nonce_gen, false)) orelse return;
        if (esAead(algo)) {
            valido = aead.chacha20poly1305_decrypt(&key, &nonce, aad, ct, &tag, pt) catch |e| return err(ctx, e);
        } else {
            aead.chacha20_xor(&key, &nonce, 0, ct, pt) catch |e| return err(ctx, e);
        }
    }

    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    if (valido != null and !valido.?) {
        jsonw.writeDescifrar(&aw.writer, algoNombre(algo), false, "") catch |e| return err(ctx, e);
    } else {
        jsonw.writeDescifrar(&aw.writer, algoNombre(algo), valido, pt) catch |e| return err(ctx, e);
    }
    try sendJson(ctx, aw.written());
}

pub fn runPoly1305(ctx: proto.Ctx) Io.Writer.Error!void {
    var clave_gen = false;
    const key = (try leerClave(ctx, &clave_gen, false)) orelse return;
    const msg = (try leerBytes(ctx, "mensaje", "mensaje_hex", bc.MAX_AEAD_BYTES, true, "Falta 'mensaje' o 'mensaje_hex'.")) orelse return;

    const tag = aead.poly1305_mac(&key, msg);
    var aw: Io.Writer.Allocating = .init(ctx.arena);
    defer aw.deinit();
    jsonw.writePoly1305(&aw.writer, &key, msg.len, &tag, clave_gen) catch |e| return err(ctx, e);
    try sendJson(ctx, aw.written());
}

// ---------- help ----------

pub fn runHelp(ctx: proto.Ctx) Io.Writer.Error!void {
    const topic = proto.argStr(ctx.args, "topic", "all");
    const md = ayuda.topicMd(topic) orelse
        return proto.sendToolError(ctx.out, ctx.id, "topic desconocido. Usa: " ++ ayuda.TOPICS);
    try sendJson(ctx, md);
}
