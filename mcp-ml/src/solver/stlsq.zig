// Copyright (c) 2026 Edison Manrique Chocce
// Todos los derechos reservados.
// Licencia Dual: AGPL-3.0 para uso académico/personal | Licencia Comercial requerida para uso propietario.
// Ver archivo LICENSE en la raíz del proyecto para términos completos.

const std = @import("std");
const types = @import("../core/types.zig");
const SolveOptions = types.SolveOptions;
const matrix = @import("../linalg/matrix.zig");
const snapping = @import("../symbolic/snapping.zig");
const qr = @import("../linalg/qr.zig");

/// Factor de complejidad. BIC clasico usa 1.0; 1.5 es mas conservador y
/// evita que terminos espurios de ruido entren en el soporte.
const bic_penalty: f64 = 1.5;

fn stlsqBicForSupport(
    temp_alloc: std.mem.Allocator,
    g_total: []const f64,
    z_total: []const f64,
    y2_total: f64,
    n_samples: usize,
    n_features: usize,
    ridge: f64,
    support: []const bool,
    active_indices: []usize,
    g_sub: []f64,
    z_sub: []f64,
    w_sub: []f64,
) !?f64 {
    var k: usize = 0;
    for (0..n_features) |f| {
        if (support[f]) {
            active_indices[k] = f;
            k += 1;
        }
    }
    if (k == 0) return null;

    for (0..k) |i| {
        const orig_i = active_indices[i];
        z_sub[i] = z_total[orig_i];
        for (0..k) |j| {
            g_sub[i * k + j] = g_total[orig_i * n_features + active_indices[j]];
        }
    }

    if (!try matrix.solveDenseSystem(temp_alloc, g_sub[0 .. k * k], z_sub[0..k], k, @max(ridge, 1e-10), w_sub[0..k])) {
        return null;
    }

    var w_gw: f64 = 0.0;
    var w_z: f64 = 0.0;
    for (0..k) |i| {
        w_z += w_sub[i] * z_sub[i];
        var row_sum: f64 = 0.0;
        for (0..k) |j| {
            row_sum += g_sub[i * k + j] * w_sub[j];
        }
        w_gw += w_sub[i] * row_sum;
    }

    const rss = @max(0.0, w_gw - 2.0 * w_z + y2_total);
    const n_f: f64 = @floatFromInt(@max(n_samples, 2));
    const k_f: f64 = @floatFromInt(k);
    return n_f * @log(rss / n_f + 1e-24) + bic_penalty * k_f * @log(n_f);
}

fn stlsqStepwise(
    temp_alloc: std.mem.Allocator,
    g_total: []const f64,
    z_total: []const f64,
    y2_total: f64,
    n_samples: usize,
    n_features: usize,
    bias_idx: usize,
    has_bias: bool,
    ridge: f64,
    support: []bool,
    active_indices: []usize,
    g_sub: []f64,
    z_sub: []f64,
    w_sub: []f64,
) !f64 {
    var current = (try stlsqBicForSupport(
        temp_alloc,
        g_total,
        z_total,
        y2_total,
        n_samples,
        n_features,
        ridge,
        support,
        active_indices,
        g_sub,
        z_sub,
        w_sub,
    )) orelse std.math.inf(f64);

    var guard: usize = 0;
    while (guard < 4 * n_features + 8) : (guard += 1) {
        var best_bic = current;
        var best_move: i8 = 0;
        var best_idx: usize = 0;

        // Intentar quitar cada termino no-bias.
        for (0..n_features) |f| {
            if (!support[f]) continue;
            if (has_bias and f == bias_idx) continue;
            support[f] = false;
            const bic = try stlsqBicForSupport(
                temp_alloc,
                g_total,
                z_total,
                y2_total,
                n_samples,
                n_features,
                ridge,
                support,
                active_indices,
                g_sub,
                z_sub,
                w_sub,
            );
            support[f] = true;
            if (bic) |b| {
                if (b + 1e-9 < best_bic) {
                    best_bic = b;
                    best_move = -1;
                    best_idx = f;
                }
            }
        }

        // Intentar agregar cada termino inactivo.
        for (0..n_features) |f| {
            if (support[f]) continue;
            support[f] = true;
            const bic = try stlsqBicForSupport(
                temp_alloc,
                g_total,
                z_total,
                y2_total,
                n_samples,
                n_features,
                ridge,
                support,
                active_indices,
                g_sub,
                z_sub,
                w_sub,
            );
            support[f] = false;
            if (bic) |b| {
                if (b + 1e-9 < best_bic) {
                    best_bic = b;
                    best_move = 1;
                    best_idx = f;
                }
            }
        }

        if (best_move == 0) break;
        support[best_idx] = best_move > 0;
        current = best_bic;
    }
    return current;
}

