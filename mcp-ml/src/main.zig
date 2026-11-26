const std = @import("std");
const Io = std.Io;
const proto = @import("protocol.zig");
const ayuda = @import("ayuda.zig");
const registro = @import("registro.zig");
const ermc = @import("ermc");

const chaos = ermc.solver.chaos;

fn lorenzOde(t: f64, state: []const f64, dstate: []f64, ctx: ?*const anyopaque) void {
    _ = t;
    _ = ctx;
    const sigma: f64 = 10.0;
    const rho: f64 = 28.0;
    const beta: f64 = 8.0 / 3.0;
    const x = state[0];
    const y = state[1];
    const z = state[2];
    dstate[0] = sigma * (y - x);
    dstate[1] = x * (rho - z) - y;
    dstate[2] = x * y - beta * z;
}

// Manifiesto de `--registro`: fuente unica en `registro.zig` (ver DEVELOPER.md §3).
const MANIFIESTO = registro.MANIFIESTO;

const FLAGS = [_][]const u8{
    "--help",       "--help-topic",      "--version",         "--chaos",        "-c",
    "--sindy",      "--sindy-dynamical", "--sindy-load",      "--svd",          "--sequence",
    "--save",       "--irls",            "--stlsq-iters",     "--huber",        "--noise-gate",
    "--snap",       "--ridge-sindy",     "--activations",     "--interactions", "--window-half",
    "--model-load", "--pinv",            "--koopman",         "--pdefind",      "--koopman-load",
    "--x0",         "--dx",              "--koopman-predict", "--steps",        "--basis",
    "--ridge",      "--dmd",             "--dt",              "--rank",         "--values",
    "--data",       "--threshold",       "--vars",
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1 and std.mem.eql(u8, args[1], "--registro")) {
        var rbuf: [1024]u8 = undefined;
        var rw: Io.File.Writer = .initStreaming(.stdout(), io, &rbuf);
        try rw.interface.writeAll(MANIFIESTO);
        try rw.interface.writeAll("\n");
        try rw.interface.flush();
        return;
    }
    if (args.len > 1) {
        var out_buf: [4096]u8 = undefined;
        var out_w: Io.File.Writer = .initStreaming(.stdout(), io, &out_buf);
        var out: *Io.Writer = &out_w.interface;
        var err_buf: [512]u8 = undefined;
        var err_w: Io.File.Writer = .initStreaming(.stderr(), io, &err_buf);
        var err: *Io.Writer = &err_w.interface;

        var do_chaos = false;
        var do_help = false;
        var help_topic: ?[]const u8 = null;
        var do_sindy = false;
        var do_sindy_dyn = false;
        var do_sindy_load = false;
        var do_svd = false;
        var do_sequence = false;
        var do_dmd = false;
        var do_model_load = false;
        var do_pinv = false;
        var do_koopman = false;
        var do_koopman_predict = false;
        var do_pdefind = false;
        var do_koopman_load_predict = false;
        var x0_str: []const u8 = "";
        var values_str: []const u8 = "";
        var basis_str: []const u8 = "poly2";
        var steps_val: usize = 5;
        var ridge_val: f64 = 1e-7;
        var ridge_sindy: f64 = 0.0;
        var acts_cli: []const u8 = "";
        var window_half_cli: usize = 15;
        var interactions_cli: bool = false;
        var irls_val: usize = 2;
        var stlsq_iters_val: usize = 8;
        var huber_val: f64 = 1.345;
        var noise_gate_val: bool = true;
        var snap_val: bool = true;
        var dt_val: f64 = 1.0;
        var dx_val: f64 = 1.0;
        var rank_val: usize = 10;
        var save_path: []const u8 = "";
        var model_path: []const u8 = "";
        var data_path: []const u8 = "";
        var threshold: f64 = 0.015;
        var vars: usize = 0;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const a = args[i];
            if (std.mem.eql(u8, a, "--chaos") or std.mem.eql(u8, a, "-c")) do_chaos = true else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "help")) {
                if (i + 1 < args.len and args[i + 1].len > 0 and args[i + 1][0] != '-') {
                    if (ayuda.topicMd(args[i + 1]) != null) {
                        help_topic = args[i + 1];
                        i += 1;
                        continue;
                    }
                }
                do_help = true;
            } else if (std.mem.eql(u8, a, "--version") or std.mem.eql(u8, a, "-V")) {
                try out.print("{s} {s}\n", .{ registro.NOMBRE, registro.VERSION });
                try out.flush();
                return;
            } else if (std.mem.eql(u8, a, "--help-topic")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --help-topic\n");
                    try err.flush();
                    std.process.exit(2);
                }
                help_topic = args[i];
            } else if (std.mem.eql(u8, a, "--sindy")) do_sindy = true else if (std.mem.eql(u8, a, "--sindy-dynamical")) do_sindy_dyn = true else if (std.mem.eql(u8, a, "--sindy-load")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --sindy-load\n");
                    try err.flush();
                    std.process.exit(2);
                }
                do_sindy_load = true;
                model_path = args[i];
            } else if (std.mem.eql(u8, a, "--window-half")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --window-half\n");
                    try err.flush();
                    std.process.exit(2);
                }
                window_half_cli = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                    try err.writeAll("Error: window-half invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--interactions")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --interactions\n");
                    try err.flush();
                    std.process.exit(2);
                }
                interactions_cli = std.mem.eql(u8, args[i], "true");
            } else if (std.mem.eql(u8, a, "--svd")) do_svd = true else if (std.mem.eql(u8, a, "--sequence")) do_sequence = true else if (std.mem.eql(u8, a, "--save")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --save\n");
                    try err.flush();
                    std.process.exit(2);
                }
                save_path = args[i];
            } else if (std.mem.eql(u8, a, "--irls")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --irls\n");
                    try err.flush();
                    std.process.exit(2);
                }
                irls_val = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                    try err.writeAll("Error: irls invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--stlsq-iters")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --stlsq-iters\n");
                    try err.flush();
                    std.process.exit(2);
                }
                stlsq_iters_val = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                    try err.writeAll("Error: stlsq_iters invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--huber")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --huber\n");
                    try err.flush();
                    std.process.exit(2);
                }
                huber_val = std.fmt.parseFloat(f64, args[i]) catch {
                    try err.writeAll("Error: huber invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--noise-gate")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --noise-gate\n");
                    try err.flush();
                    std.process.exit(2);
                }
                noise_gate_val = std.mem.eql(u8, args[i], "true");
            } else if (std.mem.eql(u8, a, "--snap")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --snap\n");
                    try err.flush();
                    std.process.exit(2);
                }
                snap_val = std.mem.eql(u8, args[i], "true");
            } else if (std.mem.eql(u8, a, "--ridge-sindy")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --ridge-sindy\n");
                    try err.flush();
                    std.process.exit(2);
                }
                ridge_sindy = std.fmt.parseFloat(f64, args[i]) catch {
                    try err.writeAll("Error: ridge invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--activations")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --activations\n");
                    try err.flush();
                    std.process.exit(2);
                }
                acts_cli = args[i];
            } else if (std.mem.eql(u8, a, "--model-load")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --model-load\n");
                    try err.flush();
                    std.process.exit(2);
                }
                do_model_load = true;
                model_path = args[i];
            } else if (std.mem.eql(u8, a, "--pinv")) do_pinv = true else if (std.mem.eql(u8, a, "--koopman")) do_koopman = true else if (std.mem.eql(u8, a, "--pdefind")) do_pdefind = true else if (std.mem.eql(u8, a, "--koopman-load")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --koopman-load\n");
                    try err.flush();
                    std.process.exit(2);
                }
                do_koopman_load_predict = true;
                model_path = args[i];
            } else if (std.mem.eql(u8, a, "--x0")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --x0\n");
                    try err.flush();
                    std.process.exit(2);
                }
                x0_str = args[i];
            } else if (std.mem.eql(u8, a, "--dx")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --dx\n");
                    try err.flush();
                    std.process.exit(2);
                }
                dx_val = std.fmt.parseFloat(f64, args[i]) catch {
                    try err.writeAll("Error: dx invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--koopman-predict")) do_koopman_predict = true else if (std.mem.eql(u8, a, "--steps")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --steps\n");
                    try err.flush();
                    std.process.exit(2);
                }
                steps_val = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                    try err.writeAll("Error: steps invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--basis")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --basis\n");
                    try err.flush();
                    std.process.exit(2);
                }
                basis_str = args[i];
            } else if (std.mem.eql(u8, a, "--ridge")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --ridge\n");
                    try err.flush();
                    std.process.exit(2);
                }
                ridge_val = std.fmt.parseFloat(f64, args[i]) catch {
                    try err.writeAll("Error: ridge invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--dmd")) do_dmd = true else if (std.mem.eql(u8, a, "--dt")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --dt\n");
                    try err.flush();
                    std.process.exit(2);
                }
                dt_val = std.fmt.parseFloat(f64, args[i]) catch {
                    try err.writeAll("Error: dt invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--rank")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --rank\n");
                    try err.flush();
                    std.process.exit(2);
                }
                rank_val = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                    try err.writeAll("Error: rank invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--values")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --values\n");
                    try err.flush();
                    std.process.exit(2);
                }
                values_str = args[i];
            } else if (std.mem.eql(u8, a, "--data")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --data\n");
                    try err.flush();
                    std.process.exit(2);
                }
                data_path = args[i];
            } else if (std.mem.eql(u8, a, "--threshold")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --threshold\n");
                    try err.flush();
                    std.process.exit(2);
                }
                threshold = std.fmt.parseFloat(f64, args[i]) catch {
                    try err.writeAll("Error: threshold invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--vars")) {
                i += 1;
                if (i >= args.len) {
                    try err.writeAll("Error: falta --vars\n");
                    try err.flush();
                    std.process.exit(2);
                }
                vars = std.fmt.parseUnsigned(usize, args[i], 10) catch {
                    try err.writeAll("Error: vars invalido\n");
                    try err.flush();
                    std.process.exit(2);
                };
            } else {
                try err.print("Error: argumento desconocido: {s}\n", .{a});
                if (ayuda.sugerir(a, FLAGS[0..])) |s| try err.print("¿Quisiste decir {s}?\n", .{s});
                try err.print("Usa `mcp-ml --help` para ver las opciones.\n", .{});
                try err.flush();
                std.process.exit(2);
            }
        }
        if (help_topic) |t| {
            const md = ayuda.topicMd(t) orelse {
                try err.print("Error: tema desconocido: {s} (temas: {s})\n", .{ t, ayuda.TOPICS });
                try err.flush();
                std.process.exit(2);
            };
            try out.writeAll(md);
            try out.writeAll("\n");
            try out.flush();
            return;
        }
        if (do_help) {
            try out.writeAll(ayuda.USAGE_CLI);
            try out.writeAll("\n");
            try out.flush();
            return;
        }
        if (do_chaos) {
            const txt = chaosCore(gpa) catch |e| {
                try err.print("Error: {s}\n", .{@errorName(e)});
                try err.flush();
                std.process.exit(2);
            };
            defer gpa.free(txt);
            try out.writeAll(txt);
            try out.writeAll("\n");
            try out.flush();
            return;
        }
        if (do_sindy) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --sindy requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runSindyCli(io, out, err, gpa, data_path, threshold, vars, save_path, irls_val, stlsq_iters_val, huber_val, noise_gate_val, snap_val, interactions_cli, ridge_sindy, acts_cli);
            return;
        }
        if (do_sindy_dyn) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --sindy-dynamical requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runSindyDynamicalCli(io, out, err, gpa, data_path, threshold, window_half_cli, vars, save_path, irls_val, stlsq_iters_val, huber_val, noise_gate_val, snap_val, interactions_cli, ridge_sindy, acts_cli);
            return;
        }
        if (do_sindy_load) {
            if (model_path.len == 0 or (data_path.len == 0 and x0_str.len == 0)) {
                try err.writeAll("Error: --sindy-load requiere PATH y --data ENTRADAS.csv o --x0 \"a,b,...\".\n");
                try err.flush();
                std.process.exit(2);
            }
            try runSindyLoadPredictCli(io, out, err, gpa, model_path, data_path, x0_str);
            return;
        }
        if (do_svd) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --svd requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runSvdCli(io, out, err, gpa, data_path);
            return;
        }
        if (do_sequence) {
            if (values_str.len == 0) {
                try err.writeAll("Error: --sequence requiere --values \"a,b,c\".\n");
                try err.flush();
                std.process.exit(2);
            }
            try runSequenceCli(io, out, err, gpa, values_str);
            return;
        }
        if (do_dmd) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --dmd requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runDmdCli(io, out, err, gpa, data_path, dt_val, rank_val);
            return;
        }
        if (do_model_load) {
            if (model_path.len == 0) {
                try err.writeAll("Error: --model-load requiere PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runModelLoadCli(io, out, err, gpa, model_path);
            return;
        }
        if (do_pinv) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --pinv requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runPinvCli(io, out, err, gpa, data_path);
            return;
        }
        if (do_koopman) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --koopman requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runKoopmanCli(io, out, err, gpa, data_path, basis_str, save_path, ridge_val);
            return;
        }
        if (do_koopman_predict) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --koopman-predict requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runKoopmanPredictCli(io, out, err, gpa, data_path, steps_val, basis_str, ridge_val);
            return;
        }
        if (do_pdefind) {
            if (data_path.len == 0) {
                try err.writeAll("Error: --pdefind requiere --data PATH.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runPdefindCli(io, out, err, gpa, data_path, dt_val, dx_val);
            return;
        }
        if (do_koopman_load_predict) {
            if (model_path.len == 0 or x0_str.len == 0) {
                try err.writeAll("Error: --koopman-load requiere PATH y --x0.\n");
                try err.flush();
                std.process.exit(2);
            }
            try runKoopmanLoadPredictCli(io, out, err, gpa, model_path, x0_str, steps_val);
            return;
        }
        try err.writeAll("Error: falta --chaos, --sindy, --sindy-dynamical, --sindy-load, --svd, --sequence, --dmd, --pinv, --koopman, --koopman-predict, --pdefind, --koopman-load, --model-load o --help.\n");
        try err.flush();
        std.process.exit(2);
    }

    // MCP stdio
    var stdin_buf: [65536]u8 = undefined;
    var stdin_reader: Io.File.Reader = .initStreaming(.stdin(), io, &stdin_buf);
    const in: *Io.Reader = &stdin_reader.interface;
    var stdout_buf: [65536]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buf);
    var out: *Io.Writer = &stdout_writer.interface;

    var msg: std.ArrayList(u8) = .empty;
    defer msg.deinit(gpa);
    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(gpa);
    while (true) {
        const got = readLine(in, gpa, &line_buf) catch break;
        if (!got) {
            if (msg.items.len > 0) {
                const t = std.mem.trim(u8, msg.items, " \t\r\n");
                if (t.len > 0) try dispatch(t, io, out, gpa);
            }
            break;
        }
        var l = line_buf.items;
        if (l.len > 0 and l[l.len - 1] == '\r') l = l[0 .. l.len - 1];
        if (l.len == 0 and msg.items.len == 0) continue;
        // Cap de seguridad: un mensaje sin cerrar no debe crecer sin limite.
        if (msg.items.len + l.len > 8 * 1024 * 1024) {
            msg.clearRetainingCapacity();
            try proto.sendJsonError(out, null, -32700, "Parse error");
            out.flush() catch {};
            continue;
        }
        try msg.appendSlice(gpa, l);
        try msg.append(gpa, '\n');
        const trimmed = std.mem.trim(u8, msg.items, " \t\r\n");
        if (trimmed.len == 0) {
            msg.clearRetainingCapacity();
            continue;
        }
        if (!proto.bracesBalanced(trimmed)) {
            const solo = std.mem.trim(u8, l, " \t");
            if (solo.len > 0 and proto.parsesAsObject(solo, gpa)) {
                msg.clearRetainingCapacity();
                try dispatch(solo, io, out, gpa);
            }
            continue;
        }
        try dispatch(trimmed, io, out, gpa);
        msg.clearRetainingCapacity();
    }
    out.flush() catch {};
}

