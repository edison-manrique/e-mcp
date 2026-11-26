// Tests del motor de regex (aparte para que regex.zig quede enfocado).

const std = @import("std");
const rx = @import("regex.zig");

const compile = rx.compile;
const expande = rx.expande;

// ---------- Tests ----------

fn prueba(pat: []const u8, hay: []const u8, ci: bool) !bool {
    var re = try compile(std.testing.allocator, pat, .{ .ci = ci });
    defer re.deinit();
    return re.isMatch(hay);
}

test "regex: literales, punto y cuantificadores" {
    const t = std.testing;
    try t.expect(try prueba("abc", "xxabcxx", false));
    try t.expect(!try prueba("abc", "abx", false));
    try t.expect(try prueba("a.c", "abc", false));
    try t.expect(!try prueba("a.c", "a\nc", false)); // '.' no cruza línea
    try t.expect(try prueba("ab*c", "ac", false));
    try t.expect(try prueba("ab*c", "abbbc", false));
    try t.expect(!try prueba("ab+c", "ac", false));
    try t.expect(try prueba("ab?c", "ac", false));
    try t.expect(try prueba("ab?c", "abc", false));
    try t.expect(try prueba("a{2,3}", "aa", false));
    try t.expect(!try prueba("^a{2,3}$", "a", false));
    try t.expect(try prueba("^a{2,3}$", "aaa", false));
    try t.expect(try prueba("a{2,}", "aaaa", false));
}

test "regex: clases y rangos" {
    const t = std.testing;
    try t.expect(try prueba("[abc]", "xby", false));
    try t.expect(!try prueba("[a-z]", "Q", false));
    try t.expect(try prueba("[a-z]", "q", false));
    try t.expect(!try prueba("[^0-9]", "5", false));
    try t.expect(try prueba("[^0-9]", "x", false));
    try t.expect(try prueba("\\d+", "abc123", false));
    try t.expect(!try prueba("^\\d+$", "abc", false));
    try t.expect(try prueba("[A-F0-9]{4}", "BEEF", false));
    try t.expect(try prueba("[-a]", "-", false)); // '-' al inicio = literal
    try t.expect(try prueba("[a-]", "-", false));
}

test "regex: anclas y limites de palabra" {
    const t = std.testing;
    try t.expect(!try prueba("^a", "ba", false));
    try t.expect(try prueba("^a", "ab", false));
    try t.expect(try prueba("c$", "abc", false));
    try t.expect(!try prueba("c$", "abcd", false));
    try t.expect(try prueba("\\bfoo\\b", "a foo b", false));
    try t.expect(!try prueba("\\bfoo\\b", "afoob", false));
    try t.expect(try prueba("^$", "", false));
}

test "regex: alternancia y grupos" {
    const t = std.testing;
    try t.expect(try prueba("cat|dog", "xxdogxx", false));
    try t.expect(try prueba("(ab|cd)+", "abcd", false));
    try t.expect(try prueba("a(b|c)d", "acd", false));
    try t.expect(try prueba("(?:xy)+", "xyxy", false));
}

test "regex: case-insensitive" {
    const t = std.testing;
    try t.expect(try prueba("ABC", "xabcx", true));
    try t.expect(!try prueba("ABC", "xabcx", false));
    try t.expect(try prueba("[a-z]+", "ABC", true));
    try t.expect(try prueba("\\w+", "AbC", true));
}

test "regex: captura de grupos (submatches)" {
    const t = std.testing;
    var re = try compile(t.allocator, "(\\d+)-(\\d+)", .{});
    defer re.deinit();
    const m = re.find("COD 4501-77 fin").?;
    try t.expect(m.ini == 4 and m.fin == 11);
    const g1 = m.grupo(1).?;
    const g2 = m.grupo(2).?;
    try t.expect(g1.ini == 4 and g1.fin == 8); // "4501"
    try t.expect(g2.ini == 9 and g2.fin == 11); // "77"
    try t.expect(m.grupo(3) == null);
}

test "regex: grupo que no participa devuelve null" {
    const t = std.testing;
    var re = try compile(t.allocator, "a(b)?c", .{});
    defer re.deinit();
    const m = re.find("ac").?;
    try t.expect(m.grupo(1) == null);
    const m2 = re.find("abc").?;
    try t.expect(m2.grupo(1).?.ini == 1 and m2.grupo(1).?.fin == 2);
}

