// Textos de ayuda y uso CLI (fuente unica: los comparten la herramienta MCP
// `sys_help` y el CLI `--help-topic`).
// Regla: ninguna rama supera ~500 tokens; `all` es indice, no manual.
// La version sale de `registro.zig` (fuente unica).

const std = @import("std");
const registro = @import("registro.zig");

// ---------- Contrato de ayuda (comun a todos los MCP) ----------
// `--help` sin tema: USAGE_CLI. `--help <tema>` / `--help-topic <tema>` /
// `help <tema>`: bloque Markdown del tema. `all` es el indice.
pub const TOPICS = "all|exec|fs|sys|read|write|edit|list|search|rm|mv|cp|mkdir|info|env";

pub fn topicMd(topic: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, topic, "all")) return HELP_ALL;
    if (std.mem.eql(u8, topic, "exec")) return HELP_EXEC;
    if (std.mem.eql(u8, topic, "fs") or std.mem.eql(u8, topic, "read") or
        std.mem.eql(u8, topic, "write") or std.mem.eql(u8, topic, "edit") or
        std.mem.eql(u8, topic, "list") or std.mem.eql(u8, topic, "search")) return HELP_FS;
    if (std.mem.eql(u8, topic, "sys") or std.mem.eql(u8, topic, "rm") or
        std.mem.eql(u8, topic, "mv") or std.mem.eql(u8, topic, "cp") or
        std.mem.eql(u8, topic, "mkdir") or std.mem.eql(u8, topic, "info") or
        std.mem.eql(u8, topic, "env")) return HELP_SYS;
    return null;
}

/// Sugerencia barata para `argumento desconocido`: prefijo comun mas largo
/// (ignora los guiones iniciales; exige >=2 caracteres utiles).
pub fn sugerir(arg: []const u8, flags: []const []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, arg, "help") != null) return "--help";
    const a = if (std.mem.startsWith(u8, arg, "--")) arg[2..] else arg;
    if (a.len == 0) return null;
    var best: ?[]const u8 = null;
    var best_len: usize = 0;
    for (flags) |f| {
        const b = if (std.mem.startsWith(u8, f, "--")) f[2..] else f;
        if (b.len == 0) continue;
        var n: usize = 0;
        while (n < a.len and n < b.len and a[n] == b[n]) : (n += 1) {}
        if (n >= 2 and n > best_len) {
            best_len = n;
            best = f;
        }
    }
    return best;
}

// ---------- Seccion 7: ayuda en Markdown ----------