/// Lee una linea completa (sin '\n') en `out`, sin limite de tamano: soporta
/// mensajes MCP mayores que el buffer fijo del reader. Devuelve false en EOF.
fn readLine(in: *Io.Reader, gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !bool {
    out.clearRetainingCapacity();
    var aw: std.Io.Writer.Allocating = .fromArrayList(gpa, out);
    defer out.* = aw.toArrayList();
    const n = in.streamDelimiterEnding(&aw.writer, '\n') catch |err| switch (err) {
        error.ReadFailed => return error.ReadFailed,
        error.WriteFailed => return error.OutOfMemory,
    };
    const buffered = in.buffered();
    if (buffered.len > 0 and buffered[0] == '\n') {
        in.toss(1);
        return true;
    }
    return n > 0;
}

fn dispatch(raw: []const u8, io: Io, out: *Io.Writer, gpa: std.mem.Allocator) !void {
    // Flush por respuesta: el pool persistente lee linea a linea sin EOF.
    defer out.flush() catch {};
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch {
        try proto.sendJsonError(out, null, -32700, "Parse error");
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        try proto.sendJsonError(out, null, -32700, "Parse error");
        return;
    }
    const obj = parsed.value.object;
    const m = obj.get("method") orelse return;
    if (m != .string) return;
    const method = m.string;
    const id_opt = obj.get("id");
    if (method.len >= 14 and std.mem.eql(u8, method[0..@min(method.len, 14)], "notifications/")) return;
    if (std.mem.eql(u8, method, "initialize")) {
        // Contrato DEVELOPER.md §2: hacer eco de params.protocolVersion.
        var pv: []const u8 = "2024-11-05";
        if (obj.get("params")) |params| {
            if (params == .object) {
                if (params.object.get("protocolVersion")) |v| {
                    if (v == .string and v.string.len > 0 and v.string.len <= 64) {
                        var valid = true;
                        for (v.string) |ch| {
                            if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-' or ch == '_')) valid = false;
                        }
                        if (valid) pv = v.string;
                    }
                }
            }
        }
        const res = try std.fmt.allocPrint(gpa, "{{\"protocolVersion\":\"{s}\",\"capabilities\":{{\"tools\":{{}}}},\"serverInfo\":{{\"name\":\"" ++ registro.SERVIDOR ++ "\",\"version\":\"" ++ registro.VERSION ++ "\"}}}}", .{pv});
        defer gpa.free(res);
        try proto.sendResult(out, id_opt, res);
        return;
    }
    if (std.mem.eql(u8, method, "ping")) {
        try proto.sendResult(out, id_opt, "{}");
        return;
    }
    if (std.mem.eql(u8, method, "tools/list")) {
        try sendToolsList(out, id_opt);
        return;
    }
    if (std.mem.eql(u8, method, "tools/call")) {
        const id = id_opt orelse return;
        const params = obj.get("params");
        var tool_name: []const u8 = "";
        var args: ?std.json.Value = null;
        if (params != null and params.? == .object) {
            const p = params.?.object;
            if (p.get("name")) |n| if (n == .string) {
                tool_name = n.string;
            };
            if (p.get("arguments")) |a| if (a == .object) {
                args = a;
            };
        }
        if (std.mem.eql(u8, tool_name, "chaos_lorenz")) {
            try runChaos(io, out, id, gpa);
            return;
        }
        if (std.mem.eql(u8, tool_name, "sindy")) {
            try runSindy(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "sindy_dynamical")) {
            try runSindyDynamical(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "sindy_load_predict")) {
            try runSindyLoadPredict(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "svd")) {
            try runSvd(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "sequence")) {
            try runSequence(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "dmd")) {
            try runDmd(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "pinv")) {
            try runPinv(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "koopman")) {
            try runKoopman(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "koopman_predict")) {
            try runKoopmanPredict(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "pdefind")) {
            try runPdefind(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "koopman_load_predict")) {
            try runKoopmanLoadPredict(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "model_load")) {
            try runModelLoad(io, out, id, gpa, args);
            return;
        }
        if (std.mem.eql(u8, tool_name, "ml_help")) {
            const topic = proto.argStr(args, "topic", "all");
            const md = ayuda.topicMd(topic) orelse {
                try proto.sendToolError(out, id, "Invalid params: topic desconocido (all|ops|ejemplos|<tool>).");
                return;
            };
            try proto.sendToolText(out, id, md);
            return;
        }
        try proto.sendToolError(out, id, "Herramienta desconocida.");
        return;
    }
    if (id_opt == null) return;
    try proto.sendJsonError(out, id_opt, -32601, "Method not found");
}

fn sendToolsList(out: *Io.Writer, id: ?std.json.Value) !void {
    if (id == null) return;
    try out.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try proto.writeId(out, id);
    try out.writeAll(",\"result\":{\"tools\":[");
    // Nombres y schemas: fuente unica en `registro.zig`.
    for (registro.HERRAMIENTAS, 0..) |h, i| {
        if (i > 0) try out.writeAll(",");
        try out.writeAll(h.json);
    }
    try out.writeAll("]}}\n");
    try out.flush();
}

fn chaosCore(gpa: std.mem.Allocator) ![]u8 {
    const init_state = [_]f64{ 10.0, 10.0, 25.0 };
    // 1000 iteraciones (~50 s de tiempo simulado) convergen al valor asintótico
    // lambda ~= 0.906 del atractor de Lorenz; con 300 se obtenía ~0.56.
    const res = try chaos.computeMaxLyapunovExponent(gpa, lorenzOde, &init_state, 1e-8, 0.05, 1000, 0.005);
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"lambda\":");
    try appendNum(&buf, gpa, res.lyapunov_exponent);
    try buf.appendSlice(gpa, ",\"lyapunov_time\":");
    try appendNum(&buf, gpa, res.lyapunov_time);
    try buf.append(gpa, '}');
    return buf.toOwnedSlice(gpa);
}

fn runChaos(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator) !void {
    _ = io;
    const txt = chaosCore(gpa) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}

/// Serializa un f64 como numero JSON valido: NaN/Inf no existen en JSON,
/// se emiten como `null`. Usa buffer amplio y cae a allocPrint si no alcanza
/// (p. ej. 1e308 ocupa ~309 digitos con `{d}`).
fn appendNum(buf: *std.ArrayList(u8), gpa: std.mem.Allocator, v: f64) !void {
    if (!std.math.isFinite(v)) {
        try buf.appendSlice(gpa, "null");
        return;
    }
    var t: [512]u8 = undefined;
    if (std.fmt.bufPrint(&t, "{d}", .{v})) |s| {
        try buf.appendSlice(gpa, s);
    } else |_| {
        const s = try std.fmt.allocPrint(gpa, "{d}", .{v});
        defer gpa.free(s);
        try buf.appendSlice(gpa, s);
    }
}

fn appendUint(buf: *std.ArrayList(u8), gpa: std.mem.Allocator, v: usize) !void {
    var t: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&t, "{d}", .{v});
    try buf.appendSlice(gpa, s);
}

fn escapeJson(s: []const u8, buf: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        switch (c) {
            '"' => {
                try buf.appendSlice(gpa, "\\\"");
                i += 1;
            },
            '\\' => {
                try buf.appendSlice(gpa, "\\\\");
                i += 1;
            },
            '\n' => {
                try buf.appendSlice(gpa, "\\n");
                i += 1;
            },
            '\r' => {
                try buf.appendSlice(gpa, "\\r");
                i += 1;
            },
            '\t' => {
                try buf.appendSlice(gpa, "\\t");
                i += 1;
            },
            0x08 => {
                try buf.appendSlice(gpa, "\\b");
                i += 1;
            },
            0x0c => {
                try buf.appendSlice(gpa, "\\f");
                i += 1;
            },
            else => {
                if (c < 0x20) {
                    var t: [8]u8 = undefined;
                    const e = try std.fmt.bufPrint(&t, "\\u{x:0>4}", .{c});
                    try buf.appendSlice(gpa, e);
                    i += 1;
                } else if (c < 0x80) {
                    try buf.append(gpa, c);
                    i += 1;
                } else {
                    const seq_len = std.unicode.utf8ByteSequenceLength(c) catch {
                        try buf.appendSlice(gpa, "\\ufffd");
                        i += 1;
                        continue;
                    };
                    const n: usize = seq_len;
                    if (i + n > s.len or !std.unicode.utf8ValidateSlice(s[i .. i + n])) {
                        try buf.appendSlice(gpa, "\\ufffd");
                        i += 1;
                    } else {
                        try buf.appendSlice(gpa, s[i .. i + n]);
                        i += n;
                    }
                }
            },
        }
    }
}

// Limite defensivo: Zig 0.16 usa un buffer de pila fijo de 32767 wchars en
// sliceToPrefixedFileW y no valida la longitud; un path mas largo desborda
// (UB en ReleaseFast, panic en Debug). Lo cortamos antes de tocar el FS.
const max_path_len = 4096;

fn readTextFile(io: Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return error.RutaVacia;
    if (path.len > max_path_len) return error.RutaDemasiadoLarga;
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024));
}

