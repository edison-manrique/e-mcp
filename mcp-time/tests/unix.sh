#!/bin/sh
# Harness de casos de uso (POSIX / Linux). Prueba el binario cross-compilado
# (zig build unix) tanto en CLI como en MCP por stdio.
#   Uso:  sh tests/unix.sh [ruta-al-binario]
# Por defecto: zig-out/unix/world-time
set -u

BIN="${1:-$(dirname "$0")/../zig-out/unix/world-time}"
if [ ! -x "$BIN" ]; then
  echo "Falta el binario: $BIN (compila con zig build unix)"
  exit 1
fi

pass=0; fail=0
check() {
  if eval "$2"; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
  else fail=$((fail+1)); printf 'FAIL %s\n' "$1"; fi
}
cli() { "$BIN" "$@" 2>/dev/null; }

# ---- CLI: time ----
check "time Tokyo +09:00" 'cli --zone Tokyo --format iso | grep -q "+09:00"'
check "offset UTC+5:30" 'cli --zone UTC+5:30 --format iso | grep -q "+05:30"'

# ---- CLI: fecha ----
check "fecha ISO UTC" 'cli --fecha 2026-10-16 --zone UTC --format iso | grep -q "2026-10-16T00:00:00.000+00:00"'
check "fecha D/M/A Lima" 'cli --fecha 16/10/2026 --format iso | grep -q "2026-10-16T00:00:00.000-05:00"'
check "fecha -100 dias" 'cli --fecha 16/10/2026 --suma "-100 dias" --format iso | grep -q "2026-07-08T00:00:00.000-05:00"'
check "fecha +P1Y2M3D" 'cli --fecha 2026-10-16 --suma P1Y2M3D --zone UTC --format iso | grep -q "2027-12-19T00:00:00.000+00:00"'

# ---- CLI: lenguaje natural ----
check "natural ultimo lunes mayo 2026" 'cli --fecha "ultimo lunes de mayo de 2026" --zone UTC --format iso | grep -q "2026-05-25T00:00:00.000+00:00"'
check "natural primero de febrero 2027" 'cli --fecha "primer dia de febrero de 2027" --zone UTC --format iso | grep -q "2027-02-01T00:00:00.000+00:00"'

# ---- CLI: DST ----
check "DST NY verano -04:00" 'cli --fecha 2026-07-15 --zone "New York" --format iso | grep -q -- "-04:00"'
check "DST Madrid verano +02:00" 'cli --fecha 2026-07-15 --zone Madrid --format iso | grep -q "+02:00"'

# ---- CLI: dif ----
check "dif 358 dias" 'cli --desde 01/01/2026 --hasta 25/12/2026 | grep -q "\"total\":358"'

# ---- CLI: laborable ----
check "laborable contar PE 21" 'cli --modo contar --desde 2026-01-01 --hasta 2026-02-01 --pais pe | grep -q "\"laborables\":21"'
check "laborable contar sin pais 22" 'cli --modo contar --desde 2026-01-01 --hasta 2026-02-01 | grep -q "\"laborables\":22"'
check "laborable sumar vie+1" 'cli --modo sumar --fecha 2026-01-02 --dias 1 | grep -q "\"resultado\":\"2026-01-05"'
check "laborable es feriado PE" 'cli --modo es --fecha 2026-12-25 --pais pe | grep -q "\"motivo\":\"feriado\""'

# ---- CLI: detalle / epoca / formato ----
check "detalle doy 289" 'cli --detalle --fecha 2026-10-16 | grep -q "\"day_of_year\":289"'
check "detalle iso_week" 'cli --detalle --fecha 2026-10-16 | grep -q "2026-W42-5"'
check "detalle bisiesto" 'cli --detalle --fecha 2024-02-29 | grep -q "\"is_leap\":true"'
check "epoca julian" 'cli --epoca --fecha 2026-10-16 | grep -q "2461329.5"'
check "epoca excel" 'cli --epoca --fecha 2026-10-16 | grep -q "\"excel_serial\":46311"'
check "formato %A" 'cli --patron "%A" --fecha 2026-10-16 --zone UTC | grep -q "\"format\":\"viernes\""'
check "formato solo patron" 'cli --formato --patron "%A %d de %B" --fecha 2026-10-16 --zone UTC | grep -q "\"format\":\"viernes 16 de octubre\""'
check "formato %X invalido falla" '! cli --patron "%X" --fecha 2026-10-16'

# ---- CLI: ayuda / errores ----
check "help uso" 'cli --help | grep -q "Uso: world-time"'
check "help zones" 'cli --help-topic zones | grep -q "America/Lima"'
check "zona invalida falla" '! cli --zone neverland'
check "fecha invalida falla" '! cli --fecha "32 de octubre de 2026"'

# ---- MCP ----
mcp() { printf '%s\n' "$@" | "$BIN" 2>/dev/null; }
check "mcp initialize" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}" | grep -q "\"name\":\"mcp-time\""'
check "mcp tools/list laborable" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}" | grep -q "\"name\":\"laborable\""'
check "mcp tools/list epoca" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}" | grep -q "\"name\":\"epoca\""'
check "mcp call epoca" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"epoca\",\"arguments\":{\"fecha\":\"2026-10-16\",\"zone\":\"UTC\"}}}" | grep -q "unix_ns"'
check "mcp call formato" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"formato\",\"arguments\":{\"patron\":\"%A\",\"fecha\":\"2026-10-16\",\"zone\":\"UTC\"}}}" | grep -q "viernes"'
check "mcp call zona invalida isError" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"time\",\"arguments\":{\"zone\":\"neverland\"}}}" | grep -q "\"isError\":true"'
check "mcp method not found" 'mcp "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"raro\"}" | grep -q -- "-32601"'

echo ""
echo "RESULTADO: $pass ok, $fail fail (total $((pass+fail)))"
[ "$fail" -gt 0 ] && exit 1
exit 0
