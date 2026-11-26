const std = @import("std");
const schnorr = @import("root.zig");
const scalar = @import("../scalar/root.zig");
const testing = std.testing;

/// ═══════════════════════════════════════════════════════════════════════════
///  secp256k1-fast/schnorr/tests.zig — Vectores oficiales BIP-340
/// ═══════════════════════════════════════════════════════════════════════════
///  Fuente: bitcoin/bips → bip-0340/test-vectors.csv (19 filas).
///  Se valida FIRMA (filas con clave secreta) y VERIFICACIÓN (todas las filas).
/// ═══════════════════════════════════════════════════════════════════════════

const Vector = struct {
    sk: ?[]const u8 = null,
    pk: []const u8,
    aux: ?[]const u8 = null,
    msg: []const u8,
    sig: []const u8,
    valid: bool,
};

const vectors = [_]Vector{
    // 0
    .{ .sk = "0000000000000000000000000000000000000000000000000000000000000003", .pk = "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9", .aux = "0000000000000000000000000000000000000000000000000000000000000000", .msg = "0000000000000000000000000000000000000000000000000000000000000000", .sig = "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0", .valid = true },
    // 1
    .{ .sk = "B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF", .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .aux = "0000000000000000000000000000000000000000000000000000000000000001", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A", .valid = true },
    // 2
    .{ .sk = "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9", .pk = "DD308AFEC5777E13121FA72B9CC1B7CC0139715309B086C960E18FD969774EB8", .aux = "C87AA53824B4D7AE2EB035A2B5BBBCCC080E76CDC6D1692C4B0B62D798E6D906", .msg = "7E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C", .sig = "5831AAEED7B44BB74E5EAB94BA9D4294C49BCF2A60728D8B4C200F50DD313C1BAB745879A5AD954A72C45A91C3A51D3C7ADEA98D82F8481E0E1E03674A6F3FB7", .valid = true },
    // 3
    .{ .sk = "0B432B2677937381AEF05BB02A66ECD012773062CF3FA2549E44F58ED2401710", .pk = "25D1DFF95105F5253C4022F628A996AD3A0D95FBF21D468A1B33F8C160D8F517", .aux = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", .msg = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", .sig = "7EB0509757E246F19449885651611CB965ECC1A187DD51B64FDA1EDC9637D5EC97582B9CB13DB3933705B32BA982AF5AF25FD78881EBB32771FC5922EFC66EA3", .valid = true },
    // 4 (verify-only)
    .{ .pk = "D69C3509BB99E412E68B0FE8544E72837DFA30746D8BE2AA65975F29D22DC7B9", .msg = "4DF3C3F68FCC83B27E9D42C90431A72499F17875C81A599B566C9889B9696703", .sig = "00000000000000000000003B78CE563F89A0ED9414F5AA28AD0D96D6795F9C6376AFB1548AF603B3EB45C9F8207DEE1060CB71C04E80F593060B07D28308D7F4", .valid = true },
    // 5 — public key not on the curve
    .{ .pk = "EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", .valid = false },
    // 6 — has_even_y(R) is false
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "FFF97BD5755EEEA420453A14355235D382F6472F8568A18B2F057A14602975563CC27944640AC607CD107AE10923D9EF7A73C643E166BE5EBEAFA34B1AC553E2", .valid = false },
    // 7 — negated message
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "1FA62E331EDBC21C394792D2AB1100A7B432B013DF3F6FF4F99FCB33E0E1515F28890B3EDB6E7189B630448B515CE4F8622A954CFE545735AAEA5134FCCDB2BD", .valid = false },
    // 8 — negated s value
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769961764B3AA9B2FFCB6EF947B6887A226E8D7C93E00C5ED0C1834FF0D0C2E6DA6", .valid = false },
    // 9 — sG - eP infinite (x(inf) as 0)
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "0000000000000000000000000000000000000000000000000000000000000000123DDA8328AF9C23A94C1FEECFD123BA4FB73476F0D594DCB65C6425BD186051", .valid = false },
    // 10 — sG - eP infinite (x(inf) as 1)
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "00000000000000000000000000000000000000000000000000000000000000017615FBAF5AE28864013C099742DEADB4DBA87F11AC6754F93780D5A1837CF197", .valid = false },
    // 11 — sig[0:32] not an X coordinate on the curve
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "4A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1D69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", .valid = false },
    // 12 — sig[0:32] equal to field size
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", .valid = false },
    // 13 — sig[32:64] equal to curve order
    .{ .pk = "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", .valid = false },
    // 14 — public key exceeds field size
    .{ .pk = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC30", .msg = "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", .sig = "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", .valid = false },
    // 15 — message of size 0
    .{ .sk = "0340034003400340034003400340034003400340034003400340034003400340", .pk = "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", .aux = "0000000000000000000000000000000000000000000000000000000000000000", .msg = "", .sig = "71535DB165ECD9FBBC046E5FFAEA61186BB6AD436732FCCC25291A55895464CF6069CE26BF03466228F19A3A62DB8A649F2D560FAC652827D1AF0574E427AB63", .valid = true },
    // 16 — message of size 1
    .{ .sk = "0340034003400340034003400340034003400340034003400340034003400340", .pk = "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", .aux = "0000000000000000000000000000000000000000000000000000000000000000", .msg = "11", .sig = "08A20A0AFEF64124649232E0693C583AB1B9934AE63B4C3511F3AE1134C6A303EA3173BFEA6683BD101FA5AA5DBC1996FE7CACFC5A577D33EC14564CEC2BACBF", .valid = true },
    // 17 — message of size 17
    .{ .sk = "0340034003400340034003400340034003400340034003400340034003400340", .pk = "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", .aux = "0000000000000000000000000000000000000000000000000000000000000000", .msg = "0102030405060708090A0B0C0D0E0F1011", .sig = "5130F39A4059B43BC7CAC09A19ECE52B5D8699D1A71E3C52DA9AFDB6B50AC370C4A482B77BF960F8681540E25B6771ECE1E5A37FD80E5A51897C5566A97EA5A5", .valid = true },
    // 18 — message of size 100
    .{ .sk = "0340034003400340034003400340034003400340034003400340034003400340", .pk = "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", .aux = "0000000000000000000000000000000000000000000000000000000000000000", .msg = "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999", .sig = "403B12B0D8555A344175EA7EC746566303321E5DBFA8BE6F091635163ECA79A8585ED3E3170807E7C03B720FC54C7B23897FCBA0E9D0B4A06894CFD249F22367", .valid = true },
};