fn writeTextFile(io: Io, path: []const u8, data: []const u8) !void {
    if (path.len == 0) return error.RutaVacia;
    if (path.len > max_path_len) return error.RutaDemasiadoLarga;
    return std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

const max_dictionary_terms: u64 = 1000;

fn estimateDictionaryTerms(n_in: usize, non_identity_acts: usize, include_interactions: bool) u64 {
    const n: u64 = @intCast(n_in);
    const a: u64 = @intCast(non_identity_acts);
    const base: u64 = (n + 1) + a * n;
    if (!include_interactions) return base;
    const c2: u64 = if (n >= 2) (n * (n - 1)) / 2 else 0;
    const c3: u64 = if (n >= 3) (n * (n - 1) * (n - 2)) / 6 else 0;
    const g: u64 = a + 1;
    return base + c2 * g * g + c3 * g * g * g;
}

fn stripUtf8Bom(content: []const u8) []const u8 {
    if (content.len >= 3 and content[0] == 0xEF and content[1] == 0xBB and content[2] == 0xBF) {
        return content[3..];
    }
    return content;
}

fn detectCsvDelimiter(line: []const u8) u8 {
    var semicolons: usize = 0;
    var tabs: usize = 0;
    var commas: usize = 0;
    var in_quotes = false;
    for (line) |c| {
        if (c == '"') {
            in_quotes = !in_quotes;
            continue;
        }
        if (in_quotes) continue;
        switch (c) {
            ';' => semicolons += 1,
            '\t' => tabs += 1,
            ',' => commas += 1,
            else => {},
        }
    }
    if (semicolons > 0) return ';';
    if (tabs > 0) return '\t';
    return ',';
}

fn unquoteCsvField(raw: []const u8) []const u8 {
    var s = std.mem.trim(u8, raw, " \t\r");
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') {
        s = s[1 .. s.len - 1];
    }
    return std.mem.trim(u8, s, " \t");
}

const SindyCsv = struct {
    samples: std.ArrayList(ermc.Sample),
    n_inputs: usize,

    fn deinit(self: *SindyCsv, gpa: std.mem.Allocator) void {
        for (self.samples.items) |s| gpa.free(s.inputs);
        self.samples.deinit(gpa);
    }
};

fn parseSindyCsv(gpa: std.mem.Allocator, content_in: []const u8) !SindyCsv {
    var samples = std.ArrayList(ermc.Sample).empty;
    errdefer {
        for (samples.items) |s| gpa.free(s.inputs);
        samples.deinit(gpa);
    }

    const content = stripUtf8Bom(content_in);
    var cols: usize = 0;
    var header_cols: usize = 0;
    var delimiter: u8 = ',';
    var first_row = true;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (first_row) {
            delimiter = detectCsvDelimiter(line);
            first_row = false;
        }

        var parts = std.mem.splitScalar(u8, line, delimiter);
        var vals = std.ArrayList(f64).empty;
        defer vals.deinit(gpa);
        var field_count: usize = 0;
        var parse_failed = false;
        while (parts.next()) |p| {
            field_count += 1;
            const pt = unquoteCsvField(p);
            if (pt.len == 0) return error.CampoVacio;
            const v = std.fmt.parseFloat(f64, pt) catch {
                parse_failed = true;
                continue;
            };
            if (!std.math.isFinite(v)) return error.ValorNoFinito;
            try vals.append(gpa, v);
        }

        if (parse_failed) {
            // Primera fila no numerica: cabecera opcional.
            if (samples.items.len == 0 and cols == 0 and header_cols == 0) {
                if (field_count < 2) return error.InvalidCharacter;
                header_cols = field_count;
                continue;
            }
            return error.InvalidCharacter;
        }
        if (field_count < 2) return error.InvalidCharacter;
        if (header_cols != 0 and field_count != header_cols) return error.InvalidCharacter;
        if (cols == 0) cols = field_count;
        if (field_count != cols) return error.InvalidCharacter;

        const n_in = cols - 1;
        const inputs = try gpa.alloc(f64, n_in);
        @memcpy(inputs, vals.items[0..n_in]);
        try samples.append(gpa, .{ .inputs = inputs, .target = vals.items[cols - 1] });
    }

    if (samples.items.len == 0 or cols < 2) return error.InvalidCharacter;
    return .{ .samples = samples, .n_inputs = cols - 1 };
}

/// CSV de trayectoria: primera columna = tiempo, resto = estados x0..x_{d-1}.
const TrajectoryCsv = struct {
    time: []f64,
    states: [][]f64,
    n_dim: usize,
    allocator: std.mem.Allocator,

    fn deinit(self: *TrajectoryCsv) void {
        self.allocator.free(self.time);
        for (self.states) |row| self.allocator.free(row);
        self.allocator.free(self.states);
    }
};

fn parseTrajectoryCsv(gpa: std.mem.Allocator, content_in: []const u8) !TrajectoryCsv {
    var flat = std.ArrayList(f64).empty;
    defer flat.deinit(gpa);

    const content = stripUtf8Bom(content_in);
    var cols: usize = 0;
    var header_cols: usize = 0;
    var delimiter: u8 = ',';
    var first_row = true;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (first_row) {
            delimiter = detectCsvDelimiter(line);
            first_row = false;
        }

        var parts = std.mem.splitScalar(u8, line, delimiter);
        var vals = std.ArrayList(f64).empty;
        defer vals.deinit(gpa);
        var field_count: usize = 0;
        var parse_failed = false;
        while (parts.next()) |p| {
            field_count += 1;
            const pt = unquoteCsvField(p);
            if (pt.len == 0) return error.CampoVacio;
            const v = std.fmt.parseFloat(f64, pt) catch {
                parse_failed = true;
                continue;
            };
            if (!std.math.isFinite(v)) return error.ValorNoFinito;
            try vals.append(gpa, v);
        }

        if (parse_failed) {
            // Primera fila no numerica: cabecera opcional.
            if (flat.items.len == 0 and cols == 0 and header_cols == 0) {
                if (field_count < 2) return error.InvalidCharacter;
                header_cols = field_count;
                continue;
            }
            return error.InvalidCharacter;
        }
        if (field_count < 2) return error.InvalidCharacter;
        if (header_cols != 0 and field_count != header_cols) return error.InvalidCharacter;
        if (cols == 0) cols = field_count;
        if (field_count != cols) return error.InvalidCharacter;

        try flat.appendSlice(gpa, vals.items);
    }

    if (cols < 2 or flat.items.len < cols * 2) return error.InvalidCharacter;
    const n_rows = flat.items.len / cols;
    const n_dim = cols - 1;

    const time = try gpa.alloc(f64, n_rows);
    errdefer gpa.free(time);
    const states = try gpa.alloc([]f64, n_rows);
    errdefer gpa.free(states);
    var built: usize = 0;
    errdefer for (states[0..built]) |row| gpa.free(row);

    for (0..n_rows) |s| {
        const base = s * cols;
        time[s] = flat.items[base];
        const row = try gpa.alloc(f64, n_dim);
        @memcpy(row, flat.items[base + 1 .. base + cols]);
        states[s] = row;
        built += 1;
    }

    return .{ .time = time, .states = states, .n_dim = n_dim, .allocator = gpa };
}

fn sindyErrorMessage(e: anyerror) []const u8 {
    return switch (e) {
        error.CampoVacio => "Invalid params: CSV con campo vacio.",
        error.ValorNoFinito => "Invalid params: CSV contiene NaN o Inf.",
        error.InvalidCharacter => "Invalid params: CSV no numerico o columnas inconsistentes.",
        error.DiccionarioDemasiadoGrande => "Invalid params: diccionario demasiado grande; reduce variables o activaciones.",
        error.DemasiadasVariables => "Invalid params: maximo 64 columnas de entrada.",
        error.DataRequerida => "Invalid params: data (ruta CSV) obligatoria.",
        error.ModelRequerido => "Invalid params: model (ruta JSON) obligatorio.",
        error.EntradaRequerida => "Invalid params: data (CSV) o x (punto coma-sep) obligatorio.",
        error.ModelInvalido => "Invalid params: modelo JSON invalido o incompatible con activaciones/entrada.",
        error.ArgsInvalidos => "Invalid params: arguments debe ser un objeto.",
        error.ParamDesconocido => "Invalid params: parametro desconocido.",
        error.ParamType => "Invalid params: tipo de parametro invalido.",
        error.ParamNegative => "Invalid params: valor negativo no permitido.",
        error.ThresholdFueraDeRango => "Invalid params: threshold debe estar en [0, 1].",
        error.RidgeFueraDeRango => "Invalid params: ridge debe ser >= 0.",
        error.HuberFueraDeRango => "Invalid params: huber debe ser >= 0 (0 = automatico).",
        error.IrlsFueraDeRango => "Invalid params: irls debe estar en [0, 100].",
        error.StlsqFueraDeRango => "Invalid params: stlsq_iters debe estar en [0, 100].",
        error.VarsFueraDeRango => "Invalid params: vars debe estar en [0, 64].",
        error.VentanaFueraDeRango => "Invalid params: window_half debe cumplir 2 <= window_half y 2*window_half+1 <= muestras.",
        error.FileNotFound => "No se encontro el archivo CSV.",
        error.AccessDenied => "Acceso denegado al archivo.",
        else => @errorName(e),
    };
}

const SindyArgs = struct {
    data_path: []const u8 = "",
    threshold: f64 = 0.015,
    vars: usize = 0,
    save_path: []const u8 = "",
    irls: usize = 2,
    stlsq_iters: usize = 8,
    huber: f64 = 1.345,
    noise_gate: bool = true,
    snap: bool = true,
    interactions: bool = false,
    ridge: f64 = 0.0,
    acts_str: []const u8 = "",
};

fn sindyNumber(obj: *const std.json.ObjectMap, key: []const u8, default: f64) !f64 {
    if (obj.get(key)) |v| {
        if (v == .float) return v.float;
        if (v == .integer) return @floatFromInt(v.integer);
        return error.ParamType;
    }
    return default;
}

fn sindyUsize(obj: *const std.json.ObjectMap, key: []const u8, default: usize) !usize {
    if (obj.get(key)) |v| {
        if (v != .integer) return error.ParamType;
        if (v.integer < 0) return error.ParamNegative;
        return @intCast(v.integer);
    }
    return default;
}

fn sindyBool(obj: *const std.json.ObjectMap, key: []const u8, default: bool) !bool {
    if (obj.get(key)) |v| {
        if (v != .bool) return error.ParamType;
        return v.bool;
    }
    return default;
}

fn sindyString(obj: *const std.json.ObjectMap, key: []const u8, default: []const u8) ![]const u8 {
    if (obj.get(key)) |v| {
        if (v != .string) return error.ParamType;
        return v.string;
    }
    return default;
}