test "regex: replaceAll con $n, $0 y $$" {
    const t = std.testing;
    var re = try compile(t.allocator, "(\\w+)@(\\w+)", .{});
    defer re.deinit();
    const r = try re.replaceAll(t.allocator, "ana@x bob@y", "$2:$1");
    defer t.allocator.free(r.out);
    try t.expectEqualStrings("x:ana y:bob", r.out);
    try t.expect(r.n == 2);

    var re2 = try compile(t.allocator, "a", .{});
    defer re2.deinit();
    const r2 = try re2.replaceAll(t.allocator, "aaa", "$0$0");
    defer t.allocator.free(r2.out);
    try t.expectEqualStrings("aaaaaa", r2.out);

    var re3 = try compile(t.allocator, "b", .{});
    defer re3.deinit();
    const r3 = try re3.replaceAll(t.allocator, "b b", "[$$]");
    defer t.allocator.free(r3.out);
    try t.expectEqualStrings("[$] [$]", r3.out);
}

test "regex: flags s (dotall) y m (multiline)" {
    const t = std.testing;
    try t.expect(!try prueba("a.c", "a\nc", false)); // '.' no cruza '\n'
    try t.expect(try prueba("(?s)a.c", "a\nc", false)); // (?s) si
    try t.expect(try prueba("(?s:a.c)", "a\nc", false)); // alcance (?s:...)
    try t.expect(!try prueba("^b", "a\nb", false)); // ^ = inicio de texto
    try t.expect(try prueba("(?m)^b", "a\nb", false)); // (?m) = inicio de linea
    try t.expect(!try prueba("a$", "a\nb", false));
    try t.expect(try prueba("(?m)a$", "a\nb", false));
}

test "regex: inline (?i) y (?-i)" {
    const t = std.testing;
    try t.expect(try prueba("(?i)abc", "ABC", false));
    try t.expect(!try prueba("(?i)a(?-i)bc", "AbC", false)); // 'bc' vuelve sensible
}

test "regex: demasiados grupos -> error" {
    const t = std.testing;
    try t.expectError(error.RegexGrande, compile(t.allocator, "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)(n)(o)(p)(q)(r)(s)(t)(u)", .{}));
}

test "regex: hasta 20 grupos y $12/${12}" {
    const t = std.testing;
    var re = try compile(t.allocator, "(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)", .{});
    defer re.deinit();
    const m = re.find("abcdefghijkl").?;
    try t.expect(m.grupo(12).?.ini == 11);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(t.allocator);
    try expande(t.allocator, &out, "abcdefghijkl", "$12$1", m, null);
    try t.expectEqualStrings("la", out.items);
    out.clearRetainingCapacity();
    try expande(t.allocator, &out, "abcdefghijkl", "${12}${1}", m, null);
    try t.expectEqualStrings("la", out.items);
}

test "regex: grupos con nombre (?P<n>) y (?<n>), $name" {
    const t = std.testing;
    var re = try compile(t.allocator, "(?P<k>\\w+)=(?<v>\\w+)", .{});
    defer re.deinit();
    try t.expectEqual(@as(?u8, 1), re.indiceNombre("k"));
    try t.expectEqual(@as(?u8, 2), re.indiceNombre("v"));
    try t.expectEqual(@as(?u8, null), re.indiceNombre("no_existe"));
    const m = re.find("name=ana").?;
    try t.expectEqualStrings("name", "name=ana"[m.grupo(1).?.ini..m.grupo(1).?.fin]);
    const r1 = try re.replaceAll(t.allocator, "name=ana", "$v=$k");
    defer t.allocator.free(r1.out);
    try t.expectEqualStrings("ana=name", r1.out);
    const r2 = try re.replaceAll(t.allocator, "name=ana", "${v}:${k}");
    defer t.allocator.free(r2.out);
    try t.expectEqualStrings("ana:name", r2.out);
    // Nombre inexistente: '$' literal, no se come el resto.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(t.allocator);
    try expande(t.allocator, &out, "name=ana", "$zzz", m, &re);
    try t.expectEqualStrings("$zzz", out.items);
}