/// Solucionador analítico principal de regresión simbólica v2 Optimizado:
/// Integra filtrado robusto MAD, IRLS opcional con Huber loss,
/// separación Train/Val sobre matrices Gram (un solo pase unificado),
/// búsqueda de umbral óptimo basada en el criterio de información de Akaike (AIC),
/// re-estimación insesgada sobre el soporte activo y snapping físico.
pub fn solveAnalyticalStlsq(
    allocator: std.mem.Allocator,
    h_matrix: []const f64,
    y_vector: []const f64,
    n_samples: usize,
    n_features: usize,
    bias_idx: usize,
    options: SolveOptions,
) ![]f64 {
    if (n_features == 0) return try allocator.alloc(f64, 0);
    const has_bias = bias_idx < n_features;

    const weights_out = try allocator.alloc(f64, n_features);
    @memset(weights_out, 0.0);

    if (n_samples == 0) return weights_out;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();

    // 1. Filtrado robusto de outliers basado en MAD (Median Absolute Deviation)
    const sample_weights = try temp_alloc.alloc(f64, n_samples);
    const y_sorted = try temp_alloc.alloc(f64, n_samples);
    @memcpy(y_sorted, y_vector);
    std.mem.sort(f64, y_sorted, {}, std.sort.asc(f64));
    const median_y = y_sorted[n_samples / 2];

    const abs_diffs = try temp_alloc.alloc(f64, n_samples);
    for (y_vector, 0..) |y, s| abs_diffs[s] = @abs(y - median_y);
    std.mem.sort(f64, abs_diffs, {}, std.sort.asc(f64));
    const mad_dev = @max(abs_diffs[n_samples / 2], 1e-15);
    const bound = 4.5 * mad_dev;

    for (0..n_samples) |s| {
        sample_weights[s] = if (@abs(y_vector[s] - median_y) > bound) 0.0 else 1.0;
    }

    // 1b. IRLS opcional: re-ponderar muestras con pérdida de Huber para robustez adicional
    if (options.max_irls_iters > 0) {
        const irls_weights = try temp_alloc.alloc(f64, n_features);
        @memset(irls_weights, 0.0);
        const residuals = try temp_alloc.alloc(f64, n_samples);
        // Huber <= 0 producia pesos negativos -> sqrt(negativo)=NaN en el QR.
        const huber_c = if (std.math.isFinite(options.huber_tuning) and options.huber_tuning > 0.0)
            options.huber_tuning
        else
            1.345;

        for (0..options.max_irls_iters) |_| {
            const solved = try qr.solveWeightedQrPreconditioned(
                temp_alloc,
                h_matrix,
                y_vector,
                sample_weights,
                n_samples,
                n_features,
                irls_weights,
            );
            if (!solved) break;

            var res_sum: f64 = 0.0;
            var active_count: f64 = 0.0;

            for (0..n_samples) |s| {
                if (sample_weights[s] == 0.0) {
                    residuals[s] = 0.0;
                    continue;
                }
                var pred: f64 = 0.0;
                const offset = s * n_features;
                for (0..n_features) |f| {
                    pred += h_matrix[offset + f] * irls_weights[f];
                }
                const r = @abs(y_vector[s] - pred);
                residuals[s] = r;
                res_sum += r;
                active_count += 1.0;
            }

            const mean_res = res_sum / @max(active_count, 1.0);
            var dev_sum: f64 = 0.0;
            for (0..n_samples) |s| {
                if (sample_weights[s] == 0.0) continue;
                dev_sum += @abs(residuals[s] - mean_res);
            }
            const scale = @max(dev_sum / @max(active_count, 1.0), 1e-6);

            for (0..n_samples) |s| {
                if (@abs(y_vector[s] - median_y) > bound) continue;
                const r_norm = residuals[s] / scale;
                if (r_norm <= huber_c) {
                    sample_weights[s] = 1.0;
                } else {
                    sample_weights[s] = huber_c / r_norm;
                }
            }
        }
    }

    // 2. Cálculo de normas de columnas de H y normalización unitaria
    const col_norms = try temp_alloc.alloc(f64, n_features);
    for (0..n_features) |f| {
        var sumsq: f64 = 0.0;
        for (0..n_samples) |s| {
            if (sample_weights[s] > 0.0) {
                const val = h_matrix[s * n_features + f];
                sumsq += val * val * sample_weights[s];
            }
        }
        col_norms[f] = @sqrt(@max(sumsq, 1e-25));
    }

    const h_norm = try temp_alloc.alloc(f64, n_samples * n_features);
    for (0..n_samples) |s| {
        for (0..n_features) |f| {
            h_norm[s * n_features + f] = h_matrix[s * n_features + f] / col_norms[f];
        }
    }

    // 3. Construcción UNIFICADA de Matrices de Correlación Gram y Vectores Cruzados
    //    Un solo pase por los datos acumula train, val y total simultáneamente
    const g_train = try temp_alloc.alloc(f64, n_features * n_features);
    @memset(g_train, 0.0);
    const z_train = try temp_alloc.alloc(f64, n_features);
    @memset(z_train, 0.0);

    const g_val = try temp_alloc.alloc(f64, n_features * n_features);
    @memset(g_val, 0.0);
    const z_val = try temp_alloc.alloc(f64, n_features);
    @memset(z_val, 0.0);
    var y2_val: f64 = 0.0;
    var n_val: usize = 0;
    var y2_total: f64 = 0.0;

    const g_total = try temp_alloc.alloc(f64, n_features * n_features);
    @memset(g_total, 0.0);
    const z_total = try temp_alloc.alloc(f64, n_features);
    @memset(z_total, 0.0);

    // Pre-computar fila normalizada ponderada para reutilización
    const row_buf = try temp_alloc.alloc(f64, n_features);

    for (0..n_samples) |s| {
        const w_s = sample_weights[s];
        if (w_s == 0.0) continue;
        const y = y_vector[s];
        const is_val = (n_samples >= 10 and (s % 5 == 0));
        const sw = @sqrt(w_s);

        // Pre-computar fila ponderada una sola vez
        for (0..n_features) |f| {
            row_buf[f] = h_norm[s * n_features + f] * sw;
        }

        const y_w = y * sw;
        y2_total += y_w * y_w;

        // Acumular en las tres matrices con una sola lectura de row_buf
        for (0..n_features) |i| {
            const ri = row_buf[i];

            // Total siempre
            z_total[i] += ri * y_w;
            for (0..n_features) |j| {
                g_total[i * n_features + j] += ri * row_buf[j];
            }

            if (is_val) {
                z_val[i] += ri * y_w;
                for (0..n_features) |j| {
                    g_val[i * n_features + j] += ri * row_buf[j];
                }
            } else {
                z_train[i] += ri * y_w;
                for (0..n_features) |j| {
                    g_train[i * n_features + j] += ri * row_buf[j];
                }
            }
        }

        if (is_val) {
            y2_val += y_w * y_w;
            n_val += 1;
        }
    }

    if (n_samples < 10) {
        @memcpy(g_train, g_total);
        @memcpy(z_train, z_total);
        @memcpy(g_val, g_total);
        @memcpy(z_val, z_total);
        n_val = 0;
        for (0..n_samples) |s| {
            const w_s = sample_weights[s];
            if (w_s > 0.0) {
                y2_val += y_vector[s] * y_vector[s] * w_s;
                n_val += 1;
            }
        }
    }

    // 4. Búsqueda exhaustiva del umbral óptimo mediante AIC (Criterio de Parsimonia)
    const candidate_thresholds = [_]f64{
        0.0001, 0.0005, 0.001, 0.002, 0.005, 0.008, 0.01, 0.015,
        0.02,   0.03,   0.04,  0.05,  0.07,  0.1,   0.15, 0.2,
        0.3,    0.4,    0.5,   0.75,  1.0,
    };

    const user_thresh = options.parsimony_threshold;
    var threshold_list: [candidate_thresholds.len]f64 = undefined;
    var n_thresholds: usize = 0;
    for (candidate_thresholds) |thr_raw| {
        // El umbral del usuario es el minimo permitido; nunca lo ignoramos.
        const thr = if (user_thresh > 0.0 and thr_raw < user_thresh) user_thresh else thr_raw;
        if (n_thresholds == 0 or @abs(threshold_list[n_thresholds - 1] - thr) > 1e-12) {
            threshold_list[n_thresholds] = thr;
            n_thresholds += 1;
        }
    }

    const best_support = try temp_alloc.alloc(bool, n_features);
    @memset(best_support, true);
    var best_score: f64 = std.math.inf(f64);

    const active = try temp_alloc.alloc(bool, n_features);
    const w_temp = try temp_alloc.alloc(f64, n_features);
    const active_indices_buf = try temp_alloc.alloc(usize, n_features);

    for (threshold_list[0..n_thresholds]) |thr| {
        @memset(active, true);

        for (0..@max(options.max_stlsq_iters, 1)) |_| {
            var k: usize = 0;
            for (0..n_features) |f| {
                if (active[f]) {
                    active_indices_buf[k] = f;
                    k += 1;
                }
            }
            if (k == 0) break;

            const active_indices = active_indices_buf[0..k];
            const g_sub = try temp_alloc.alloc(f64, k * k);
            const z_sub = try temp_alloc.alloc(f64, k);

            for (0..k) |i| {
                const orig_i = active_indices[i];
                z_sub[i] = z_train[orig_i];
                for (0..k) |j| {
                    g_sub[i * k + j] = g_train[orig_i * n_features + active_indices[j]];
                }
            }

            const w_sub = try temp_alloc.alloc(f64, k);
            const ok = try matrix.solveDenseSystem(temp_alloc, g_sub, z_sub, k, @max(options.ridge, 1e-8), w_sub);

            if (ok) {
                var max_w: f64 = 0.0;
                for (active_indices, 0..) |orig_f, idx| {
                    // El bias no participa en la escala: si no, un offset grande
                    // (p. ej. 1e6) hace que todos los demas terminos se poden.
                    if (has_bias and orig_f == bias_idx) continue;
                    const nw = @abs(w_sub[idx]);
                    if (nw > max_w) max_w = nw;
                }
                const cutoff = max_w * thr;
                var changed = false;

                for (active_indices, 0..) |orig_f, idx| {
                    if (has_bias and orig_f == bias_idx) continue;
                    if (@abs(w_sub[idx]) < cutoff) {
                        active[orig_f] = false;
                        changed = true;
                    }
                }
                if (!changed) break;
            } else {
                break;
            }
        }

        var k_final: usize = 0;
        for (0..n_features) |f| {
            if (active[f]) {
                active_indices_buf[k_final] = f;
                k_final += 1;
            }
        }

        @memset(w_temp, 0.0);

        if (k_final > 0) {
            const active_indices = active_indices_buf[0..k_final];
            const g_sub = try temp_alloc.alloc(f64, k_final * k_final);
            const z_sub = try temp_alloc.alloc(f64, k_final);

            for (0..k_final) |i| {
                const orig_i = active_indices[i];
                z_sub[i] = z_total[orig_i];
                for (0..k_final) |j| {
                    g_sub[i * k_final + j] = g_total[orig_i * n_features + active_indices[j]];
                }
            }

            const w_sub = try temp_alloc.alloc(f64, k_final);
            if (try matrix.solveDenseSystem(temp_alloc, g_sub, z_sub, k_final, @max(options.ridge, 1e-10), w_sub)) {
                for (active_indices, 0..) |orig_f, idx| {
                    w_temp[orig_f] = w_sub[idx];
                }
            }
        }

        // Evaluación de bondad de ajuste en conjunto de Validación
        var w_gw: f64 = 0.0;
        var w_z: f64 = 0.0;
        for (0..n_features) |i| {
            w_z += w_temp[i] * z_total[i];
            var row_sum: f64 = 0.0;
            for (0..n_features) |j| {
                row_sum += g_total[i * n_features + j] * w_temp[j];
            }
            w_gw += w_temp[i] * row_sum;
        }

        const total_rss = @max(0.0, w_gw - 2.0 * w_z + y2_total);
        const n_eval: usize = @max(n_samples, 2);
        const n_eval_f: f64 = @floatFromInt(n_eval);
        const mse = total_rss / n_eval_f;
        const k_f: f64 = @floatFromInt(k_final);
        // BIC: penaliza complejidad con log(n). Es mas conservador que el
        // score anterior y evita que terminos espurios de ruido sobrevivan.
        const score = n_eval_f * @log(mse + 1e-24) + bic_penalty * k_f * @log(n_eval_f);

        if (score < best_score) {
            best_score = score;
            @memcpy(best_support, active);
        }
    }

    // 5. Re-estimación de coeficientes insesgados sobre G_total con el soporte óptimo descubierto
    // 4b. Refinamiento global por BIC. STLSQ puede quedar atrapado en un
    // soporte local; para bibliotecas pequenas probamos todos los subconjuntos
    // y para las grandes hacemos seleccion stepwise (forward/backward).
    const g_support = try temp_alloc.alloc(f64, n_features * n_features);
    const z_support = try temp_alloc.alloc(f64, n_features);
    const w_support = try temp_alloc.alloc(f64, n_features);

    if (n_features <= 14) {
        var optional: [14]usize = undefined;
        var optional_count: usize = 0;
        for (0..n_features) |f| {
            if (has_bias and f == bias_idx) continue;
            optional[optional_count] = f;
            optional_count += 1;
        }
        const total: u64 = @as(u64, 1) << @intCast(optional_count);
        var mask: u64 = 0;
        while (mask < total) : (mask += 1) {
            @memset(active, false);
            if (has_bias) active[bias_idx] = true;
            for (0..optional_count) |j| {
                if (((mask >> @intCast(j)) & 1) != 0) active[optional[j]] = true;
            }
            const bic = try stlsqBicForSupport(
                temp_alloc,
                g_total,
                z_total,
                y2_total,
                n_samples,
                n_features,
                options.ridge,
                active,
                active_indices_buf,
                g_support,
                z_support,
                w_support,
            );
            if (bic) |b| {
                if (b < best_score) {
                    best_score = b;
                    @memcpy(best_support, active);
                }
            }
        }
    } else {
        // Empezar desde el mejor soporte de STLSQ.
        @memcpy(active, best_support);
        const s1 = try stlsqStepwise(
            temp_alloc,
            g_total,
            z_total,
            y2_total,
            n_samples,
            n_features,
            bias_idx,
            has_bias,
            options.ridge,
            active,
            active_indices_buf,
            g_support,
            z_support,
            w_support,
        );
        if (s1 < best_score) {
            best_score = s1;
            @memcpy(best_support, active);
        }

        // Empezar desde el modelo solo-bias.
        @memset(active, false);
        if (has_bias) active[bias_idx] = true;
        const s2 = try stlsqStepwise(
            temp_alloc,
            g_total,
            z_total,
            y2_total,
            n_samples,
            n_features,
            bias_idx,
            has_bias,
            options.ridge,
            active,
            active_indices_buf,
            g_support,
            z_support,
            w_support,
        );
        if (s2 < best_score) {
            best_score = s2;
            @memcpy(best_support, active);
        }
    }

    // El bias (intercepto) es estructural: nunca debe podarse.
    if (has_bias) best_support[bias_idx] = true;
    var k_best: usize = 0;
    for (0..n_features) |f| {
        if (best_support[f]) {
            active_indices_buf[k_best] = f;
            k_best += 1;
        }
    }

    @memset(weights_out, 0.0);

    if (k_best > 0) {
        const active_indices = active_indices_buf[0..k_best];
        const g_sub = try temp_alloc.alloc(f64, k_best * k_best);
        const z_sub = try temp_alloc.alloc(f64, k_best);

        for (0..k_best) |i| {
            const orig_i = active_indices[i];
            z_sub[i] = z_total[orig_i];
            for (0..k_best) |j| {
                g_sub[i * k_best + j] = g_total[orig_i * n_features + active_indices[j]];
            }
        }

        const w_sub = try temp_alloc.alloc(f64, k_best);
        if (try matrix.solveDenseSystem(temp_alloc, g_sub, z_sub, k_best, @max(options.ridge, 1e-12), w_sub)) {
            for (active_indices, 0..) |orig_f, idx| {
                weights_out[orig_f] = w_sub[idx] / col_norms[orig_f];
            }
        }
    }

    // 6. Post-Pruning Noise Gate con re-estimación de soporte
    if (options.noise_gate_l2 and user_thresh > 0.0) {
        var max_w: f64 = 0.0;
        for (0..n_features) |f| {
            if (has_bias and f == bias_idx) continue;
            const c = @abs(weights_out[f] * col_norms[f]);
            if (c > max_w) max_w = c;
        }
        const hard_cutoff = max_w * user_thresh;
        var pruned_any = false;

        for (0..n_features) |f| {
            if (has_bias and f == bias_idx) continue;
            const c = @abs(weights_out[f] * col_norms[f]);
            if (c < hard_cutoff and weights_out[f] != 0.0) {
                weights_out[f] = 0.0;
                best_support[f] = false;
                pruned_any = true;
            }
        }

        if (pruned_any) {
            var k_surv: usize = 0;
            for (0..n_features) |f| {
                if (best_support[f]) {
                    active_indices_buf[k_surv] = f;
                    k_surv += 1;
                }
            }

            if (k_surv > 0) {
                const active_indices = active_indices_buf[0..k_surv];
                const g_sub = try temp_alloc.alloc(f64, k_surv * k_surv);
                const z_sub = try temp_alloc.alloc(f64, k_surv);

                for (0..k_surv) |i| {
                    const orig_i = active_indices[i];
                    z_sub[i] = z_total[orig_i];
                    for (0..k_surv) |j| {
                        g_sub[i * k_surv + j] = g_total[orig_i * n_features + active_indices[j]];
                    }
                }

                const w_sub = try temp_alloc.alloc(f64, k_surv);
                if (try matrix.solveDenseSystem(temp_alloc, g_sub, z_sub, k_surv, @max(options.ridge, 1e-12), w_sub)) {
                    @memset(weights_out, 0.0);
                    for (active_indices, 0..) |orig_f, idx| {
                        weights_out[orig_f] = w_sub[idx] / col_norms[orig_f];
                    }
                }
            }
        }
    }

    // 7. Snapping a constantes físicas y fracciones exactas
    if (options.snap_constants) {
        for (weights_out) |*w| {
            if (@abs(w.*) > 1e-25) {
                w.* = snapping.snapToPhysicalConstantScaleInvariant(w.*);
            } else {
                w.* = 0.0;
            }
        }
    }

    return weights_out;
}