fn parseSindyArgs(args: ?std.json.Value) !SindyArgs {
    var out = SindyArgs{};
    const a = args orelse return error.DataRequerida;
    if (a != .object) return error.ArgsInvalidos;
    const obj = &a.object;

    const known = [_][]const u8{
        "data",  "threshold",  "vars", "save",         "irls",  "stlsq_iters",
        "huber", "noise_gate", "snap", "interactions", "ridge", "activations",
    };
    for (obj.keys()) |key| {
        var ok = false;
        for (known) |k| {
            if (std.mem.eql(u8, key, k)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.ParamDesconocido;
    }

    out.data_path = try sindyString(obj, "data", "");
    if (out.data_path.len == 0) return error.DataRequerida;
    out.threshold = try sindyNumber(obj, "threshold", out.threshold);
    out.vars = try sindyUsize(obj, "vars", out.vars);
    out.save_path = try sindyString(obj, "save", out.save_path);
    out.irls = try sindyUsize(obj, "irls", out.irls);
    out.stlsq_iters = try sindyUsize(obj, "stlsq_iters", out.stlsq_iters);
    out.huber = try sindyNumber(obj, "huber", out.huber);
    out.noise_gate = try sindyBool(obj, "noise_gate", out.noise_gate);
    out.snap = try sindyBool(obj, "snap", out.snap);
    out.interactions = try sindyBool(obj, "interactions", out.interactions);
    out.ridge = try sindyNumber(obj, "ridge", out.ridge);
    out.acts_str = try sindyString(obj, "activations", out.acts_str);
    return out;
}

/// Parsea la lista coma-separada de activaciones. Devuelve error.InvalidCharacter
/// para tokens desconocidos y deja `out` con las activaciones validas.
fn parseActivationList(gpa: std.mem.Allocator, acts_str: []const u8, out: *std.ArrayList(ermc.Activation)) !void {
    const src_str = if (acts_str.len == 0) "id,sqr" else acts_str;
    var it = std.mem.splitScalar(u8, src_str, ',');
    while (it.next()) |tok| {
        const t = std.mem.trim(u8, tok, " \t");
        if (t.len == 0) continue;
        if (std.mem.eql(u8, t, "id") or std.mem.eql(u8, t, "identity")) {
            try out.append(gpa, .Identity);
        } else if (std.mem.eql(u8, t, "sin") or std.mem.eql(u8, t, "sine")) {
            try out.append(gpa, .Sine);
        } else if (std.mem.eql(u8, t, "cos") or std.mem.eql(u8, t, "cosine")) {
            try out.append(gpa, .Cosine);
        } else if (std.mem.eql(u8, t, "sqr") or std.mem.eql(u8, t, "square")) {
            try out.append(gpa, .Square);
        } else if (std.mem.eql(u8, t, "cube")) {
            try out.append(gpa, .Cube);
        } else if (std.mem.eql(u8, t, "exp")) {
            try out.append(gpa, .Exp);
        } else if (std.mem.eql(u8, t, "expneg") or std.mem.eql(u8, t, "exp_neg")) {
            try out.append(gpa, .ExpNeg);
        } else if (std.mem.eql(u8, t, "ln")) {
            try out.append(gpa, .Ln);
        } else if (std.mem.eql(u8, t, "tanh")) {
            try out.append(gpa, .Tanh);
        } else if (std.mem.eql(u8, t, "inv")) {
            try out.append(gpa, .Inv);
        } else if (std.mem.eql(u8, t, "sqrt")) {
            try out.append(gpa, .Sqrt);
        } else if (std.mem.eql(u8, t, "inv_sqr") or std.mem.eql(u8, t, "invsqr") or std.mem.eql(u8, t, "inv_square")) {
            try out.append(gpa, .InverseSquare);
        } else if (std.mem.eql(u8, t, "poly2")) {
            try out.append(gpa, .Square);
        } else if (std.mem.eql(u8, t, "poly3")) {
            try out.append(gpa, .Square);
            try out.append(gpa, .Cube);
        } else {
            return error.InvalidCharacter;
        }
    }
    if (out.items.len == 0) return error.InvalidCharacter;
}

fn dictionaryTermGuard(n_in: usize, acts: []const ermc.Activation, interactions: bool) !void {
    var non_identity_acts: usize = 0;
    for (acts) |act| {
        switch (act) {
            .Identity, .Interaction => {},
            else => non_identity_acts += 1,
        }
    }
    const estimated_terms = estimateDictionaryTerms(n_in, non_identity_acts, interactions);
    if (estimated_terms > max_dictionary_terms) return error.DiccionarioDemasiadoGrande;
}

fn sindyCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8, threshold: f64, vars: usize, save_path: []const u8, irls: usize, stlsq_iters: usize, huber: f64, noise_gate: bool, snap: bool, interactions: bool, ridge: f64, acts_str: []const u8) ![]u8 {
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var parsed = try parseSindyCsv(gpa, content);
    defer parsed.deinit(gpa);
    const samples = &parsed.samples;
    const n_in = parsed.n_inputs;
    if (vars != 0 and vars != n_in) return error.InvalidCharacter;
    // El diccionario expandido crece O(n_in^3) (interacciones). Acotamos para
    // evitar un DoS de memoria/CPU desde un CSV ancho.
    if (n_in > 64) return error.DemasiadasVariables;

    var engine = try ermc.OmniEngine.init(gpa, n_in);
    defer engine.deinit();
    // Activaciones por defecto: polinomio de grado 2. Es el punto de partida
    // mas seguro; el usuario puede pedir sin/exp/etc. de forma explicita.
    var acts_list = std.ArrayList(ermc.Activation).empty;
    defer acts_list.deinit(gpa);
    try parseActivationList(gpa, acts_str, &acts_list);
    // El diccionario expandido crece de forma cubica con las variables y con
    // las activaciones. La cota lineal anterior no protegia contra el DoS.
    try dictionaryTermGuard(n_in, acts_list.items, interactions);
    try engine.buildExpansionDictionaryAdvanced(acts_list.items, interactions);

    const opts = ermc.core.SolveOptions{
        .parsimony_threshold = threshold,
        .max_irls_iters = irls,
        .max_stlsq_iters = stlsq_iters,
        .huber_tuning = huber,
        .noise_gate_l2 = noise_gate,
        .snap_constants = snap,
        .ridge = ridge,
    };
    const weights = try engine.solveAnalyticalWithOptions(samples.items, opts);
    defer gpa.free(weights);
    const formula = try engine.getReconstructedFormula(weights);
    defer gpa.free(formula);
    const active = engine.countActiveTerms(weights);

    // Metricas de ajuste en una sola pasada.
    var y_sum: f64 = 0.0;
    var ss_res: f64 = 0.0;
    var abs_res: f64 = 0.0;
    for (samples.items) |sample| {
        const pred = engine.predict(sample.inputs, weights);
        const resid = sample.target - pred;
        ss_res += resid * resid;
        abs_res += @abs(resid);
        y_sum += sample.target;
    }
    const n_samples_f: f64 = @floatFromInt(samples.items.len);
    const y_mean = y_sum / n_samples_f;
    var ss_tot: f64 = 0.0;
    for (samples.items) |sample| {
        const dev = sample.target - y_mean;
        ss_tot += dev * dev;
    }
    var r2: f64 = 0.0;
    if (ss_tot > 1e-30) {
        r2 = 1.0 - ss_res / ss_tot;
    } else if (ss_res < 1e-30) {
        r2 = 1.0;
    }
    const rmse = @sqrt(ss_res / n_samples_f);
    const mae = abs_res / n_samples_f;

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"formula\":\"");
    try escapeJson(formula, &buf, gpa);
    try buf.appendSlice(gpa, "\",\"r2\":");
    try appendNum(&buf, gpa, r2);
    try buf.appendSlice(gpa, ",\"rmse\":");
    try appendNum(&buf, gpa, rmse);
    try buf.appendSlice(gpa, ",\"mae\":");
    try appendNum(&buf, gpa, mae);
    try buf.appendSlice(gpa, ",\"active\":");
    try appendUint(&buf, gpa, active);
    try buf.appendSlice(gpa, ",\"terms\":");
    try appendUint(&buf, gpa, engine.termCount());
    try buf.appendSlice(gpa, ",\"samples\":");
    try appendUint(&buf, gpa, samples.items.len);
    try buf.appendSlice(gpa, ",\"interactions\":");
    try buf.appendSlice(gpa, if (interactions) "true" else "false");
    try buf.appendSlice(gpa, ",\"activations\":\"");
    const effective_acts = if (acts_str.len == 0) "id,sqr" else acts_str;
    try escapeJson(effective_acts, &buf, gpa);
    try buf.appendSlice(gpa, "\",\"kind\":\"static\",\"n_inputs\":");
    try appendUint(&buf, gpa, n_in);
    try buf.appendSlice(gpa, ",\"threshold\":");
    try appendNum(&buf, gpa, threshold);
    try buf.appendSlice(gpa, ",\"weights\":[");
    for (weights, 0..) |w, i| {
        if (i > 0) try buf.append(gpa, ',');
        try appendNum(&buf, gpa, w);
    }
    try buf.appendSlice(gpa, "],\"term_names\":[");
    for (engine.dict.node_names.items, 0..) |name, i| {
        if (i > 0) try buf.append(gpa, ',');
        try buf.append(gpa, '"');
        try escapeJson(name, &buf, gpa);
        try buf.append(gpa, '"');
    }
    try buf.appendSlice(gpa, "],\"coefficients\":[");
    var first_coef = true;
    for (weights, 0..) |w, i| {
        if (@abs(w) <= 1e-8) continue;
        const name = if (i < engine.dict.node_names.items.len) engine.dict.node_names.items[i] else "unk";
        if (!first_coef) try buf.append(gpa, ',');
        first_coef = false;
        try buf.appendSlice(gpa, "{\"name\":\"");
        try escapeJson(name, &buf, gpa);
        try buf.appendSlice(gpa, "\",\"value\":");
        try appendNum(&buf, gpa, w);
        try buf.append(gpa, '}');
    }
    try buf.appendSlice(gpa, "]}");
    const out_slice = try buf.toOwnedSlice(gpa);
    if (save_path.len > 0) {
        try writeTextFile(io, save_path, out_slice);
    }
    return out_slice;
}

const SindyDynArgs = struct {
    data_path: []const u8 = "",
    threshold: f64 = 0.015,
    window_half: usize = 15,
    vars: usize = 0,
    save_path: []const u8 = "",
    irls: usize = 2,
    stlsq_iters: usize = 8,
    huber: f64 = 1.345,
    noise_gate: bool = true,
    snap: bool = true,
    interactions: bool = false,
    ridge: f64 = 0.0,
    acts_str: []const u8 = "",
};

fn parseSindyDynArgs(args: ?std.json.Value) !SindyDynArgs {
    var out = SindyDynArgs{};
    const a = args orelse return error.DataRequerida;
    if (a != .object) return error.ArgsInvalidos;
    const obj = &a.object;

    const known = [_][]const u8{
        "data",        "threshold", "window_half", "vars", "save",         "irls",
        "stlsq_iters", "huber",     "noise_gate",  "snap", "interactions", "ridge",
        "activations",
    };
    for (obj.keys()) |key| {
        var ok = false;
        for (known) |k| {
            if (std.mem.eql(u8, key, k)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.ParamDesconocido;
    }

    out.data_path = try sindyString(obj, "data", "");
    if (out.data_path.len == 0) return error.DataRequerida;
    out.threshold = try sindyNumber(obj, "threshold", out.threshold);
    out.window_half = try sindyUsize(obj, "window_half", out.window_half);
    out.vars = try sindyUsize(obj, "vars", out.vars);
    out.save_path = try sindyString(obj, "save", out.save_path);
    out.irls = try sindyUsize(obj, "irls", out.irls);
    out.stlsq_iters = try sindyUsize(obj, "stlsq_iters", out.stlsq_iters);
    out.huber = try sindyNumber(obj, "huber", out.huber);
    out.noise_gate = try sindyBool(obj, "noise_gate", out.noise_gate);
    out.snap = try sindyBool(obj, "snap", out.snap);
    out.interactions = try sindyBool(obj, "interactions", out.interactions);
    out.ridge = try sindyNumber(obj, "ridge", out.ridge);
    out.acts_str = try sindyString(obj, "activations", out.acts_str);
    return out;
}

/// SINDy dinamico: la primera columna del CSV es el tiempo y el resto son los
/// estados. Estima derivadas con Savitzky-Golay y descubre dx_d/dt = f(x).
fn sindyDynamicalCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8, threshold: f64, window_half: usize, vars: usize, save_path: []const u8, irls: usize, stlsq_iters: usize, huber: f64, noise_gate: bool, snap: bool, interactions: bool, ridge: f64, acts_str: []const u8) ![]u8 {
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var parsed = try parseTrajectoryCsv(gpa, content);
    defer parsed.deinit();
    const n_samples = parsed.states.len;
    const n_dim = parsed.n_dim;
    if (vars != 0 and vars != n_dim) return error.InvalidCharacter;
    if (n_dim > 64) return error.DemasiadasVariables;
    if (n_samples < 5) return error.InvalidCharacter;
    if (window_half < 2 or window_half >= n_samples or 2 * window_half + 1 > n_samples) return error.VentanaFueraDeRango;

    var engine = try ermc.OmniEngine.init(gpa, n_dim);
    defer engine.deinit();
    var acts_list = std.ArrayList(ermc.Activation).empty;
    defer acts_list.deinit(gpa);
    try parseActivationList(gpa, acts_str, &acts_list);
    try dictionaryTermGuard(n_dim, acts_list.items, interactions);
    try engine.buildExpansionDictionaryAdvanced(acts_list.items, interactions);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const ta = arena.allocator();

    // Coordenadas por dimension y filtrado/diferenciacion Savitzky-Golay.
    const coords = try ta.alloc([]f64, n_dim);
    for (0..n_dim) |d| {
        coords[d] = try ta.alloc(f64, n_samples);
        for (0..n_samples) |s| coords[d][s] = parsed.states[s][d];
    }

    const smoothed = try ta.alloc(f64, n_samples * n_dim);
    const derivs = try ta.alloc([]f64, n_dim);
    for (0..n_dim) |d| {
        const filt = try ermc.filter.localSavitzkyGolayCubic(ta, parsed.time, coords[d], window_half);
        derivs[d] = filt.derivatives;
        for (0..n_samples) |s| smoothed[s * n_dim + d] = filt.smoothed[s];
    }

    const opts = ermc.core.SolveOptions{
        .parsimony_threshold = threshold,
        .max_irls_iters = irls,
        .max_stlsq_iters = stlsq_iters,
        .huber_tuning = huber,
        .noise_gate_l2 = noise_gate,
        .snap_constants = snap,
        .ridge = ridge,
    };

    const samples = try ta.alloc(ermc.Sample, n_samples);
    const pred = try ta.alloc(f64, n_samples);
    var weights_per_dim = try gpa.alloc([]f64, n_dim);
    defer {
        for (weights_per_dim) |w| gpa.free(w);
        gpa.free(weights_per_dim);
    }
    var formulas = try gpa.alloc([]u8, n_dim);
    defer {
        for (formulas) |f| gpa.free(f);
        gpa.free(formulas);
    }

    for (0..n_dim) |d| {
        for (0..n_samples) |s| {
            samples[s] = .{ .inputs = smoothed[s * n_dim .. s * n_dim + n_dim], .target = derivs[d][s] };
        }
        const w = try engine.solveAnalyticalWithOptions(samples, opts);
        weights_per_dim[d] = w;
        for (0..n_samples) |s| pred[s] = engine.predict(samples[s].inputs, w);
        formulas[d] = try engine.getReconstructedFormula(w);
    }

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"kind\":\"dynamical\",\"dim\":");
    try appendUint(&buf, gpa, n_dim);
    try buf.appendSlice(gpa, ",\"n_inputs\":");
    try appendUint(&buf, gpa, n_dim);
    try buf.appendSlice(gpa, ",\"samples\":");
    try appendUint(&buf, gpa, n_samples);
    try buf.appendSlice(gpa, ",\"window_half\":");
    try appendUint(&buf, gpa, window_half);
    try buf.appendSlice(gpa, ",\"terms\":");
    try appendUint(&buf, gpa, engine.termCount());
    try buf.appendSlice(gpa, ",\"interactions\":");
    try buf.appendSlice(gpa, if (interactions) "true" else "false");
    try buf.appendSlice(gpa, ",\"activations\":\"");
    const effective_acts = if (acts_str.len == 0) "id,sqr" else acts_str;
    try escapeJson(effective_acts, &buf, gpa);
    try buf.appendSlice(gpa, "\",\"threshold\":");
    try appendNum(&buf, gpa, threshold);
    try buf.appendSlice(gpa, ",\"term_names\":[");
    for (engine.dict.node_names.items, 0..) |name, i| {
        if (i > 0) try buf.append(gpa, ',');
        try buf.append(gpa, '"');
        try escapeJson(name, &buf, gpa);
        try buf.append(gpa, '"');
    }
    try buf.appendSlice(gpa, "],\"equations\":[");

    for (0..n_dim) |d| {
        const w = weights_per_dim[d];
        const y = derivs[d];
        for (0..n_samples) |s| pred[s] = engine.predict(samples[s].inputs, w);
        const r2d = ermc.solver.r2(y, pred);
        const rmsed = ermc.solver.rmse(y, pred);
        const maed = ermc.solver.mae(y, pred);
        const active = engine.countActiveTerms(w);
        if (d > 0) try buf.append(gpa, ',');
        try buf.appendSlice(gpa, "{\"dim\":");
        try appendUint(&buf, gpa, d);
        try buf.appendSlice(gpa, ",\"formula\":\"");
        try escapeJson(formulas[d], &buf, gpa);
        try buf.appendSlice(gpa, "\",\"r2\":");
        try appendNum(&buf, gpa, r2d);
        try buf.appendSlice(gpa, ",\"rmse\":");
        try appendNum(&buf, gpa, rmsed);
        try buf.appendSlice(gpa, ",\"mae\":");
        try appendNum(&buf, gpa, maed);
        try buf.appendSlice(gpa, ",\"active\":");
        try appendUint(&buf, gpa, active);
        try buf.appendSlice(gpa, ",\"weights\":[");
        for (w, 0..) |c, i| {
            if (i > 0) try buf.append(gpa, ',');
            try appendNum(&buf, gpa, c);
        }
        try buf.appendSlice(gpa, "],\"coefficients\":[");
        var first = true;
        for (w, 0..) |c, i| {
            if (@abs(c) <= 1e-8) continue;
            const name = if (i < engine.dict.node_names.items.len) engine.dict.node_names.items[i] else "unk";
            if (!first) try buf.append(gpa, ',');
            first = false;
            try buf.appendSlice(gpa, "{\"name\":\"");
            try escapeJson(name, &buf, gpa);
            try buf.appendSlice(gpa, "\",\"value\":");
            try appendNum(&buf, gpa, c);
            try buf.append(gpa, '}');
        }
        try buf.appendSlice(gpa, "]}");
    }
    try buf.appendSlice(gpa, "]}");

    const out_slice = try buf.toOwnedSlice(gpa);
    if (save_path.len > 0) {
        try writeTextFile(io, save_path, out_slice);
    }
    return out_slice;
}

