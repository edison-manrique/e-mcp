#!/bin/sh
# Pruebas Unix (Linux/macOS) para `sys`: CLI + MCP + tree-kill.
# Uso:  sh unix.sh /ruta/al/sys      (o SYS=/ruta/al/sys sh unix.sh)
# POSIX sh (probado en Alpine/musl con busybox ash). Escribe PASS/FAIL a
# stdout y un resumen final; todo va acotado por `timeout` (nunca cuelga).
#
# Temporales en RAM: si no hay TMPDIR y existe /dev/shm (tmpfs), se usa
# para no escribir en el SSD. Como el tool (auditoria y jobs) tambien
# respeta TMPDIR, sus temporales van a memoria igual. El harness borra su
# carpeta al terminar (rm -rf "$WORK").
if [ -z "$TMPDIR" ] && [ -d /dev/shm ] && [ -w /dev/shm ]; then
  TMPDIR=/dev/shm; export TMPDIR
fi
# El tool prioriza SYS_TMPDIR: lo fijamos a la misma base (RAM). La
# auditoria esta OFF por defecto, asi que la activamos (el harness la prueba).
SYS_TMPDIR="$TMPDIR"; export SYS_TMPDIR
SYS_AUDIT=1; export SYS_AUDIT

SYS="${1:-${SYS:-/tmp/sys/sys}}"
if [ ! -x "$SYS" ]; then echo "No ejecutable: $SYS"; exit 1; fi

WORK="$(mktemp -d 2>/dev/null || { d="${TMPDIR:-/tmp}/sys-uc.$$"; mkdir -p "$d"; echo "$d"; })"
cd "$WORK" || exit 1

pass=0; fail=0
ok() { pass=$((pass+1)); echo "PASS  $1"; }
no() { fail=$((fail+1)); echo "FAIL  $1"; }
chk() { # desc, esperado, real
  if [ "x$2" = "x$3" ]; then ok "$1"; else no "$1 :: esperado=[$2] real=[$3]"; fi
}
has() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
chkh() { if has "$1" "$2"; then ok "$3"; else no "$3 :: no contiene [$1] en [$2]"; fi; }
chknh() { if has "$1" "$2"; then no "$3 :: NO debia contener [$1] en [$2]"; else ok "$3"; fi; }

OUT=""; RC=0
run() { T="$1"; shift; OUT="$(timeout "$T" "$@" 2>&1)"; RC=$?; }

echo "=== sys Unix: $SYS ==="
echo "workdir: $WORK"

# ------------------------------------------------------------------ 1. basico
echo "--- 1. basico ---"
run 10 "$SYS" --help;                        chkh "Uso: sys" "$OUT" "help muestra uso"
run 10 "$SYS" --sys info;                    chkh '"os":"linux"' "$OUT" "sys info: os linux"
run 10 "$SYS" --sys info;                    chkh '"arch":"x86_64"' "$OUT" "sys info: arch x86_64"
run 10 "$SYS" --help-topic fs;               chkh "write" "$OUT" "help-topic fs"

# ------------------------------------------------------------------ 2. exec
echo "--- 2. exec ---"
run 10 "$SYS" --exec "echo AAA; echo BBB";   chkh 'AAA\nBBB' "$OUT" "exec: dos lineas"
run 10 "$SYS" --exec "printf XYZ";           chkh '"stdout":"XYZ"' "$OUT" "exec: sin newline final"
run 10 "$SYS" --exec "exit 7";               chkh '"exit":7' "$OUT" "exec: propaga exit 7"
run 10 "$SYS" --exec "echo eee 1>&2";        chkh '"stderr":"eee' "$OUT" "exec: captura stderr"
run 10 "$SYS" --exec "echo out; echo err 1>&2"; chkh '"stdout":"out' "$OUT" "exec: separa stdout/stderr"
run 10 "$SYS" --exec "pwd";                  chkh "$WORK" "$OUT" "exec: hereda cwd"
run 10 "$SYS" --exec "pwd" --cwd /etc;       chkh '"stdout":"/etc' "$OUT" "exec: --cwd /etc"
run 12 "$SYS" --exec "sleep 30" --timeout 900; chkh '"timed_out":true' "$OUT" "exec: timeout corta"
run 12 "$SYS" --exec "seq 1 200" --max 512;  chkh '"truncated":true' "$OUT" "exec: max recorta"