fn decodeHex(comptime n: usize, hex_str: []const u8, out: *[n]u8) []u8 {
    return std.fmt.hexToBytes(out, hex_str) catch unreachable;
}

test "schnorr: vectores oficiales BIP-340 (firma + verificación)" {
    for (vectors, 0..) |v, idx| {
        var pk: [32]u8 = undefined;
        _ = decodeHex(32, v.pk, &pk);

        var sig_buf: [64]u8 = undefined;
        _ = decodeHex(64, v.sig, &sig_buf);
        const sig = schnorr.Signature.fromBytes(&sig_buf);

        var msg_buf: [128]u8 = undefined;
        const msg = decodeHex(128, v.msg, &msg_buf);

        // Verificación (todas las filas)
        testing.expectEqual(v.valid, schnorr.verify(msg, &pk, sig)) catch |err| {
            std.debug.print("verify falló en vector {d}\n", .{idx});
            return err;
        };

        // Firma (sólo filas con clave secreta)
        if (v.sk) |sk_hex| {
            var sk: [32]u8 = undefined;
            _ = decodeHex(32, sk_hex, &sk);

            var aux: [32]u8 = undefined;
            _ = decodeHex(32, v.aux.?, &aux);

            const derived = try schnorr.publicKey(&sk);
            testing.expectEqualSlices(u8, &pk, &derived) catch |err| {
                std.debug.print("pubkey falló en vector {d}\n", .{idx});
                return err;
            };

            const produced = try schnorr.sign(msg, &sk, &aux);
            testing.expectEqualSlices(u8, &sig_buf, &produced.toBytes()) catch |err| {
                std.debug.print("sign falló en vector {d}\n", .{idx});
                return err;
            };
        }
    }
}