fn runSindyDynamical(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const cfg = parseSindyDynArgs(args) catch |e| {
        try proto.sendToolError(out, id, sindyErrorMessage(e));
        return;
    };

    if (!(cfg.threshold >= 0.0) or !(cfg.threshold <= 1.0) or !std.math.isFinite(cfg.threshold)) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.ThresholdFueraDeRango));
        return;
    }
    if (!(cfg.ridge >= 0.0) or !std.math.isFinite(cfg.ridge)) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.RidgeFueraDeRango));
        return;
    }
    if (cfg.irls > 100) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.IrlsFueraDeRango));
        return;
    }
    if (cfg.stlsq_iters > 100) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.StlsqFueraDeRango));
        return;
    }
    if (!(cfg.huber >= 0.0) or !std.math.isFinite(cfg.huber)) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.HuberFueraDeRango));
        return;
    }
    if (cfg.vars > 64) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.VarsFueraDeRango));
        return;
    }

    const txt = sindyDynamicalCore(io, gpa, cfg.data_path, cfg.threshold, cfg.window_half, cfg.vars, cfg.save_path, cfg.irls, cfg.stlsq_iters, cfg.huber, cfg.noise_gate, cfg.snap, cfg.interactions, cfg.ridge, cfg.acts_str) catch |e| {
        try proto.sendToolError(out, id, sindyErrorMessage(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}

// ---------- sindy_load_predict: prediccion desde un modelo SINDy guardado ----------

const SindyModelKind = enum { static, dynamical };

const SindyPredictArgs = struct {
    model_path: []const u8 = "",
    data_path: []const u8 = "",
    x_str: []const u8 = "",
};

fn parseSindyPredictArgs(args: ?std.json.Value) !SindyPredictArgs {
    var out = SindyPredictArgs{};
    const a = args orelse return error.ModelRequerido;
    if (a != .object) return error.ArgsInvalidos;
    const obj = &a.object;
    const known = [_][]const u8{ "model", "data", "x" };
    for (obj.keys()) |key| {
        var ok = false;
        for (known) |k| {
            if (std.mem.eql(u8, key, k)) {
                ok = true;
                break;
            }
        }
        if (!ok) return error.ParamDesconocido;
    }
    out.model_path = try sindyString(obj, "model", "");
    if (out.model_path.len == 0) return error.ModelRequerido;
    out.data_path = try sindyString(obj, "data", "");
    out.x_str = try sindyString(obj, "x", "");
    if (out.data_path.len == 0 and out.x_str.len == 0) return error.EntradaRequerida;
    return out;
}

fn jsonFieldUsize(obj: anytype, key: []const u8) !usize {
    const v = obj.get(key) orelse return error.ModelInvalido;
    if (v != .integer or v.integer < 0) return error.ModelInvalido;
    return @intCast(v.integer);
}

fn jsonWeightArray(v: std.json.Value, gpa: std.mem.Allocator) ![]f64 {
    if (v != .array) return error.ModelInvalido;
    const items = v.array.items;
    const out = try gpa.alloc(f64, items.len);
    errdefer gpa.free(out);
    for (items, 0..) |el, i| {
        switch (el) {
            .integer => |n| out[i] = @floatFromInt(n),
            .float => |f| out[i] = f,
            else => return error.ModelInvalido,
        }
        if (!std.math.isFinite(out[i])) return error.ModelInvalido;
    }
    return out;
}

const LoadedSindyModel = struct {
    kind: SindyModelKind,
    n_inputs: usize,
    dim: usize,
    activations: []const u8,
    interactions: bool,
    static_weights: []const f64 = &.{},
    dyn_weights: []const []const f64 = &.{},
    allocator: std.mem.Allocator,

    fn deinit(self: *LoadedSindyModel) void {
        self.allocator.free(self.activations);
        switch (self.kind) {
            .static => self.allocator.free(self.static_weights),
            .dynamical => {
                for (self.dyn_weights) |w| self.allocator.free(w);
                self.allocator.free(self.dyn_weights);
            },
        }
    }
};

fn loadSindyModel(gpa: std.mem.Allocator, root: std.json.Value) !LoadedSindyModel {
    if (root != .object) return error.ModelInvalido;
    const obj = &root.object;
    const n_inputs = try jsonFieldUsize(obj, "n_inputs");
    if (n_inputs < 1 or n_inputs > 64) return error.ModelInvalido;
    const acts_val = obj.get("activations") orelse return error.ModelInvalido;
    if (acts_val != .string) return error.ModelInvalido;
    const activations = try gpa.dupe(u8, acts_val.string);
    errdefer gpa.free(activations);
    var interactions = false;
    if (obj.get("interactions")) |v| {
        if (v != .bool) return error.ModelInvalido;
        interactions = v.bool;
    }

    if (obj.get("equations")) |eqs| {
        if (eqs != .array or eqs.array.items.len == 0) return error.ModelInvalido;
        const dim = eqs.array.items.len;
        const dyn = try gpa.alloc([]const f64, dim);
        errdefer gpa.free(dyn);
        var built: usize = 0;
        errdefer for (dyn[0..built]) |w| gpa.free(w);
        for (eqs.array.items, 0..) |eq, di| {
            if (eq != .object) return error.ModelInvalido;
            const wv = eq.object.get("weights") orelse return error.ModelInvalido;
            dyn[di] = try jsonWeightArray(wv, gpa);
            built += 1;
        }
        return .{
            .kind = .dynamical,
            .n_inputs = n_inputs,
            .dim = dim,
            .activations = activations,
            .interactions = interactions,
            .dyn_weights = dyn,
            .allocator = gpa,
        };
    }

    const wv = obj.get("weights") orelse return error.ModelInvalido;
    const w = try jsonWeightArray(wv, gpa);
    return .{
        .kind = .static,
        .n_inputs = n_inputs,
        .dim = 1,
        .activations = activations,
        .interactions = interactions,
        .static_weights = w,
        .allocator = gpa,
    };
}

const InputRows = struct {
    rows: [][]f64,
    n_inputs: usize,
    allocator: std.mem.Allocator,

    fn deinit(self: *InputRows) void {
        for (self.rows) |r| self.allocator.free(r);
        self.allocator.free(self.rows);
    }
};

fn parseOneRow(gpa: std.mem.Allocator, text: []const u8) ![]f64 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return error.CampoVacio;
    const delimiter = detectCsvDelimiter(t);
    var vals = std.ArrayList(f64).empty;
    errdefer vals.deinit(gpa);
    var parts = std.mem.splitScalar(u8, t, delimiter);
    while (parts.next()) |p| {
        const pt = unquoteCsvField(p);
        if (pt.len == 0) return error.CampoVacio;
        const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
        if (!std.math.isFinite(v)) return error.ValorNoFinito;
        try vals.append(gpa, v);
    }
    return vals.toOwnedSlice(gpa);
}

fn parseInputRows(gpa: std.mem.Allocator, content_in: []const u8) !InputRows {
    var rows = std.ArrayList([]f64).empty;
    errdefer {
        for (rows.items) |r| gpa.free(r);
        rows.deinit(gpa);
    }

    const content = stripUtf8Bom(content_in);
    var n_inputs: usize = 0;
    var header_cols: usize = 0;
    var delimiter: u8 = ',';
    var first_row = true;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (first_row) {
            delimiter = detectCsvDelimiter(line);
            first_row = false;
        }

        var parts = std.mem.splitScalar(u8, line, delimiter);
        var vals = std.ArrayList(f64).empty;
        defer vals.deinit(gpa);
        var field_count: usize = 0;
        var parse_failed = false;
        while (parts.next()) |p| {
            field_count += 1;
            const pt = unquoteCsvField(p);
            if (pt.len == 0) return error.CampoVacio;
            const v = std.fmt.parseFloat(f64, pt) catch {
                parse_failed = true;
                continue;
            };
            if (!std.math.isFinite(v)) return error.ValorNoFinito;
            try vals.append(gpa, v);
        }

        if (parse_failed) {
            // Primera fila no numerica: cabecera opcional.
            if (rows.items.len == 0 and n_inputs == 0 and header_cols == 0) {
                header_cols = field_count;
                continue;
            }
            return error.InvalidCharacter;
        }
        if (field_count == 0) return error.InvalidCharacter;
        if (header_cols != 0 and field_count != header_cols) return error.InvalidCharacter;
        if (n_inputs == 0) n_inputs = field_count;
        if (field_count != n_inputs) return error.InvalidCharacter;

        {
            const row = try gpa.dupe(f64, vals.items);
            errdefer gpa.free(row);
            try rows.append(gpa, row);
        }
    }

    if (rows.items.len == 0 or n_inputs == 0) return error.InvalidCharacter;
    const out_rows = try rows.toOwnedSlice(gpa);
    return .{ .rows = out_rows, .n_inputs = n_inputs, .allocator = gpa };
}