# ------------------------------------------------------------------ 3. fs
echo "--- 3. archivos ---"
run 10 "$SYS" --write a.txt --content hola --mode create; chkh '"mode":"create"' "$OUT" "write: create"
run 10 "$SYS" --write a.txt --content x --mode create;     chkh 'Ya existe' "$OUT" "write: create existente falla"
run 10 "$SYS" --write a.txt --content "-mas" --mode append; chkh '"mode":"append"' "$OUT" "write: append"
run 10 "$SYS" --read a.txt;               chkh 'hola-mas' "$OUT" "read: contiene lo escrito+append"
# --- append concurrente al MISMO archivo: lock + pwrite => sin lost updates ---
: > conc.txt
i=0
while [ $i -lt 24 ]; do
  tok="T$(printf '%02d' "$i")_ABCDEFGH"
  "$SYS" --write conc.txt --content "$tok" --mode append >/dev/null 2>&1 &
  i=$((i+1))
done
wait
n1=$(grep -o 'T[0-9][0-9]_ABCDEFGH' conc.txt | sort | uniq -c | awk '$1==1{c++} END{print c+0}')
nall=$(grep -o 'T[0-9][0-9]_ABCDEFGH' conc.txt | wc -l | tr -d ' ')
sz=$(wc -c < conc.txt | tr -d ' ')
chk "append concurrente 24x: cada token 1 vez (sin lost update)" "24" "$n1"
chk "append concurrente 24x: 24 tokens presentes" "24" "$nall"
chk "append concurrente 24x: longitud exacta (24*12)" "288" "$sz"
run 10 "$SYS" --write via.txt --content x --mode append; chkh '"via":"append"' "$OUT" "append: avisa via=append (O_APPEND real)"
# --- append + overwrite concurrentes: el SO anexa (O_APPEND) => sin entrelazado ---
: > mix.txt
i=0
while [ $i -lt 16 ]; do
  tok="A$(printf '%02d' "$i")_ZZZZZZZZ"   # 12 bytes
  "$SYS" --write mix.txt --content "$tok" --mode append >/dev/null 2>&1 &
  i=$((i+1))
done
i=0
while [ $i -lt 8 ]; do
  tok="O$(printf '%02d' "$i")_ZZZZZZZZ"
  "$SYS" --write mix.txt --content "$tok" --mode overwrite >/dev/null 2>&1 &
  i=$((i+1))