test "regex: lookaround (?=) (?!) (?<=) (?<!)" {
    const t = std.testing;
    {
        // (?=...) no consume: 'foo' seguido de 'bar'
        var re = try compile(t.allocator, "foo(?=bar)", .{ .ci = true });
        defer re.deinit();
        const m = re.find("foobar").?;
        try t.expectEqual(@as(usize, 0), m.ini);
        try t.expectEqual(@as(usize, 3), m.fin);
        try t.expect(re.find("foobaz") == null);
    }
    {
        // (?!...): solo el 'foo' NO seguido de 'bar'
        var re = try compile(t.allocator, "foo(?!bar)", .{ .ci = true });
        defer re.deinit();
        const m = re.find("foobar foobaz").?;
        try t.expectEqual(@as(usize, 7), m.ini);
        try t.expectEqual(@as(usize, 10), m.fin);
    }
    {
        // lookahead positivo en el medio
        var re = try compile(t.allocator, "\\d+(?=px)", .{ .ci = true });
        defer re.deinit();
        const m = re.find("12px 34em").?;
        try t.expectEqual(@as(usize, 0), m.ini);
        try t.expectEqual(@as(usize, 2), m.fin);
        const r = try re.replaceAll(t.allocator, "12px 34em", "N");
        defer t.allocator.free(r.out);
        try t.expectEqualStrings("Npx 34em", r.out);
    }
    {
        // lookbehind de longitud fija
        var re = try compile(t.allocator, "(?<=@)\\w+", .{ .ci = true });
        defer re.deinit();
        const m = re.find("user@host.com").?;
        try t.expectEqual(@as(usize, 5), m.ini);
        try t.expectEqual(@as(usize, 9), m.fin);
        var re2 = try compile(t.allocator, "(?<=ab)c", .{ .ci = true });
        defer re2.deinit();
        const m2 = re2.find("xabc").?;
        try t.expectEqual(@as(usize, 3), m2.ini);
    }
    {
        // lookbehind de longitud VARIABLE (acotada): la coincidencia debe
        // terminar justo en la posicion de la asercion.
        var re = try compile(t.allocator, "(?<=a{1,3})b", .{ .ci = true });
        defer re.deinit();
        const m = re.find("aab").?;
        try t.expectEqual(@as(usize, 2), m.ini);
        // alternancia de distinta longitud
        var re2 = try compile(t.allocator, "(?<=ab|xyz)Q", .{ .ci = true });
        defer re2.deinit();
        const m2 = re2.find("abQ").?;
        try t.expectEqual(@as(usize, 2), m2.ini);
        // varios offsets: \d{2,3} justo antes de "px"
        var re3 = try compile(t.allocator, "(?<=\\d{2,3})px", .{ .ci = true });
        defer re3.deinit();
        const m3 = re3.find("12px 345px").?;
        try t.expectEqual(@as(usize, 2), m3.ini);
        const m3b = re3.findFrom("12px 345px", 3).?;
        try t.expectEqual(@as(usize, 8), m3b.ini);
    }
    {
        // lookbehind negativo
        var re = try compile(t.allocator, "(?<!\\d)x", .{ .ci = true });
        defer re.deinit();
        const m = re.find("ax1x").?;
        try t.expectEqual(@as(usize, 1), m.ini);
    }
    {
        // lookahead que no consume el siguiente char
        var re = try compile(t.allocator, "a(?=b)c", .{});
        defer re.deinit();
        try t.expect(re.find("abc") == null);
    }
    // lookbehind de longitud variable -> error claro
    try t.expectError(error.RegexLookbehind, compile(t.allocator, "(?<=a+)b", .{}));
}

test "regex: span y perezoso" {
    var re = try compile(std.testing.allocator, "b+", .{});
    defer re.deinit();
    const m = re.find("aabbbcc").?;
    try std.testing.expect(m.ini == 2 and m.fin == 5);

    var re2 = try compile(std.testing.allocator, "a.*?b", .{});
    defer re2.deinit();
    const m2 = re2.find("axbxb").?;
    try std.testing.expect(m2.ini == 0 and m2.fin == 3); // el 'b' mas cercano

    var re3 = try compile(std.testing.allocator, "a.*b", .{});
    defer re3.deinit();
    const m3 = re3.find("axbxb").?;
    try std.testing.expect(m3.fin == 5); // codicioso: hasta el ultimo 'b'
}

test "regex: iteradores (y matches vacios no cuelgan)" {
    const t = std.testing;
    var re = try compile(t.allocator, "\\d", .{});
    defer re.deinit();
    var it = re.iter("a1b2c3");
    var cuenta: usize = 0;
    while (it.next()) |_| cuenta += 1;
    try t.expect(cuenta == 3);

    var re2 = try compile(t.allocator, "a*", .{});
    defer re2.deinit();
    var it2 = re2.iter("bb");
    var c2: usize = 0;
    while (it2.next()) |_| c2 += 1;
    try t.expect(c2 == 3);
}

test "regex: errores de patron" {
    const t = std.testing;
    try t.expectError(error.PatronVacio, compile(t.allocator, "", .{}));
    try t.expectError(error.RegexGrupo, compile(t.allocator, "(abc", .{}));
    try t.expectError(error.RegexClase, compile(t.allocator, "[abc", .{}));
    try t.expectError(error.RegexCuant, compile(t.allocator, "*a", .{}));
    try t.expectError(error.RegexInvalido, compile(t.allocator, "abc)", .{}));
}

test "regex: sin retroceso patologico (a+)+$ sobre 'a...ab'" {
    const t = std.testing;
    const hay = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ++ "b";
    var re = try compile(t.allocator, "(a+)+$", .{});
    defer re.deinit();
    try t.expect(re.find(hay) == null); // termina rapido (lineal), no 2^n
}