pub const HELP_ALL =
    "\\# Servidor MCP de Sistema (sys v" ++ registro.VERSION ++ ")\n" ++
    \\
    \\Control total del SO: ejecuta comandos, lee/escribe/edita archivos,
    \\busca texto en cualquier archivo o árbol y gestiona carpetas.
    \\Zig sin dependencias, 1 proceso por llamada.
    \\
    \\## Herramientas
    \\
    \\| Herramienta | Para que sirve | Parametros |
    \\|---|---|---|
    \\| `exec` | Ejecuta un comando shell con timeout | `cmd`, `cwd`, `timeout_ms`, `max_bytes`, `encoding`, `base64`, `force` |
    \\| `job` | Comandos en fondo (no bloquean) | `op`, `cmd`, `job`, `cwd`, `timeout_ms`, `max_bytes`, `lines`, `encoding`, `base64`, `force` |
    \\| `read` | Lee archivo por lineas (paginado) | `path`, `offset`, `limit`, `max_bytes`, `numbers` |
    \\| `write` | Crea/sobrescribe/agrega archivo | `path`, `content`, `mode` |
    \\| `edit` | Cambia/inserta/borra sin reescribir | `path`, `mode`, `old`, `new`, `occ`, `unique`, `regex`, `at`, `del` |
    \\| `search` | Busca texto o nombres (archivo o árbol) | `pattern`, `path`, `mode`, `recursive`, `glob`, `max`, `case`, `context`, `word`, `regex`, `exclude` |
    \\| `list` | Lista carpeta con filtro glob | `path`, `pattern`, `max`, `recursive`, `depth`, `exclude` |
    \\| `sys` | Info, env, stat, mkdir, rm, mv, cp | `op`, `path`, `dest`, `name`, `filter` |
    \\| `sys_help` | Esta ayuda en Markdown | `topic: all\|exec\|fs\|sys` |
    \\
    \\## Uso rapido
    \\
    \\- Buscar: `{"name":"search","arguments":{"pattern":"timeout","glob":"*.zig"}}`
    \\- Leer: `{"name":"read","arguments":{"path":"nota.txt"}}`
    \\- Cambiar 2ª ocurrencia: `{"name":"edit","arguments":{"path":"a.txt","old":"x","new":"y","occ":2}}`
    \\- Fondo: `{"name":"job","arguments":{"op":"start","cmd":"make -j4"}}`
    \\- Respuestas chicas: `read`/`list`/`search` paginan; `edit` evita reescribir todo.
    \\
    \\## Ejemplo JSON-RPC (tools/call)
    \\
    \\```json
    \\{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"exec","arguments":{"cmd":"echo hola"}}}
    \\```
    \\
    \\## Notas
    \\
    \\- `rm` borra recursivo pero rechaza raices (`/`, `C:\`) y rutas con `..`.
    \\- `write` con `mode=create` falla si existe (no pisa sin aviso).
    \\- Sin red; errores con `isError` y tip accionable.
    ;

pub const HELP_EXEC =
    \\# Herramienta `exec`
    \\
    \\Ejecuta un comando del shell (`cmd` por stdin en Windows, `sh -c` en Unix)
    \\con timeout y tope de salida. Comillas, `&`, `()` y `|` funcionan tal cual.
    \\
    \\Ojo: en Windows es **`cmd.exe`, no PowerShell** (`Remove-Item`,
    \\`Get-ChildItem`, etc. no existen ahí). Usa
    \\`powershell -NoProfile -Command "..."` o `-File`. En Unix, `sh -c`.
    \\
    \\## Parametros
    \\
    \\- `cmd` (texto, obligatorio, max 4000): ej. `echo hola`, `netstat -ano`, `for %i in (*) do @echo %i`.
    \\- `cwd` (opcional, se valida que exista). `timeout_ms` (def. 8000, 100-120000; más: usa `job`).
    \\- `max_bytes` (def. 4096, 512-8192 por flujo): RECORTA con `truncated:true`, no aborta.
    \\- `encoding` (def. `auto`): `auto` (UTF-8, si no OEM→UTF-8) | `utf8` (estricto) | `oem` | `raw`. Responde `encoding`.
    \\- `base64`: salida en base64 (binarios). `force`: confirma comando destructivo (denylist).
    \\
    \\## Que devuelve
    \\
    \\```json
    \\{"exit":0,"stdout":"hola\n","stderr":"","truncated":false,"timed_out":false,"encoding":"utf8"}
    \\```
    \\
    \\En timeout: `exit:null` + `timed_out:true` + salida parcial. `exit` sigue convención POSIX.
    \\
    \\## Errores
    \\
    \\- Sin `cmd` o muy largo -> error de params. Destructivo sin `force` -> bloqueado.
    \\- `cwd` inexistente -> error claro. No interactivo: usa comandos que terminen solos.
    \\
    \\## Ejemplos copiables
    \\
    \\```json
    \\{"name": "exec", "arguments": {"cmd": "echo hola"}}
    \\{"name": "exec", "arguments": {"cmd": "netstat -ano", "max_bytes": 8192}}
    \\{"name": "exec", "arguments": {"cmd": "certutil -encode f.bin", "base64": true}}
    \\```
    \\
    \\## Fondo: `job` (no bloquea al worker)
    \\
    \\- `start` (`cmd` oblig., `cwd`, `timeout_ms` 1000-3600000, def. 300000): devuelve `{"job","pid","timeout_ms","dir"}` al instante.
    \\- `poll` (`job`, `max_bytes`, `lines` últimas N, `encoding`, `base64`): `{"job","running","exit","elapsed_ms","timed_out","killed","note","out","err","encoding"}` (colas de log).
    \\- `kill` (`job`): mata e informa; `list`: todos; `forget` (`job`): borra sus logs.
    \\- El timeout se aplica en `poll` (mata si excede). Un `exit` del usuario omite el código (`exit:null` + nota).
    \\
    \\```json
    \\{"name": "job", "arguments": {"op": "start", "cmd": "make -j4"}}
    \\{"name": "job", "arguments": {"op": "poll", "job": "122806213-0"}}
    \\```
;

pub const HELP_FS =
    \\# Archivos: `read`, `write`, `edit`, `list`, `search`
    \\
    \\## `read`: lee por lineas (paginado)
    \\
    \\- `path` (obligatorio), `offset` (def. 0), `limit` (def. 100, max 1000), `max_bytes` (def. 4096, max 8192).
    \\- `numbers` (def. true): `N: texto` (N absoluta).
    \\- Devuelve `{"path","offset","limit","total","returned","truncated","text"}`.
    \\
    \\## `write`: crea o modifica (hasta 100KB)
    \\
    \\- `path` + `content` (obligatorios), `mode`: `overwrite` (def.) | `create` (falla si existe) | `append` (pega bytes crudos: incluye tu propio `\n` para no unir lineas).
    \\- Crea carpetas padre solas. Devuelve `{"path","bytes","mode"}`.
    \\- Más de ~30KB (límite Windows): parte en `create` + `append`s.
    \\
    \\## `edit`: cambia/inserta/borra sin reescribir (`mode`)
    \\
    \\- `sub` (def.): `old`→`new` (primero; `replace_all`=todos; `occ`=N-ésimo; `unique`=falla si varios). Sin match reintenta sin espacios (si varias líneas, pide precisar).
    \\- `regex` (def. false): con `sub`, `old` es una expresión regular y `new` expande `$0`..`$20` (ej. `$2-$1`) y grupos con nombre (`(?P<n>...)`/`(?<n>...)` -> `$nombre`/`${nombre}`); lookaround `(?=) (?!)(?<=)(?<!)` (lookbehind de longitud acotada: `(?<=ab)`, `(?<=a{1,3})`; no `(?<=a+)`); con `del`, `del` es un patrón (borra líneas que casan); con `ins`, `old` es un patrón (inserta `new` antes de cada línea que casa). `^`/`$` son anclas de línea. Sin tolerancias.
    \\- `ins`: inserta `new` en línea `at` (`total+1` = final). `del`: borra `del` (`5` o `2-8`).
    \\- Devuelve `{"path","replaced","total","bytes"}`.
    \\
    \\## `list`: carpeta ordenada
    \\
    \\- `path` (def. `.`), `pattern` (glob `*`/`?`, ej. `*.zig`; o regex si `regex=true`), `regex` (def. false), `max` (def. 50, max 1000).
    \\- `recursive` recorre el árbol (`depth` 0-10, def. 3); `exclude` filtra.
    \\- Devuelve `{"path","total","truncated","entries":[{"name","kind","size"}]}`.
    \\
    \\## `search`: busca texto en archivo o árbol
    \\
    \\- `pattern` (oblig.), `path` (def. `.`), `recursive` (def. true), `glob` (ej. `*.zig`).
    \\- `max` (def. 50, max 500), `case` (def. false), `context` (0-5), `word`, `exclude` (globs con comas).
    \\- `regex` (def. false): `pattern` es una expresión regular (`. [] () | * + ? {} ^ $ \d \w \s`), insensible a mayúsculas por defecto. Captura con `(...)` (o con nombre `(?P<n>...)`/`(?<n>...)`); lookaround `(?=) (?!)(?<=)(?<!)`; flags inline `(?i)(?s)(?m)`. Motor propio sin ReDoS; devuelve `match` (texto exacto encontrado).
    \\- Omite ocultos, `zig-out`, `node_modules`, `target`, `__pycache__`, >1MB. `skipped` los cuenta (+archivos con líneas ilegibles, que sí aportan matches).
    \\- `mode` = `files`: busca por NOMBRE (basename) o ruta relativa a `path` con el mismo `pattern`/`regex`/`case`/`glob`, en vez de por contenido. Devuelve `entries:[{"name","kind","size"}]`.
    \\- Multi-match: reporta cada ocurrencia por línea (no solo la primera); `total` cuenta ocurrencias y cada match trae `col` (1-based, byte del inicio).
    \\- Devuelve `{"path","pattern","regex","total","skipped","truncated","matches":[{"file","line","col","text","match"}]}`.
    \\
    \\## Ejemplos copiables
    \\
    \\```json
    \\{"name": "search", "arguments": {"pattern": "timeout", "glob": "*.zig"}}
    \\{"name": "edit", "arguments": {"path": "a.txt", "old": "x", "new": "y", "occ": 2}}
    \\{"name": "edit", "arguments": {"path": "a.txt", "mode": "del", "del": "2-8"}}
    \\```
;

pub const HELP_SYS =
    \\# Herramienta `sys`: sistema y operaciones
    \\
    \\Un `op` por llamada. Params segun `op`: `path`, `dest`, `name`, `filter`,
    \\`pattern`, `glob`, `regex`, `subst`, `dry_run`, `max`, `force`.
    \\
    \\## Ops de lectura
    \\
    \\- `info`: `{"os","arch","zig"}` (SO, arquitectura, version Zig).
    \\- `env_get` (+`name`): `{"name","value"}`. Sin `name` o inexistente -> error.
    \\- `env_list` (+`filter` substring, max 200 vars): `{"filter","count","truncated","vars"}`.
    \\- `stat` (+`path`): `{"path","kind":"file|dir|otro","size"}`.
    \\
    \\## Ops de escritura
    \\
    \\- `mkdir` (+`path`): crea padres.
    \\- `rm` (+`path`): borra archivo o arbol (rechaza `/`, `C:\`, `..`).
    \\  En lote (1 llamada): `path`=carpeta + `pattern` (glob) o `glob` + `regex:true`,
    \\  con `max` (def. 200) y `dry_run` opcionales. El guard se aplica por archivo.
    \\- `mv` (+`path` origen, +`dest`): renombra/mueve (ambas absolutas o ambas relativas).
    \\  En lote: `path`=carpeta + `pattern`/`glob` (+`regex`) + `dest` (carpeta existente)
    \\  y/o `subst` (reemplazo regex `$1..$N`), `max`, `dry_run`, `force`.
    \\  Sin `force`, si el destino existe aborta antes de mover.
    \\- `cp` (+`path`, +`dest`): copia archivo (no carpetas; para carpetas usa `exec`: `xcopy`/`cp -r`).
    \\
    \\## Procesos (via `exec`, no `sys`)
    \\
    \\- Windows: `tasklist`, `taskkill /PID 1234 /F`. Unix: `ps aux`, `kill 1234`.
    \\
    \\## Ejemplos copiables
    \\
    \\```json
    \\{"name": "sys", "arguments": {"op": "info"}}
    \\{"name": "sys", "arguments": {"op": "env_get", "name": "PATH"}}
    \\{"name": "sys", "arguments": {"op": "mkdir", "path": "tmp/datos"}}
    \\{"name": "sys", "arguments": {"op": "mv", "path": "a.txt", "dest": "b.txt"}}
    \\{"name": "sys", "arguments": {"op": "rm", "path": "tmp", "glob": "*.tmp", "dry_run": true}}
    \\{"name": "sys", "arguments": {"op": "rm", "path": "tmp", "pattern": "^tmp_\\d+", "regex": true}}
    \\{"name": "sys", "arguments": {"op": "mv", "path": "fotos", "pattern": "^img_(\\d+)\\.jpg$", "regex": true, "subst": "$1-photo.jpg", "dry_run": true}}
    \\```
;

pub const USAGE_CLI =
    \\Uso: sys [opciones] (`--flag=valor` vale igual; `--` escapa el próximo valor)
    \\     sys --help [tema]      Ayuda general o de un tema
    \\     sys --version          Version
    \\     sys --registro         Manifiesto JSON firmado
    \\
    \\Temas: all|exec|fs|sys|read|write|edit|list|search|rm|mv|cp|mkdir|info|env
    \\  sys --help <tema>   (equivale a --help-topic <tema>; all = indice)
    \\
    \\  --exec CMD [--cwd D] [--timeout MS] [--max N] [--encoding E] [--base64] [--force]
    \\    CMD="-" lee de stdin; --cmd-file F lee el comando de un archivo
    \\  --job OP [--exec CMD | --job-id J] [--cwd D] [--timeout MS] [--max N] [--lines N] [--encoding E] [--base64] [--force] [--encoding E] [--base64] [--force]
    \\    OP: start|poll|kill|list|forget
    \\  --read PATH [--offset N] [--limit N] [--max N]
    \\  --write PATH --content S [--mode create|overwrite|append]
    \\  --edit PATH [--mode sub|ins|del] [--old S --new S [--all|--occ N]] [--regex]
    \\    [--at N --new S | --del N|A-B]
    \\  --list [PATH] [--pattern G] [--regex] [--max N] [--recursive [--depth D] [--exclude G]]
    \\  --search PATTERN [--path P] [--no-recursive] [--glob G] [--max N] [--case]
    \\    [--word] [--context N] [--exclude G] [--regex] [--files|--mode files|content]
    \\    (--regex: PATTERN es expresion regular . [] () | * + ? {} ^ $ \d \w \s)
    \\    (--files / --mode files: busca por nombre/ruta en vez de por contenido)
    \\  --sys OP [--path P] [--dest D] [--name N] [--filter F]
    \\    [--pattern P|--glob G] [--regex] [--subst S] [--dry-run] [--max N] [--force]
    \\    OP: info|env_get|env_list|stat|mkdir|rm|mv|cp
    \\    rm/mv en lote: --path CARPETA + --pattern/--glob (+--regex) [--dest CARPETA]
    \\  --help-topic T   all|exec|fs|sys : imprime la ayuda y sale
    \\  --help [T], -h   Ayuda general o del tema T (ej. `sys --help rm`)
    \\  --version, -V    Version del binario
    \\  --registro       Manifiesto JSON firmado
    \\
    \\CLI <-> MCP (mismos datos, distinto nombre):
    \\  --files              -> mode:"files"
    \\  --pattern / --glob   -> pattern / glob (+ regex:true si --regex)
    \\  --dry-run            -> dry_run
    \\  --max                -> max
    \\  --subst              -> subst (mv; exige regex)
    \\  --dest               -> dest (mv/cp)
    \\  --force              -> force
    \\
    \\Nota: el shell descarta "" vacíos; para contenido vacío usa la vía MCP.
    \\
    \\Ejemplos:
    \\  sys --exec "echo hola"
    \\  sys --read nota.txt --limit 50
    \\  sys --write nuevo.txt --content hola --mode create
    \\  sys --edit a.txt --old x --new y --occ 2
    \\  sys --edit a.txt --mode del --del 2-8
    \\  sys --search timeout --glob *.zig
    \\  sys --search "\d+ms" --regex
    \\  sys --search "\.zig$" --regex --files
    \\  sys --edit a.txt --old "(\w+)=(\w+)" --new "$2=$1" --regex --all
    \\  sys --edit a.txt --mode del --del "^\s*#" --regex
    \\  sys --edit a.txt --mode ins --old "^import" --new "// import" --regex
    \\  sys --list . --pattern *.zig
    \\  sys --sys rm --path tmp --glob "*.tmp" --dry-run
    \\  sys --sys rm --path tmp --pattern "^tmp_\d+" --regex
    \\  sys --sys mv --path fotos --pattern "^img_(\d+)\.jpg$" --regex --subst "$1-photo.jpg" --dry-run
    \\  sys --sys info
    \\  sys --help-topic fs
;