test "schnorr: rechaza clave secreta 0 y >= N" {
    const zero: [32]u8 = @splat(0);
    try testing.expectError(error.InvalidSecretKey, schnorr.keyPair(&zero));

    var n_bytes: [32]u8 = undefined;
    scalar.Scalar256.N.toBytes(&n_bytes);
    try testing.expectError(error.InvalidSecretKey, schnorr.keyPair(&n_bytes));

    var n_minus_one: [32]u8 = undefined;
    scalar.Scalar256.N.sub(scalar.Scalar256.one).toBytes(&n_minus_one);
    _ = try schnorr.keyPair(&n_minus_one);
}

test "schnorr: roundtrip y detección de manipulación" {
    var seed: u64 = 0x123456789ABCDEF0;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        var sk: [32]u8 = undefined;
        var aux: [32]u8 = undefined;
        var msg: [64]u8 = undefined;
        for (&sk) |*b| {
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            b.* = @truncate(seed >> 33);
        }
        for (&aux) |*b| {
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            b.* = @truncate(seed >> 33);
        }
        for (&msg) |*b| {
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            b.* = @truncate(seed >> 33);
        }
        const sk_scalar = scalar.Scalar256.fromBytes(&sk);
        var normalized = sk;
        if (sk_scalar.isZero() or sk_scalar.isGreaterOrEqual(scalar.Scalar256.N)) {
            normalized = @splat(0);
            normalized[31] = 1;
        }

        const pk = try schnorr.publicKey(&normalized);
        const sig = try schnorr.sign(&msg, &normalized, &aux);
        try testing.expect(schnorr.verify(&msg, &pk, sig));

        // mensaje alterado → inválida
        var msg_bad = msg;
        msg_bad[0] ^= 0x01;
        try testing.expect(!schnorr.verify(&msg_bad, &pk, sig));

        // firma alterada → inválida
        var sig_bad = sig;
        sig_bad.s[31] ^= 0x01;
        try testing.expect(!schnorr.verify(&msg, &pk, sig_bad));

        // clave pública alterada → inválida (o punto fuera de curva)
        var pk_bad = pk;
        pk_bad[0] ^= 0x01;
        try testing.expect(!schnorr.verify(&msg, &pk_bad, sig));

        // determinismo con la misma aux
        const sig2 = try schnorr.sign(&msg, &normalized, &aux);
        try testing.expectEqualSlices(u8, &sig.toBytes(), &sig2.toBytes());
    }
}

test "schnorr: aux aleatoria cambia la firma pero ambas verifican" {
    var sk: [32]u8 = undefined;
    @memset(&sk, 0);
    sk[31] = 7;
    var msg: [32]u8 = @splat(0xAB);
    const aux0: [32]u8 = @splat(0);
    var aux1: [32]u8 = @splat(0);
    aux1[0] = 1;

    const pk = try schnorr.publicKey(&sk);
    const s0 = try schnorr.sign(&msg, &sk, &aux0);
    const s1 = try schnorr.sign(&msg, &sk, &aux1);

    try testing.expect(!std.mem.eql(u8, &s0.toBytes(), &s1.toBytes()));
    try testing.expect(schnorr.verify(&msg, &pk, s0));
    try testing.expect(schnorr.verify(&msg, &pk, s1));
}

test "schnorr: liftX devuelve Y par y rechaza x >= P" {
    const gx = [_]u8{ 0x79, 0xBE, 0x66, 0x7E, 0xF9, 0xDC, 0xBB, 0xAC, 0x55, 0xA0, 0x62, 0x95, 0xCE, 0x87, 0x0B, 0x07, 0x02, 0x9B, 0xFC, 0xDB, 0x2D, 0xCE, 0x28, 0xD9, 0x59, 0xF2, 0x81, 0x5B, 0x16, 0xF8, 0x17, 0x98 };
    const p = schnorr.liftX(&gx).?;
    try testing.expect(!p.toAffine().y.isOdd());

    const p_bytes: [32]u8 = @splat(0xFF); // > P
    try testing.expect(schnorr.liftX(&p_bytes) == null);
}
