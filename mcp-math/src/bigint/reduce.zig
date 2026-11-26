const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.zig");
const addsub = @import("addsub.zig");

// Reduccion modular mod P = 2^256 - 2^32 - 977.
// Entrada: entero de 512 bits (low, high). Salida: < P.
const has_bmi2 = builtin.cpu.arch == .x86_64 and
    builtin.abi != .msvc and
    std.Target.x86.featureSetHas(builtin.cpu.features, .bmi2);

pub fn reduce(low: [4]u64, high: [4]u64) [4]u64 {
    if (comptime !has_bmi2) {
        return reduceGeneric(low, high);
    }
    return reduceAsm(low, high);
}

pub fn reduceGeneric(low: [4]u64, high: [4]u64) [4]u64 {
    const h = high;
    const term_mul = mulScalar4(h[0], h[1], h[2], h[3], 977);
    const term_shift = shiftLeft32_4(h[0], h[1], h[2], h[3]);
    var res = low;
    const c1 = addsub.add(res, term_mul.limbs);
    const c2 = addsub.add(c1.limbs, term_shift);
    res = c2.limbs;
    var total_carry: u64 = @as(u64, c1.carry) + @as(u64, c2.carry) + term_mul.carry + (h[3] >> 32);

    // Paso 1: reduce el acarreo.
    {
        const c_val = total_carry;
        const t1 = c_val * 977;
        const t2_low = c_val << 32;
        const t2_high = c_val >> 32;
        const add1 = addsub.add(res, .{ t1, 0, 0, 0 });
        const add2 = addsub.add(add1.limbs, .{ t2_low, t2_high, 0, 0 });
        res = add2.limbs;
        total_carry = @as(u64, add1.carry) + @as(u64, add2.carry);
    }

    // Paso 2: acarreo final pequeño.
    {
        const c_val = total_carry;
        const t1 = c_val * 977;
        const t2_low = c_val << 32;
        const t2_high = c_val >> 32;
        const add1 = addsub.add(res, .{ t1, 0, 0, 0 });
        const add2 = addsub.add(add1.limbs, .{ t2_low, t2_high, 0, 0 });
        res = add2.limbs;
    }

    // Ajuste final: si res >= P, res -= P.
    const res_sub_p = addsub.sub(res, constants.P_LIMBS);
    if (res_sub_p.borrow == 0) {
        res = res_sub_p.limbs;
    }

    return res;
}

pub noinline fn reduceAsm(low: [4]u64, high: [4]u64) [4]u64 {
    if (@inComptime() or comptime !has_bmi2) {
        return reduceGeneric(low, high);
    }
    var r0: u64 = low[0];
    var r1: u64 = low[1];
    var r2: u64 = low[2];
    var r3: u64 = low[3];
    const h0: u64 = high[0];
    const h1: u64 = high[1];
    const h2: u64 = high[2];
    const h3: u64 = high[3];

    asm volatile (
        \\xorq %%r8, %%r8
        \\movq $0x1000003D1, %%rdx
        \\
        \\mulxq %[h0], %%rax, %%rbx
        \\addq %%rax, %[r0]
        \\adcq %%rbx, %[r1]
        \\adcq $0, %[r2]
        \\adcq $0, %[r3]
        \\adcq $0, %%r8
        \\
        \\mulxq %[h1], %%rax, %%rbx
        \\addq %%rax, %[r1]
        \\adcq %%rbx, %[r2]
        \\adcq $0, %[r3]
        \\adcq $0, %%r8
        \\
        \\mulxq %[h2], %%rax, %%rbx
        \\addq %%rax, %[r2]
        \\adcq %%rbx, %[r3]
        \\adcq $0, %%r8
        \\
        \\mulxq %[h3], %%rax, %%rbx
        \\addq %%rax, %[r3]
        \\adcq %%rbx, %%r8
        \\
        \\movq %%r8, %%rdx
        \\movq $0x1000003D1, %%rax
        \\mulxq %%rax, %%rax, %%rbx
        \\addq %%rax, %[r0]
        \\adcq %%rbx, %[r1]
        \\adcq $0, %[r2]
        \\adcq $0, %[r3]
        \\
        \\movq $0, %%rax
        \\movq $0x1000003D1, %%rdx
        \\cmovc %%rdx, %%rax
        \\addq %%rax, %[r0]
        \\adcq $0, %[r1]
        \\adcq $0, %[r2]
        \\adcq $0, %[r3]
        \\
        \\movq %[r0], %%r8
        \\movq %[r1], %%r9
        \\movq %[r2], %%r10
        \\movq %[r3], %%r11
        \\
        \\movabsq $0xFFFFFFFEFFFFFC2F, %%rax
        \\subq %%rax, %%r8
        \\sbbq $-1, %%r9
        \\sbbq $-1, %%r10
        \\sbbq $-1, %%r11
        \\
        \\cmovnc %%r8, %[r0]
        \\cmovnc %%r9, %[r1]
        \\cmovnc %%r10, %[r2]
        \\cmovnc %%r11, %[r3]
        : [r0] "+r" (r0),
          [r1] "+r" (r1),
          [r2] "+r" (r2),
          [r3] "+r" (r3),
        : [h0] "rm" (h0),
          [h1] "rm" (h1),
          [h2] "rm" (h2),
          [h3] "rm" (h3),
        : .{ .rax = true, .rbx = true, .rdx = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .cc = true });

    return .{ r0, r1, r2, r3 };
}

inline fn mulScalar4(l0: u64, l1: u64, l2: u64, l3: u64, s: u64) struct { limbs: [4]u64, carry: u64 } {
    var res: [4]u64 = undefined;
    var carry: u64 = 0;
    var p: u128 = 0;

    p = @as(u128, l0) * s;
    res[0] = @as(u64, @truncate(p));
    carry = @as(u64, @truncate(p >> 64));

    p = @as(u128, l1) * s + carry;
    res[1] = @as(u64, @truncate(p));
    carry = @as(u64, @truncate(p >> 64));

    p = @as(u128, l2) * s + carry;
    res[2] = @as(u64, @truncate(p));
    carry = @as(u64, @truncate(p >> 64));

    p = @as(u128, l3) * s + carry;
    res[3] = @as(u64, @truncate(p));
    carry = @as(u64, @truncate(p >> 64));

    return .{ .limbs = res, .carry = carry };
}

inline fn shiftLeft32_4(l0: u64, l1: u64, l2: u64, l3: u64) [4]u64 {
    return .{ l0 << 32, (l1 << 32) | (l0 >> 32), (l2 << 32) | (l1 >> 32), (l3 << 32) | (l2 >> 32) };
}