fn sindyPredictCore(io: Io, gpa: std.mem.Allocator, model_path: []const u8, data_path: []const u8, x_str: []const u8) ![]u8 {
    const model_txt = try readTextFile(io, gpa, model_path);
    defer gpa.free(model_txt);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, model_txt, .{}) catch return error.ModelInvalido;
    defer parsed.deinit();
    var model = try loadSindyModel(gpa, parsed.value);
    defer model.deinit();

    var engine = try ermc.OmniEngine.init(gpa, model.n_inputs);
    defer engine.deinit();
    var acts = std.ArrayList(ermc.Activation).empty;
    defer acts.deinit(gpa);
    try parseActivationList(gpa, model.activations, &acts);
    try dictionaryTermGuard(model.n_inputs, acts.items, model.interactions);
    try engine.buildExpansionDictionaryAdvanced(acts.items, model.interactions);
    const n_terms = engine.termCount();

    switch (model.kind) {
        .static => if (model.static_weights.len != n_terms) return error.ModelInvalido,
        .dynamical => for (model.dyn_weights) |w| {
            if (w.len != n_terms) return error.ModelInvalido;
        },
    }

    var input_rows: InputRows = undefined;
    if (x_str.len > 0) {
        const row = try parseOneRow(gpa, x_str);
        if (row.len != model.n_inputs) {
            gpa.free(row);
            return error.ModelInvalido;
        }
        const arr = gpa.alloc([]f64, 1) catch |e| {
            gpa.free(row);
            return e;
        };
        arr[0] = row;
        input_rows = .{ .rows = arr, .n_inputs = model.n_inputs, .allocator = gpa };
    } else {
        const content = try readTextFile(io, gpa, data_path);
        defer gpa.free(content);
        input_rows = try parseInputRows(gpa, content);
    }
    defer input_rows.deinit();
    if (input_rows.n_inputs != model.n_inputs) return error.ModelInvalido;

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"kind\":\"");
    try buf.appendSlice(gpa, if (model.kind == .static) "static" else "dynamical");
    try buf.appendSlice(gpa, "\",\"n_inputs\":");
    try appendUint(&buf, gpa, model.n_inputs);
    try buf.appendSlice(gpa, ",\"samples\":");
    try appendUint(&buf, gpa, input_rows.rows.len);
    if (model.kind == .dynamical) {
        try buf.appendSlice(gpa, ",\"dim\":");
        try appendUint(&buf, gpa, model.dim);
    }
    try buf.appendSlice(gpa, ",\"predictions\":[");
    switch (model.kind) {
        .static => for (input_rows.rows, 0..) |row, i| {
            if (i > 0) try buf.append(gpa, ',');
            try appendNum(&buf, gpa, engine.predict(row, model.static_weights));
        },
        .dynamical => for (input_rows.rows, 0..) |row, i| {
            if (i > 0) try buf.append(gpa, ',');
            try buf.append(gpa, '[');
            for (model.dyn_weights, 0..) |w, di| {
                if (di > 0) try buf.append(gpa, ',');
                try appendNum(&buf, gpa, engine.predict(row, w));
            }
            try buf.append(gpa, ']');
        },
    }
    try buf.appendSlice(gpa, "]}");
    return buf.toOwnedSlice(gpa);
}

fn runSindyLoadPredict(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const cfg = parseSindyPredictArgs(args) catch |e| {
        try proto.sendToolError(out, id, sindyErrorMessage(e));
        return;
    };
    const txt = sindyPredictCore(io, gpa, cfg.model_path, cfg.data_path, cfg.x_str) catch |e| {
        try proto.sendToolError(out, id, sindyErrorMessage(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}

fn runSindyCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8, threshold: f64, vars: usize, save_path: []const u8, irls: usize, stlsq_iters: usize, huber: f64, noise_gate: bool, snap: bool, interactions: bool, ridge: f64, acts_str: []const u8) !void {
    const txt = sindyCore(io, gpa, data_path, threshold, vars, save_path, irls, stlsq_iters, huber, noise_gate, snap, interactions, ridge, acts_str) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runSindyDynamicalCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8, threshold: f64, window_half: usize, vars: usize, save_path: []const u8, irls: usize, stlsq_iters: usize, huber: f64, noise_gate: bool, snap: bool, interactions: bool, ridge: f64, acts_str: []const u8) !void {
    const txt = sindyDynamicalCore(io, gpa, data_path, threshold, window_half, vars, save_path, irls, stlsq_iters, huber, noise_gate, snap, interactions, ridge, acts_str) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runSindyLoadPredictCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, model_path: []const u8, data_path: []const u8, x_str: []const u8) !void {
    const txt = sindyPredictCore(io, gpa, model_path, data_path, x_str) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runSindy(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const cfg = parseSindyArgs(args) catch |e| {
        try proto.sendToolError(out, id, sindyErrorMessage(e));
        return;
    };

    // Limites defensivos: evitan bucles y diccionarios sin cota.
    if (!(cfg.threshold >= 0.0) or !(cfg.threshold <= 1.0) or !std.math.isFinite(cfg.threshold)) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.ThresholdFueraDeRango));
        return;
    }
    if (!(cfg.ridge >= 0.0) or !std.math.isFinite(cfg.ridge)) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.RidgeFueraDeRango));
        return;
    }
    if (cfg.irls > 100) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.IrlsFueraDeRango));
        return;
    }
    if (cfg.stlsq_iters > 100) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.StlsqFueraDeRango));
        return;
    }
    if (!(cfg.huber >= 0.0) or !std.math.isFinite(cfg.huber)) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.HuberFueraDeRango));
        return;
    }
    if (cfg.vars > 64) {
        try proto.sendToolError(out, id, sindyErrorMessage(error.VarsFueraDeRango));
        return;
    }

    const txt = sindyCore(io, gpa, cfg.data_path, cfg.threshold, cfg.vars, cfg.save_path, cfg.irls, cfg.stlsq_iters, cfg.huber, cfg.noise_gate, cfg.snap, cfg.interactions, cfg.ridge, cfg.acts_str) catch |e| {
        try proto.sendToolError(out, id, sindyErrorMessage(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn svdCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8) ![]u8 {
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var rows: usize = 0;
    var cols: usize = 0;
    var data = std.ArrayList(f64).empty;
    defer data.deinit(gpa);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ',');
        var row_vals: usize = 0;
        while (parts.next()) |p| {
            const pt = std.mem.trim(u8, p, " \t");
            if (pt.len == 0) continue;
            const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
            try data.append(gpa, v);
            row_vals += 1;
        }
        if (row_vals == 0) continue;
        if (cols == 0) cols = row_vals;
        if (row_vals != cols) return error.InvalidCharacter;
        rows += 1;
    }
    if (rows == 0 or cols == 0) return error.InvalidCharacter;
    if (rows < cols) return error.MatrizAncha;

    var mat = try ermc.linalg.DenseMatrix.init(gpa, rows, cols);
    defer mat.deinit();
    @memcpy(mat.data, data.items[0 .. rows * cols]);

    var res = try ermc.linalg.computeSvd(gpa, mat, 100, 1e-12);
    defer res.deinit();

    // Rango numerico con tolerancia relativa (max(m,n) * sigma_max * eps).
    const rank = res.rank(null);

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"singular_values\":[");
    for (res.s, 0..) |s, i| {
        if (i > 0) try buf.append(gpa, ',');
        try appendNum(&buf, gpa, s);
    }
    try buf.appendSlice(gpa, "],\"rank\":");
    try appendUint(&buf, gpa, rank);
    try buf.appendSlice(gpa, ",\"m\":");
    try appendUint(&buf, gpa, rows);
    try buf.appendSlice(gpa, ",\"n\":");
    try appendUint(&buf, gpa, cols);
    try buf.append(gpa, '}');
    return buf.toOwnedSlice(gpa);
}

fn runSvdCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8) !void {
    const txt = svdCore(io, gpa, data_path) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runSvd(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const data_path = proto.argStr(args, "data", "");
    if (data_path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: data (ruta CSV) obligatoria.");
        return;
    }
    const txt = svdCore(io, gpa, data_path) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn sequenceCore(gpa: std.mem.Allocator, values_str: []const u8) ![]u8 {
    // parse comma-separated values
    var seq = std.ArrayList(f64).empty;
    defer seq.deinit(gpa);
    var parts = std.mem.splitScalar(u8, values_str, ',');
    while (parts.next()) |p| {
        const pt = std.mem.trim(u8, p, " \t");
        if (pt.len == 0) continue;
        const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
        try seq.append(gpa, v);
    }
    if (seq.items.len < 4) return error.InvalidCharacter;

    const ai = ermc.series.SequenceAi.init();
    const coefs = try ai.fitGaps(gpa, seq.items);
    defer gpa.free(coefs);
    const next = ai.predictNext(seq.items, coefs);

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"next\":");
    try appendNum(&buf, gpa, next);
    try buf.appendSlice(gpa, ",\"samples\":");
    try appendUint(&buf, gpa, seq.items.len);
    try buf.append(gpa, '}');
    return buf.toOwnedSlice(gpa);
}

fn runSequenceCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, values_str: []const u8) !void {
    _ = io;
    const txt = sequenceCore(gpa, values_str) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runSequence(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    _ = io;
    const values_str = proto.argStr(args, "values", "");
    if (values_str.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: values (coma-separados) obligatorio.");
        return;
    }
    const txt = sequenceCore(gpa, values_str) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn dmdCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8, dt: f64, rank: usize) ![]u8 {
    if (rank == 0 or rank > max_dmd_rank) return error.RankInvalido;
    if (!(dt > 0.0) or !std.math.isFinite(dt)) return error.DtInvalido;
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var rows: usize = 0;
    var cols: usize = 0;
    var data = std.ArrayList(f64).empty;
    defer data.deinit(gpa);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ',');
        var row_vals: usize = 0;
        while (parts.next()) |p| {
            const pt = std.mem.trim(u8, p, " \t");
            if (pt.len == 0) continue;
            const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
            try data.append(gpa, v);
            row_vals += 1;
        }
        if (row_vals == 0) continue;
        if (cols == 0) cols = row_vals;
        if (row_vals != cols) return error.InvalidCharacter;
        rows += 1;
    }
    if (rows == 0 or cols < 3) return error.InvalidCharacter;

    var mat = try ermc.linalg.DenseMatrix.init(gpa, rows, cols);
    defer mat.deinit();
    @memcpy(mat.data, data.items[0 .. rows * cols]);

    var res = try ermc.solver.computeDmd(gpa, mat, dt, rank);
    defer res.deinit();

    // dominant mode by amplitude
    var best_idx: usize = 0;
    var best_amp: f64 = -1;
    for (res.modes, 0..) |m, i| {
        if (m.amplitude > best_amp) {
            best_amp = m.amplitude;
            best_idx = i;
        }
    }

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    if (res.modes.len == 0) {
        try buf.appendSlice(gpa, "{\"modes\":0}");
        return buf.toOwnedSlice(gpa);
    }
    const m = res.modes[best_idx];
    try buf.appendSlice(gpa, "{\"dominant_frequency\":");
    try appendNum(&buf, gpa, m.frequency_rad_s);
    try buf.appendSlice(gpa, ",\"growth_rate\":");
    try appendNum(&buf, gpa, m.growth_rate);
    try buf.appendSlice(gpa, ",\"amplitude\":");
    try appendNum(&buf, gpa, m.amplitude);
    try buf.appendSlice(gpa, ",\"rank\":");
    try appendUint(&buf, gpa, res.rank);
    try buf.appendSlice(gpa, ",\"n_states\":");
    try appendUint(&buf, gpa, res.n_states);
    try buf.appendSlice(gpa, ",\"modes\":");
    try appendUint(&buf, gpa, res.modes.len);
    try buf.append(gpa, '}');
    return buf.toOwnedSlice(gpa);
}

fn runDmdCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8, dt: f64, rank: usize) !void {
    const txt = dmdCore(io, gpa, data_path, dt, rank) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runDmd(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const data_path = proto.argStr(args, "data", "");
    if (data_path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: data (ruta CSV) obligatoria.");
        return;
    }
    var dt: f64 = 1.0;
    var rank: usize = 10;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("dt")) |v| {
                if (v == .float) dt = v.float;
                if (v == .integer) dt = @floatFromInt(v.integer);
            }
            if (a.object.get("rank")) |v| {
                if (v == .integer) {
                    if (v.integer < 1) {
                        try proto.sendToolError(out, id, "Invalid params: rank debe ser >= 1.");
                        return;
                    }
                    rank = @intCast(v.integer);
                }
            }
        }
    }
    const txt = dmdCore(io, gpa, data_path, dt, rank) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn modelLoadCore(io: Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const content = try readTextFile(io, gpa, path);
    return content;
}