done
wait
msz=$(wc -c < mix.txt | tr -d ' ')
mmod=$((msz % 12))
mbad=$(fold -w 12 mix.txt | grep -cv '^[AO][0-9][0-9]_ZZZZZZZZ$')
mdup=$(fold -w 12 mix.txt | sort | uniq -d | wc -l | tr -d ' ')
chk "append+overwrite 16+8: longitud multiplo de 12 (sin partidos)" "0" "$mmod"
chk "append+overwrite 16+8: registros integros (sin entrelazado)" "0" "$mbad"
chk "append+overwrite 16+8: sin registros duplicados" "0" "$mdup"
# --- append a archivo de solo lectura: funciona (degrada a reemplazo) ---
echo -n base > ro.txt; chmod 444 ro.txt
run 10 "$SYS" --write ro.txt --content -mas --mode append; chk "append read-only: exit 0" 0 "$RC"
chk "append read-only: contenido correcto (base-mas)" "base-mas" "$(cat ro.txt)"
chmod 644 ro.txt
run 10 "$SYS" --write multi.txt --content "$(printf 'uno\ndos\ntres')"; chkh '"bytes":12' "$OUT" "write: multilinea"
run 10 "$SYS" --edit multi.txt --old dos --new DOS;    chkh '"replaced":1' "$OUT" "edit: sub"
run 10 "$SYS" --read multi.txt;           chkh 'DOS' "$OUT" "edit: sub aplicado"
run 10 "$SYS" --edit multi.txt --mode ins --at 2 --new intercalado; chkh '"replaced":1' "$OUT" "edit: ins"
run 10 "$SYS" --read multi.txt;           chkh 'intercalado' "$OUT" "edit: ins aplicado"
run 10 "$SYS" --edit multi.txt --mode del --del 3; chkh '"replaced":1' "$OUT" "edit: del"
run 10 "$SYS" --read multi.txt --limit 1; chkh '"returned":1' "$OUT" "read: limit"
run 10 "$SYS" --list . --pattern "*.txt"; chkh 'multi.txt' "$OUT" "list: pattern"
run 10 "$SYS" --search intercalado --path . ; chkh 'multi.txt' "$OUT" "search: encuentra"
run 10 "$SYS" --search 'inter\w+' --regex --path .; chkh 'intercalado' "$OUT" "search --regex: \\w+ y match exacto"
run 10 "$SYS" --search '^uno$' --regex --path .; chkh '"match":"uno"' "$OUT" "search --regex: anclas ^ \$"
run 10 "$SYS" --search '\bmas\b' --regex --path .; chkh 'hola-mas' "$OUT" "search --regex: \\b bordes de palabra"
run 10 "$SYS" --search 'inter(calado|rupto)' --regex --path .; chkh 'intercalado' "$OUT" "search --regex: grupo + alternancia"
run 10 "$SYS" --search 'INTERCALADO' --regex --path .; chkh 'intercalado' "$OUT" "search --regex: CI por defecto"
run 10 "$SYS" --search 'a' --glob 'multi.txt' --path .; chkh '"total":2' "$OUT" "search: multi-match (2 en 1 linea)"; chkh '"col":7' "$OUT" "search: col del 1er match"
run 10 "$SYS" --search '(abc' --regex --path .; chk "search --regex: error exit 2" 2 "$RC"; chkh 'sin cerrar' "$OUT" "search --regex: error claro"
# --- edit con regex (captura $n, occ, unique, anclas) ---
printf 'name=ana\nid=4501\nname=bob\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '(\w+)=(\w+)' --new '$2=$1' --regex --all; chkh '"replaced":3' "$OUT" "edit --regex: swap \$2=\$1"
run 10 "$SYS" --read rx.txt; chkh 'ana=name' "$OUT" "edit --regex: reemplazo aplicado"
printf 'foo=1\nbar=2\nFOO=3\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '^foo=' --new 'X_' --regex; chkh '"replaced":1' "$OUT" "edit --regex: ancla ^ (sensible)"
printf 'foo=1\nbar=2\nFOO=3\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '(?i)^foo=' --new 'Y_' --regex; chkh '"total":2' "$OUT" "edit --regex: (?i) inline (2 hay)"
printf 'a=1\nb=2\nc=3\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '=([0-9])' --new '=<${1}>' --regex --occ 2; chkh '"replaced":1' "$OUT" "edit --regex: --occ 2"
run 10 "$SYS" --read rx.txt; chkh 'b=<2>' "$OUT" "edit --regex: occ aplicado"
run 10 "$SYS" --edit rx.txt --old '\w+' --new x --regex --unique; chk "edit --regex: --unique con varios" 2 "$RC"; chkh 'nico' "$OUT" "edit --regex: --unique mensaje"
run 10 "$SYS" --edit rx.txt --old '(' --new x --regex; chk "edit --regex: error exit 2" 2 "$RC"; chkh 'sin cerrar' "$OUT" "edit --regex: error claro"
printf 'abcdefghijkl\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)' --new '$12$1' --regex --all; chkh '"replaced":1' "$OUT" "edit --regex: \$12 grupo 12"
run 10 "$SYS" --read rx.txt; chkh 'la' "$OUT" "edit --regex: \$12 -> la"
printf 'name=ana\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '(?P<k>\w+)=(?<v>\w+)' --new '$v=$k' --regex; chkh '"replaced":1' "$OUT" "edit --regex: grupos con nombre"
run 10 "$SYS" --read rx.txt; chkh 'ana=name' "$OUT" "edit --regex: \$v=\$k aplicado"
printf '10px 20em\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '\d+(?=px)' --new N --regex; chkh '"replaced":1' "$OUT" "edit --regex: lookahead (?=px)"
run 10 "$SYS" --read rx.txt; chkh 'Npx 20em' "$OUT" "edit --regex: lookahead aplicado"
printf 'keep\nDROP 1\ndrop 2\nkeep2\n' > rx.txt
run 10 "$SYS" --edit rx.txt --mode del --del '^DROP' --regex; chkh '"replaced":1' "$OUT" "edit del --regex: borra lineas"
run 10 "$SYS" --read rx.txt; chkh '"total":3' "$OUT" "edit del --regex: quedan 3"
printf 'a\nMARK\nb\n' > rx.txt
run 10 "$SYS" --edit rx.txt --mode ins --old '^MARK' --new '#' --regex; chkh '"replaced":1' "$OUT" "edit ins --regex: inserta"
run 10 "$SYS" --read rx.txt; chkh '2: #' "$OUT" "edit ins --regex: antes del match"
# --- lookbehind de longitud variable + preservacion del EOL (CRLF) ---
printf '12px 345px\n' > rx.txt
run 10 "$SYS" --edit rx.txt --old '(?<=\d{2,3})px' --new Q --regex --all; chkh '"replaced":2' "$OUT" "edit --regex: lookbehind variable (\\d{2,3})"
run 10 "$SYS" --read rx.txt; chkh '345Q' "$OUT" "edit --regex: lookbehind variable aplicado"
run 10 "$SYS" --edit rx.txt --old '(?<=a+)b' --new x --regex; chk "edit --regex: lookbehind sin tope exit 2" 2 "$RC"; chkh 'acotada' "$OUT" "edit --regex: lookbehind sin tope mensaje"
printf 'a=1\r\nb=2\r\n' > rx.txt
nl='
'
run 10 "$SYS" --edit rx.txt --old '=' --new "$nl" --regex --all; chkh '"replaced":2' "$OUT" "edit --regex: CRLF + reemplazo multilinea"
printf 'a\r\n1\r\nb\r\n2\r\n' > exp.txt
run 10 cmp -s rx.txt exp.txt; chk "edit --regex: preserva CRLF en multilinea" 0 "$RC"
# --- atomicidad: ningun temporal '.tmp' huerfano tras los edit ---
ntmp=$(ls -1 *.tmp 2>/dev/null | wc -l | tr -d ' ')
chk "edit: sin temporales huerfanos (escritura atomica)" "0" "$ntmp"
# --- search regex: '$' casa antes de CRLF (no deja '\r' en el texto) ---
printf 'foo\r\nbar\r\n' > crlf.txt
run 10 "$SYS" --search 'foo$' --regex --path crlf.txt; chkh '"text":"foo"' "$OUT" "search --regex: \$ antes de CRLF"
# --- unicode round-trip (emoji UTF-8 intacto) ---
printf 'emoji \xf0\x9f\x98\x80 fin\n' > uni.txt
run 10 "$SYS" --read uni.txt; chkh 'emoji' "$OUT" "read: unicode (emoji) presente"
# --- search modo files (nombres con regex) ---
mkdir -p fn/src fn/docs
printf 'x' > fn/src/regex.zig
printf 'y' > fn/src/main.zig
printf 'z' > fn/docs/guide.md
printf 'w' > fn/build.zig
run 10 "$SYS" --search '\.zig$' --regex --files --path fn; chkh '"total":3' "$OUT" "search --files: regex .zig"
run 10 "$SYS" --search '^src/' --regex --files --path fn; chkh '"total":2' "$OUT" "search --files: ancla ^src/"
run 10 "$SYS" --search '\.ZIG$' --regex --files --case --path fn; chkh '"total":0' "$OUT" "search --files: --case sensible"
run 10 "$SYS" --search '\.ZIG$' --regex --files --path fn; chkh '"total":3' "$OUT" "search --files: CI por defecto"
run 10 "$SYS" --search '.' --regex --files --glob '*.md' --path fn; chkh 'docs/guide.md' "$OUT" "search --files: --glob basename"
run 10 "$SYS" --search '^regex\.zig$' --regex --files --path fn; chkh 'src/regex.zig' "$OUT" "search --files: ^\$ casa por basename"
run 10 "$SYS" --sys stat --path multi.txt; chkh '"kind":"file"' "$OUT" "sys stat"
run 10 "$SYS" --sys mkdir --path sub;      chkh '"op":"mkdir"' "$OUT" "sys mkdir"
run 10 "$SYS" --write sub/b.txt --content interior; chkh '"path":"sub/b.txt"' "$OUT" "write: crea padres"
run 10 "$SYS" --read 'sub\b.txt';          chkh '"path":"sub/b.txt"' "$OUT" "read: '\\' se normaliza a '/'"
run 10 "$SYS" --sys rm --path sub;         chkh '"op":"rm"' "$OUT" "sys rm recursivo"
[ -d sub ] && no "sys rm: carpeta sigue" || ok "sys rm: carpeta borrada"
run 10 "$SYS" --read /etc/os-release --offset 1 --limit 1; chkh '"offset":1' "$OUT" "read: offset+limit"