fn runModelLoadCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, path: []const u8) !void {
    const txt = modelLoadCore(io, gpa, path) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runModelLoad(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const path = proto.argStr(args, "path", "");
    if (path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: path obligatorio.");
        return;
    }
    const txt = modelLoadCore(io, gpa, path) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn pinvCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8) ![]u8 {
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var rows: usize = 0;
    var cols: usize = 0;
    var data = std.ArrayList(f64).empty;
    defer data.deinit(gpa);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ',');
        var row_vals: usize = 0;
        while (parts.next()) |p| {
            const pt = std.mem.trim(u8, p, " \t");
            if (pt.len == 0) continue;
            const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
            try data.append(gpa, v);
            row_vals += 1;
        }
        if (row_vals == 0) continue;
        if (cols == 0) cols = row_vals;
        if (row_vals != cols) return error.InvalidCharacter;
        rows += 1;
    }
    if (rows == 0 or cols == 0) return error.InvalidCharacter;

    var mat = try ermc.linalg.DenseMatrix.init(gpa, rows, cols);
    defer mat.deinit();
    @memcpy(mat.data, data.items[0 .. rows * cols]);

    var res = try ermc.linalg.computeSvd(gpa, mat, 100, 1e-12);
    defer res.deinit();

    // A^+ = V * diag(1/s) * U^T  (n x m)
    const n = cols;
    const m = rows;
    const pinv = try gpa.alloc(f64, n * m);
    defer gpa.free(pinv);
    @memset(pinv, 0.0);

    // Tolerancia relativa: descarta direcciones nulas (igual que SvdResult.pseudoInverse).
    const tol = @as(f64, @floatFromInt(@max(m, n))) * (if (res.s.len > 0) res.s[0] else 0.0) * 1e-15;

    for (0..n) |i| {
        for (0..m) |j| {
            var sum: f64 = 0.0;
            for (0..n) |k| {
                const s = res.s[k];
                if (s > tol) {
                    sum += res.v.get(i, k) * (1.0 / s) * res.u.get(j, k);
                }
            }
            pinv[i * m + j] = sum;
        }
    }

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"rows\":");
    try appendUint(&buf, gpa, n);
    try buf.appendSlice(gpa, ",\"cols\":");
    try appendUint(&buf, gpa, m);
    try buf.appendSlice(gpa, ",\"data\":[");
    for (pinv, 0..) |val, idx| {
        if (idx > 0) try buf.append(gpa, ',');
        try appendNum(&buf, gpa, val);
    }
    try buf.appendSlice(gpa, "]}");
    return buf.toOwnedSlice(gpa);
}

fn runPinvCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8) !void {
    const txt = pinvCore(io, gpa, data_path) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runPinv(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const data_path = proto.argStr(args, "data", "");
    if (data_path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: data (ruta CSV) obligatoria.");
        return;
    }
    const txt = pinvCore(io, gpa, data_path) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn parseBasis(s: []const u8) ?ermc.solver.koopman.KoopmanBasis {
    if (std.mem.eql(u8, s, "state")) return .StateOnly;
    if (std.mem.eql(u8, s, "poly2")) return .Polynomial2;
    if (std.mem.eql(u8, s, "poly3")) return .Polynomial3;
    return null;
}

fn basisName(b: ermc.solver.koopman.KoopmanBasis) []const u8 {
    return switch (b) {
        .StateOnly => "state",
        .Polynomial2 => "poly2",
        .Polynomial3 => "poly3",
    };
}

/// El ajuste de Koopman resuelve un sistema L x L (O(L^3)) sobre el espacio
/// elevado de dimensión L = dim(psi(x)). Sin cota, un CSV modesto dispara L
/// enorme (p. ej. 20x200 -> state_dim=100 -> poly2 L=5151) y bloquea el worker
/// durante minutos. Cota defensiva para que un cliente erróneo no lo tumbe.
const max_lifted_dim: usize = 1024;

fn checkLiftedDim(state_dim: usize, basis: ermc.solver.koopman.KoopmanBasis) !void {
    if (ermc.solver.koopman.computeLiftedDimension(state_dim, basis) > max_lifted_dim) {
        return error.DemasiadasVariables;
    }
}

/// Cota del rango de DMD. Los modos dominantes son pocos (decenas); pedir
/// rank = tamaño completo dispara el eigensolver O(r³) por paso y el coste
/// O(r⁴) en el peor caso. 256 acota el peor caso a unos pocos segundos.
const max_dmd_rank: usize = 256;

fn koopmanCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8, basis_str: []const u8, save_path: []const u8, ridge: f64) ![]u8 {
    if (!std.math.isFinite(ridge) or ridge < 0.0) return error.ParametrosInvalidos;
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var rows: usize = 0;
    var cols: usize = 0;
    var data = std.ArrayList(f64).empty;
    defer data.deinit(gpa);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ',');
        var row_vals: usize = 0;
        while (parts.next()) |p| {
            const pt = std.mem.trim(u8, p, " \t");
            if (pt.len == 0) continue;
            const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
            try data.append(gpa, v);
            row_vals += 1;
        }
        if (row_vals == 0) continue;
        if (cols == 0) cols = row_vals;
        if (row_vals != cols) return error.InvalidCharacter;
        rows += 1;
    }
    if (rows == 0 or cols < 2 or cols % 2 != 0) return error.InvalidCharacter;
    const state_dim = cols / 2;
    const n_snapshots = rows;

    const X = try gpa.alloc(f64, n_snapshots * state_dim);
    defer gpa.free(X);
    const Y = try gpa.alloc(f64, n_snapshots * state_dim);
    defer gpa.free(Y);
    for (0..rows) |r| {
        for (0..state_dim) |d| {
            X[r * state_dim + d] = data.items[r * cols + d];
            Y[r * state_dim + d] = data.items[r * cols + state_dim + d];
        }
    }

    const basis = parseBasis(basis_str) orelse return error.BasisInvalido;
    try checkLiftedDim(state_dim, basis);
    const opts = ermc.solver.koopman.KoopmanOptions{ .basis = basis, .ridge_alpha = ridge };
    var model = try ermc.solver.koopman.fitKoopman(gpa, X, Y, n_snapshots, state_dim, opts);
    defer model.deinit();

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"state_dim\":");
    try appendUint(&buf, gpa, model.state_dim);
    try buf.appendSlice(gpa, ",\"lifted_dim\":");
    try appendUint(&buf, gpa, model.lifted_dim);
    try buf.appendSlice(gpa, ",\"basis\":\"");
    try buf.appendSlice(gpa, basisName(basis));
    try buf.appendSlice(gpa, "\",\"K\":[");
    for (model.K, 0..) |val, idx| {
        if (idx > 0) try buf.append(gpa, ',');
        try appendNum(&buf, gpa, val);
    }
    try buf.appendSlice(gpa, "]}");
    const out_slice = try buf.toOwnedSlice(gpa);
    if (save_path.len > 0) {
        try writeTextFile(io, save_path, out_slice);
    }
    return out_slice;
}

fn runKoopmanCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8, basis_str: []const u8, save_path: []const u8, ridge: f64) !void {
    const txt = koopmanCore(io, gpa, data_path, basis_str, save_path, ridge) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runKoopman(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const data_path = proto.argStr(args, "data", "");
    if (data_path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: data (ruta CSV) obligatoria.");
        return;
    }
    const basis_str = proto.argStr(args, "basis", "poly2");
    const save_path = proto.argStr(args, "save", "");
    var ridge: f64 = 1e-7;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("ridge")) |v| {
                if (v == .float) ridge = v.float;
                if (v == .integer) ridge = @floatFromInt(v.integer);
            }
        }
    }
    const txt = koopmanCore(io, gpa, data_path, basis_str, save_path, ridge) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn koopmanPredictCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8, steps: usize, basis_str: []const u8, ridge: f64) ![]u8 {
    if (!std.math.isFinite(ridge) or ridge < 0.0) return error.ParametrosInvalidos;
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var rows: usize = 0;
    var cols: usize = 0;
    var data = std.ArrayList(f64).empty;
    defer data.deinit(gpa);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ',');
        var row_vals: usize = 0;
        while (parts.next()) |p| {
            const pt = std.mem.trim(u8, p, " \t");
            if (pt.len == 0) continue;
            const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
            try data.append(gpa, v);
            row_vals += 1;
        }
        if (row_vals == 0) continue;
        if (cols == 0) cols = row_vals;
        if (row_vals != cols) return error.InvalidCharacter;
        rows += 1;
    }
    if (rows == 0 or cols < 2 or cols % 2 != 0) return error.InvalidCharacter;
    const state_dim = cols / 2;
    const n_snapshots = rows;

    const X = try gpa.alloc(f64, n_snapshots * state_dim);
    defer gpa.free(X);
    const Y = try gpa.alloc(f64, n_snapshots * state_dim);
    defer gpa.free(Y);
    for (0..rows) |r| {
        for (0..state_dim) |d| {
            X[r * state_dim + d] = data.items[r * cols + d];
            Y[r * state_dim + d] = data.items[r * cols + state_dim + d];
        }
    }

    const basis = parseBasis(basis_str) orelse return error.BasisInvalido;
    try checkLiftedDim(state_dim, basis);
    const opts = ermc.solver.koopman.KoopmanOptions{ .basis = basis, .ridge_alpha = ridge };
    var model = try ermc.solver.koopman.fitKoopman(gpa, X, Y, n_snapshots, state_dim, opts);
    defer model.deinit();

    // initial state from first row
    const x0 = data.items[0..state_dim];
    // Cota de salida: evita intentar reservar decenas de GB (steps max 1e6 x
    // state_dim grande). Tambien descarta desbordamientos de steps*state_dim.
    const n_out = std.math.mul(usize, steps, state_dim) catch return error.ParametrosInvalidos;
    if (n_out > 50_000_000) return error.ParametrosInvalidos;
    const out_traj = try gpa.alloc(f64, n_out);
    defer gpa.free(out_traj);
    try model.predict(x0, steps, out_traj);

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"steps\":");
    try appendUint(&buf, gpa, steps);
    try buf.appendSlice(gpa, ",\"state_dim\":");
    try appendUint(&buf, gpa, state_dim);
    try buf.appendSlice(gpa, ",\"trajectory\":[");
    for (out_traj, 0..) |val, idx| {
        if (idx > 0) try buf.append(gpa, ',');
        try appendNum(&buf, gpa, val);
    }
    try buf.appendSlice(gpa, "]}");
    return buf.toOwnedSlice(gpa);
}

fn runKoopmanPredictCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8, steps: usize, basis_str: []const u8, ridge: f64) !void {
    const txt = koopmanPredictCore(io, gpa, data_path, steps, basis_str, ridge) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runKoopmanPredict(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const data_path = proto.argStr(args, "data", "");
    if (data_path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: data (ruta CSV) obligatoria.");
        return;
    }
    var steps: usize = 5;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("steps")) |v| {
                if (v == .integer) {
                    if (v.integer < 1 or v.integer > 1_000_000) {
                        try proto.sendToolError(out, id, "Invalid params: steps debe estar en [1, 1000000].");
                        return;
                    }
                    steps = @intCast(v.integer);
                }
            }
        }
    }
    const basis_str = proto.argStr(args, "basis", "poly2");
    var ridge: f64 = 1e-7;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("ridge")) |v| {
                if (v == .float) ridge = v.float;
                if (v == .integer) ridge = @floatFromInt(v.integer);
            }
        }
    }
    const txt = koopmanPredictCore(io, gpa, data_path, steps, basis_str, ridge) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
fn pdefindCore(io: Io, gpa: std.mem.Allocator, data_path: []const u8, dt: f64, dx: f64) ![]u8 {
    if (!(dt > 0.0) or !(dx > 0.0) or !std.math.isFinite(dt) or !std.math.isFinite(dx)) return error.ParametrosInvalidos;
    const content = try readTextFile(io, gpa, data_path);
    defer gpa.free(content);

    var rows: usize = 0;
    var cols: usize = 0;
    var data = std.ArrayList(f64).empty;
    defer data.deinit(gpa);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, ',');
        var row_vals: usize = 0;
        while (parts.next()) |p| {
            const pt = std.mem.trim(u8, p, " \t");
            if (pt.len == 0) continue;
            const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
            try data.append(gpa, v);
            row_vals += 1;
        }
        if (row_vals == 0) continue;
        if (cols == 0) cols = row_vals;
        if (row_vals != cols) return error.InvalidCharacter;
        rows += 1;
    }
    if (rows < 3 or cols < 5) return error.InvalidCharacter;

    const opts = ermc.solver.pdefind.PdeFindOptions{};
    var res = try ermc.solver.pdefind.findPde(gpa, data.items, rows, cols, dt, dx, opts);
    defer res.deinit();

    // build active terms JSON
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"equation\":\"");
    try escapeJson(res.equation, &buf, gpa);
    try buf.appendSlice(gpa, "\",\"r2\":");
    try appendNum(&buf, gpa, res.r2_score);
    try buf.appendSlice(gpa, ",\"mse\":");
    try appendNum(&buf, gpa, res.mse);
    try buf.appendSlice(gpa, ",\"n_samples\":");
    try appendUint(&buf, gpa, res.n_samples);
    try buf.appendSlice(gpa, ",\"active_terms\":[");
    for (res.active_terms, 0..) |term, i| {
        if (i > 0) try buf.append(gpa, ',');
        try buf.appendSlice(gpa, "{\"name\":\"");
        try escapeJson(term.name, &buf, gpa);
        try buf.appendSlice(gpa, "\",\"coef\":");
        try appendNum(&buf, gpa, term.coefficient);
        try buf.append(gpa, '}');
    }
    try buf.appendSlice(gpa, "]}");
    return buf.toOwnedSlice(gpa);
}

fn runPdefindCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, data_path: []const u8, dt: f64, dx: f64) !void {
    const txt = pdefindCore(io, gpa, data_path, dt, dx) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runPdefind(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const data_path = proto.argStr(args, "data", "");
    if (data_path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: data (ruta CSV) obligatoria.");
        return;
    }
    var dt: f64 = 1.0;
    var dx: f64 = 1.0;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("dt")) |v| {
                if (v == .float) dt = v.float;
                if (v == .integer) dt = @floatFromInt(v.integer);
            }
            if (a.object.get("dx")) |v| {
                if (v == .float) dx = v.float;
                if (v == .integer) dx = @floatFromInt(v.integer);
            }
        }
    }
    const txt = pdefindCore(io, gpa, data_path, dt, dx) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}
test "sequenceCore predicts square" {
    const gpa = std.testing.allocator;
    const txt = try sequenceCore(gpa, "0,1,4,9,16,25,36");
    defer gpa.free(txt);
    try std.testing.expect(std.mem.indexOf(u8, txt, "\"next\":") != null);
}

test "appendNum serializes non-finite as null" {
    const gpa = std.testing.allocator;
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(gpa);
    try appendNum(&buf, gpa, std.math.nan(f64));
    try buf.append(gpa, ',');
    try appendNum(&buf, gpa, std.math.inf(f64));
    try buf.append(gpa, ',');
    try appendNum(&buf, gpa, 1.5);
    try std.testing.expectEqualStrings("null,null,1.5", buf.items);
}

test "escapeJson escapes control chars and invalid utf8" {
    const gpa = std.testing.allocator;
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(gpa);
    try escapeJson("a\x01\"\\\n\xff", &buf, gpa);
    try std.testing.expectEqualStrings("a\\u0001\\\"\\\\\\n\\ufffd", buf.items);
}
fn koopmanLoadPredictCore(io: Io, gpa: std.mem.Allocator, path: []const u8, x0_str: []const u8, steps: usize) ![]u8 {
    const content = try readTextFile(io, gpa, path);
    defer gpa.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCharacter;
    const obj = parsed.value.object;

    const state_dim_v = obj.get("state_dim") orelse return error.InvalidCharacter;
    const lifted_dim_v = obj.get("lifted_dim") orelse return error.InvalidCharacter;
    const k_v = obj.get("K") orelse return error.InvalidCharacter;
    if (state_dim_v != .integer or lifted_dim_v != .integer or k_v != .array) return error.InvalidCharacter;
    if (state_dim_v.integer < 1 or lifted_dim_v.integer < 1) return error.InvalidCharacter;
    if (state_dim_v.integer > 4096 or lifted_dim_v.integer > 20000) return error.InvalidCharacter;
    const state_dim: usize = @intCast(state_dim_v.integer);
    const lifted_dim: usize = @intCast(lifted_dim_v.integer);
    const expected_k = std.math.mul(usize, lifted_dim, lifted_dim) catch return error.InvalidCharacter;
    if (k_v.array.items.len != expected_k) return error.InvalidCharacter;

    const basis_str = if (obj.get("basis")) |b| (if (b == .string) b.string else "poly2") else "poly2";
    const basis = parseBasis(basis_str) orelse return error.BasisInvalido;
    // El vector elevado debe tener exactamente la dimension del diccionario:
    // si no, liftState escribiria fuera del buffer en predict().
    if (lifted_dim != ermc.solver.koopman.computeLiftedDimension(state_dim, basis)) return error.ModeloInconsistente;

    const K = try gpa.alloc(f64, lifted_dim * lifted_dim);
    for (k_v.array.items, 0..) |item, i| {
        if (item == .float) K[i] = item.float else if (item == .integer) K[i] = @floatFromInt(item.integer) else return error.InvalidCharacter;
    }

    var model = ermc.solver.koopman.KoopmanModel{
        .allocator = gpa,
        .state_dim = state_dim,
        .lifted_dim = lifted_dim,
        .basis = basis,
        .K = K,
    };
    // Need own K; model.deinit frees K, so don't defer free K separately. But model is not pointer; deinit frees. We'll let model deinit at end.
    // However model is value; call predict then deinit.
    defer model.deinit();

    // parse x0
    var x0 = std.ArrayList(f64).empty;
    defer x0.deinit(gpa);
    var parts = std.mem.splitScalar(u8, x0_str, ',');
    while (parts.next()) |p| {
        const pt = std.mem.trim(u8, p, " \t");
        if (pt.len == 0) continue;
        const v = std.fmt.parseFloat(f64, pt) catch return error.InvalidCharacter;
        try x0.append(gpa, v);
    }
    if (x0.items.len != state_dim) return error.InvalidCharacter;

    const n_out = std.math.mul(usize, steps, state_dim) catch return error.ParametrosInvalidos;
    if (n_out > 50_000_000) return error.ParametrosInvalidos;
    const out_traj = try gpa.alloc(f64, n_out);
    defer gpa.free(out_traj);
    try model.predict(x0.items, steps, out_traj);

    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"steps\":");
    try appendUint(&buf, gpa, steps);
    try buf.appendSlice(gpa, ",\"state_dim\":");
    try appendUint(&buf, gpa, state_dim);
    try buf.appendSlice(gpa, ",\"trajectory\":[");
    for (out_traj, 0..) |val, idx| {
        if (idx > 0) try buf.append(gpa, ',');
        try appendNum(&buf, gpa, val);
    }
    try buf.appendSlice(gpa, "]}");
    return buf.toOwnedSlice(gpa);
}

fn runKoopmanLoadPredictCli(io: Io, out: *Io.Writer, err: *Io.Writer, gpa: std.mem.Allocator, path: []const u8, x0_str: []const u8, steps: usize) !void {
    const txt = koopmanLoadPredictCore(io, gpa, path, x0_str, steps) catch |e| {
        try err.print("Error: {s}\n", .{@errorName(e)});
        try err.flush();
        std.process.exit(2);
    };
    defer gpa.free(txt);
    try out.writeAll(txt);
    try out.writeAll("\n");
    try out.flush();
}

fn runKoopmanLoadPredict(io: Io, out: *Io.Writer, id: std.json.Value, gpa: std.mem.Allocator, args: ?std.json.Value) !void {
    const path = proto.argStr(args, "path", "");
    if (path.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: path obligatorio.");
        return;
    }
    const x0_str = proto.argStr(args, "x0", "");
    if (x0_str.len == 0) {
        try proto.sendToolError(out, id, "Invalid params: x0 (coma-sep) obligatorio.");
        return;
    }
    var steps: usize = 5;
    if (args) |a| {
        if (a == .object) {
            if (a.object.get("steps")) |v| {
                if (v == .integer) {
                    if (v.integer < 1 or v.integer > 1_000_000) {
                        try proto.sendToolError(out, id, "Invalid params: steps debe estar en [1, 1000000].");
                        return;
                    }
                    steps = @intCast(v.integer);
                }
            }
        }
    }
    const txt = koopmanLoadPredictCore(io, gpa, path, x0_str, steps) catch |e| {
        try proto.sendToolError(out, id, @errorName(e));
        return;
    };
    defer gpa.free(txt);
    try proto.sendToolText(out, id, txt);
}

test "parseSindyCsv soporta BOM, comentarios, cabecera y punto y coma" {
    const gpa = std.testing.allocator;
    const csv = "\xEF\xBB\xBF# comentario\nx0;y\n1;3\n2;5\n";
    var p = try parseSindyCsv(gpa, csv);
    defer p.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), p.n_inputs);
    try std.testing.expectEqual(@as(usize, 2), p.samples.items.len);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), p.samples.items[0].target, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), p.samples.items[1].inputs[0], 1e-12);
}

test "parseSindyCsv rechaza campo vacio y NaN" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.CampoVacio, parseSindyCsv(gpa, "1,,2\n"));
    try std.testing.expectError(error.ValorNoFinito, parseSindyCsv(gpa, "1,nan,2\n"));
}

test "parseTrajectoryCsv lee tiempo y estados" {
    const gpa = std.testing.allocator;
    var p = try parseTrajectoryCsv(gpa, "0,1,2\n0.1,1.1,2.1\n0.2,1.2,2.2\n");
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 2), p.n_dim);
    try std.testing.expectEqual(@as(usize, 3), p.states.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.2), p.states[2][0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), p.time[2], 1e-12);
}

test "parseTrajectoryCsv descarta cabecera con campos numericos" {
    const gpa = std.testing.allocator;
    var p = try parseTrajectoryCsv(gpa, "time,2\n0,3\n1,4\n");
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 1), p.n_dim);
    try std.testing.expectEqual(@as(usize, 2), p.states.len);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), p.states[1][0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), p.time[1], 1e-12);
}

test "parseActivationList acepta alias y rechaza desconocidos" {
    const gpa = std.testing.allocator;
    var acts = std.ArrayList(ermc.Activation).empty;
    defer acts.deinit(gpa);
    try parseActivationList(gpa, "id,poly2", &acts);
    try std.testing.expectEqual(@as(usize, 2), acts.items.len);
    try std.testing.expectEqual(ermc.Activation.Square, acts.items[1]);

    var acts2 = std.ArrayList(ermc.Activation).empty;
    defer acts2.deinit(gpa);
    try std.testing.expectError(error.InvalidCharacter, parseActivationList(gpa, "id,nope", &acts2));
}

test "estimateDictionaryTerms y cota del diccionario" {
    try std.testing.expectEqual(@as(u64, 131), estimateDictionaryTerms(5, 1, true));
    try std.testing.expectEqual(@as(u64, 11), estimateDictionaryTerms(5, 1, false));
    try std.testing.expectEqual(@as(u64, 1526), estimateDictionaryTerms(5, 4, true));

    var big = [_]ermc.Activation{ .Sine, .Square, .Exp, .Cube };
    try std.testing.expectError(error.DiccionarioDemasiadoGrande, dictionaryTermGuard(5, &big, true));
    var small = [_]ermc.Activation{.Square};
    try dictionaryTermGuard(5, &small, true);
}

test "loadSindyModel estatico y dinamico" {
    const gpa = std.testing.allocator;
    {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"kind\":\"static\",\"n_inputs\":2,\"activations\":\"id,sqr\",\"interactions\":false,\"weights\":[1.0,2.0,3.0]}", .{});
        defer parsed.deinit();
        var m = try loadSindyModel(gpa, parsed.value);
        defer m.deinit();
        try std.testing.expectEqual(SindyModelKind.static, m.kind);
        try std.testing.expectEqual(@as(usize, 2), m.n_inputs);
        try std.testing.expectEqual(@as(usize, 3), m.static_weights.len);
        try std.testing.expectApproxEqAbs(@as(f64, 2.0), m.static_weights[1], 1e-12);
    }
    {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"kind\":\"dynamical\",\"n_inputs\":2,\"activations\":\"id\",\"interactions\":true,\"equations\":[{\"weights\":[1,2,3]},{\"weights\":[4,5,6]}]}", .{});
        defer parsed.deinit();
        var m = try loadSindyModel(gpa, parsed.value);
        defer m.deinit();
        try std.testing.expectEqual(SindyModelKind.dynamical, m.kind);
        try std.testing.expectEqual(@as(usize, 2), m.dim);
        try std.testing.expectApproxEqAbs(@as(f64, 6.0), m.dyn_weights[1][2], 1e-12);
    }
}

test "loadSindyModel rechaza modelo invalido" {
    const gpa = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"n_inputs\":0,\"activations\":\"id\",\"weights\":[]}", .{});
    defer parsed.deinit();
    try std.testing.expectError(error.ModelInvalido, loadSindyModel(gpa, parsed.value));
}

test "parseInputRows lee filas y cabecera" {
    const gpa = std.testing.allocator;
    var rows = try parseInputRows(gpa, "x0;x1\n1;2\n3;4\n");
    defer rows.deinit();
    try std.testing.expectEqual(@as(usize, 2), rows.n_inputs);
    try std.testing.expectEqual(@as(usize, 2), rows.rows.len);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), rows.rows[1][0], 1e-12);
}

test "parseOneRow acepta coma y rechaza vacio" {
    const gpa = std.testing.allocator;
    const row = try parseOneRow(gpa, "1.5, -2, 3");
    defer gpa.free(row);
    try std.testing.expectEqual(@as(usize, 3), row.len);
    try std.testing.expectApproxEqAbs(@as(f64, -2.0), row[1], 1e-12);
    try std.testing.expectError(error.CampoVacio, parseOneRow(gpa, ""));
}