# ------------------------------------------------------------------ 4. denylist
echo "--- 4. denylist ---"
run 10 "$SYS" --exec "mkfs.ext4 /dev/null"; chkh 'bloqueado' "$OUT" "denylist: mkfs bloqueado"
run 10 "$SYS" --exec "echo add 1";          chknh 'bloqueado' "$OUT" "denylist: 'echo add 1' permitido"

# ------------------------------------------------------------------ 5. job
echo "--- 5. job ---"
run 10 "$SYS" --job start --exec "sh -c 'echo iniciando; sleep 20'"
JID="$(printf '%s' "$OUT" | sed -n 's/.*"job":"\([^"]*\)".*/\1/p')"
chkh '"pid":' "$OUT" "job: start devuelve pid"
[ -n "$JID" ] && ok "job: id extraido ($JID)" || no "job: no se pudo extraer id"
run 10 "$SYS" --job poll --job-id "$JID";   chkh '"running":true' "$OUT" "job: poll running"
run 10 "$SYS" --job poll --job-id "$JID";   chkh 'iniciando' "$OUT" "job: poll trae stdout parcial"
run 10 "$SYS" --job kill --job-id "$JID";   chkh '"killed":true' "$OUT" "job: kill"
run 10 "$SYS" --job poll --job-id "$JID";   chkh '"running":false' "$OUT" "job: kill deja no-running"
run 10 "$SYS" --job forget --job-id "$JID"; chkh '"forgotten":true' "$OUT" "job: forget"

# ------------------------------------------------------------------ 6. TREE-KILL (clave Unix)
echo "--- 6. tree-kill ---"
# exec cortado por timeout: el nieto (subshell en 2.o plano) NO debe sobrevivir.
rm -f "$WORK/tt.marker"
run 12 "$SYS" --exec "sh -c '(sleep 3; echo x > $WORK/tt.marker) & sleep 60'" --timeout 900
chkh '"timed_out":true' "$OUT" "tree-kill(exec): timed_out"
sleep 4
[ -f "$WORK/tt.marker" ] && no "tree-kill(exec): nieto SOBREVIVIO (marker creado)" || ok "tree-kill(exec): nieto muerto (sin marker)"

# job kill: idem.
rm -f "$WORK/jt.marker"
run 10 "$SYS" --job start --exec "sh -c '(sleep 3; echo y > $WORK/jt.marker) & sleep 60'"
JID2="$(printf '%s' "$OUT" | sed -n 's/.*"job":"\([^"]*\)".*/\1/p')"
run 10 "$SYS" --job kill --job-id "$JID2"; chkh '"killed":true' "$OUT" "tree-kill(job): kill"
sleep 4
[ -f "$WORK/jt.marker" ] && no "tree-kill(job): nieto SOBREVIVIO" || ok "tree-kill(job): nieto muerto"
run 10 "$SYS" --job forget --job-id "$JID2" >/dev/null 2>&1

# ------------------------------------------------------------------ 7. MCP JSON-RPC
echo "--- 7. MCP ---"
mcp() { printf '%s\n' "$1" | timeout 10 "$SYS" 2>&1; }
INIT="$(mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')"
chkh '"protocolVersion":"2024-11-05"' "$INIT" "mcp: initialize (version)"
chkh '"id":1' "$INIT" "mcp: initialize (id)"
LIST="$(mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')"
NT="$(printf '%s' "$LIST" | grep -o '"inputSchema"' | wc -l | tr -d ' ')"
chk "mcp: tools/list = 9 herramientas" "9" "$NT"
CALL="$(mcp '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"exec","arguments":{"cmd":"echo mcp-ok"}}}')"
chkh 'mcp-ok' "$CALL" "mcp: tools/call exec"
BAD="$(mcp 'esto no es json')"
chkh '-32700' "$BAD" "mcp: JSON invalido -> -32700"
METH="$(mcp '{"jsonrpc":"2.0","id":4,"method":"no/existe","params":{}}')"
chkh '"error"' "$METH" "mcp: metodo desconocido -> error"
UNK="$(mcp '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}')"
chkh 'isError' "$UNK" "mcp: herramienta desconocida -> isError"
NOTIF="$(mcp '{"jsonrpc":"2.0","method":"notifications/initialized"}')"
chk "mcp: notificacion sin respuesta" "" "$NOTIF"

# ------------------------------------------------------------------ 8. concurrencia
echo "--- 8. concurrencia ---"
N=8; i=0
while [ "$i" -lt "$N" ]; do
  ( "$SYS" --exec "echo proc-$i" > "$WORK/c-$i.json" 2>&1 ) &
  i=$((i+1))
done
wait
cok=0
i=0
while [ "$i" -lt "$N" ]; do
  if grep -q "proc-$i" "$WORK/c-$i.json" 2>/dev/null; then cok=$((cok+1)); fi
  i=$((i+1))
done
chk "concurrencia: $N exec aislados" "$N" "$cok"

# ------------------------------------------------------------- 9. extra Unix
echo "--- 9. extra Unix ---"
# job: codigo de salida via archivo `done` (el shell escribe $?).
run 10 "$SYS" --job start --exec "sh -c 'exit 5'"
JID3="$(printf '%s' "$OUT" | sed -n 's/.*"job":"\([^"]*\)".*/\1/p')"
run 10 "$SYS" --job poll --job-id "$JID3"; chkh '"running":false' "$OUT" "job: termina solo"
run 10 "$SYS" --job poll --job-id "$JID3"; chkh '"exit":5' "$OUT" "job: codigo de salida 5 (Unix)"
run 10 "$SYS" --job forget --job-id "$JID3" >/dev/null 2>&1

# job: timeout propio mata proceso + arbol.
rm -f "$WORK/to.marker"
run 10 "$SYS" --job start --exec "sh -c '(sleep 4; echo t > $WORK/to.marker) & sleep 60'" --timeout 1500
JID4="$(printf '%s' "$OUT" | sed -n 's/.*"job":"\([^"]*\)".*/\1/p')"
sleep 2
run 10 "$SYS" --job poll --job-id "$JID4"; chkh '"timed_out":true' "$OUT" "job: timeout propio corta"
sleep 3
[ -f "$WORK/to.marker" ] && no "job-timeout: nieto SOBREVIVIO" || ok "job-timeout: nieto muerto"
run 10 "$SYS" --job forget --job-id "$JID4" >/dev/null 2>&1

# auditoria en Unix: TEMP(win) -> TMPDIR/·tmp.
ALOG="${TMPDIR:-/tmp}/sys-audit.log"
rm -f "$ALOG"
run 10 "$SYS" --exec "echo audit-probe"
if [ -f "$ALOG" ]; then
  ok "audit: log creado ($ALOG)"
  chkh '"tool":"exec"' "$(cat "$ALOG")" "audit: linea json tool=exec"
else
  no "audit: no se creo $ALOG"
fi

# tree-kill profundo (3 niveles de sh + subshell).
rm -f "$WORK/deep.marker"
run 14 "$SYS" --exec "sh -c 'sh -c \"(sleep 3; echo d > $WORK/deep.marker) & sleep 60\"'" --timeout 900
chkh '"timed_out":true' "$OUT" "tree-kill 3 niveles: timed_out"
sleep 4
[ -f "$WORK/deep.marker" ] && no "tree-kill 3 niveles: nieto SOBREVIVIO" || ok "tree-kill 3 niveles: nieto muerto"

# ---------------- rm/mv en lote (glob/regex, dry_run, force) ----------------
echo "--- rm/mv en lote ---"
mkdir -p "$WORK/lote"
printf a > "$WORK/lote/a.tmp"
printf b > "$WORK/lote/b.tmp"
printf k > "$WORK/lote/keep.txt"
printf 1 > "$WORK/lote/img_01.jpg"
printf 2 > "$WORK/lote/img_02.jpg"

run 10 "$SYS" --sys rm --path "$WORK/lote" --glob '*.tmp' --dry-run
chkh '"matched":2' "$OUT" "rm lote: dry-run matched=2"
chkh '"done":0' "$OUT" "rm lote: dry-run done=0"
[ -f "$WORK/lote/a.tmp" ] && ok "rm lote: dry-run no borra" || no "rm lote: dry-run BORRO"
run 10 "$SYS" --sys rm --path "$WORK/lote" --glob '*.tmp'
chkh '"done":2' "$OUT" "rm lote: glob borra 2"
[ -f "$WORK/lote/a.tmp" ] && no "rm lote: a.tmp sigue" || ok "rm lote: a.tmp borrado"
[ -f "$WORK/lote/keep.txt" ] && ok "rm lote: keep.txt intacto" || no "rm lote: keep.txt borrado"

run 10 "$SYS" --sys mv --path "$WORK/lote" --pattern '^img_([0-9]+)\.jpg$' --regex --subst '$1-photo.jpg' --dry-run
chkh '"matched":2' "$OUT" "mv lote: dry-run matched=2"
[ -f "$WORK/lote/img_01.jpg" ] && ok "mv lote: dry-run no mueve" || no "mv lote: dry-run MOVIO"
run 10 "$SYS" --sys mv --path "$WORK/lote" --pattern '^img_([0-9]+)\.jpg$' --regex --subst '$1-photo.jpg'
chkh '"done":2' "$OUT" "mv lote: regex+subst renombra 2"
[ -f "$WORK/lote/01-photo.jpg" ] && [ -f "$WORK/lote/02-photo.jpg" ] && ok "mv lote: nombres nuevos" || no "mv lote: nombres nuevos"

printf nuevo > "$WORK/lote/img_02.jpg"
run 10 "$SYS" --sys mv --path "$WORK/lote" --pattern '^img_([0-9]+)\.jpg$' --regex --subst '$1-photo.jpg'
chk "mv lote: colision aborta (rc=2)" 2 "$RC"
[ -f "$WORK/lote/img_02.jpg" ] && ok "mv lote: colision no movio" || no "mv lote: colision MOVIO"
run 10 "$SYS" --sys mv --path "$WORK/lote" --pattern '^img_([0-9]+)\.jpg$' --regex --subst '$1-photo.jpg' --force
chk "mv lote: --force pisa destino" 0 "$RC"
[ -f "$WORK/lote/img_02.jpg" ] && no "mv lote: force dejo origen" || ok "mv lote: force movio"

run 10 "$SYS" --list "$WORK/lote" --pattern '^[0-9]+-photo' --regex
chkh '"total":2' "$OUT" "list --regex filtra por nombre"
run 10 "$SYS" --search '^[0-9]+-photo' --regex --mode files --path "$WORK/lote"
chkh '"mode":"files"' "$OUT" "search --mode files (alias)"

printf s > "$WORK/lote/single.txt"
run 10 "$SYS" --sys rm --path "$WORK/lote/single.txt" --pattern '.*' --regex
chk "rm path=archivo + pattern rechazado" 2 "$RC"
[ -f "$WORK/lote/single.txt" ] && ok "rm path=archivo: intacto" || no "rm path=archivo: BORRADO"

# ------------------------------------------------------------------ resumen
echo ""
echo "=== RESUMEN Unix: PASS=$pass FAIL=$fail ==="
rm -rf "$WORK"
[ "$fail" -eq 0 ]
