# Harness de casos de uso (Windows / PowerShell 5.1). Prueba el binario real:
# CLI (una llamada = un proceso) y el servidor MCP por stdio.
# Uso:  powershell -ExecutionPolicy Bypass -File tests\usecases.ps1
#
# Nota: se usan frases SIN tildes a proposito (PowerShell 5.1 puede re-codificar
# los literales del script); el parser acepta ambas formas.

$ErrorActionPreference = "Stop"
$exe = Join-Path $PSScriptRoot "..\zig-out\bin\world-time.exe"
if (-not (Test-Path $exe)) { Write-Host "Falta el binario: $exe (compila con zig build)"; exit 1 }

$pass = 0; $fail = 0
function Check($name, $cond) {
    if ($cond) { $script:pass++; Write-Host ("ok   " + $name) }
    else { $script:fail++; Write-Host ("FAIL " + $name) }
}
function RunCli([string[]]$a) {
    $ErrorActionPreference = "Continue"
    $o = & $exe @a 2>$null
    return ($o -join "`n")
}
function RunCliCode([string[]]$a) {
    $ErrorActionPreference = "Continue"
    $null = & $exe @a 2>$null
    return $LASTEXITCODE
}
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
function Mcp([string[]]$lines) {
    return (($lines -join "`n") | & $exe) -join "`n"
}

# ---------------- CLI: time ----------------
$r = RunCli @("--zone","Tokyo","--format","iso")
Check "time Tokyo iso +09:00" ($r -like '*"+09:00"*')
$r = RunCli @("--zone","Madrid","--format","all")
Check "time Madrid all tiene human" ($r -like '*"human":*')
$r = RunCli @("--zone","UTC+5:30","--format","iso")
Check "offset UTC+5:30" ($r -like '*"+05:30"*')

# ---------------- CLI: fecha clasica ----------------
$r = RunCli @("--fecha","2026-10-16","--zone","UTC","--format","iso")
Check "fecha ISO UTC" ($r -like '*"2026-10-16T00:00:00.000+00:00"*')
$r = RunCli @("--fecha","16/10/2026","--format","iso")
Check "fecha D/M/A" ($r -like '*"2026-10-16T00:00:00.000-05:00"*')
$r = RunCli @("--fecha","16 de octubre de 2026","--format","iso")
Check "fecha 'D de mes de A'" ($r -like '*"2026-10-16T00:00:00.000-05:00"*')
$r = RunCli @("--fecha","1792126800","--zone","UTC","--format","iso")
Check "fecha unix segundos" ($r -like '*"2026-10-16T05:00:00.000+00:00"*')
$r = RunCli @("--fecha","16/10/2026","--suma","-100 dias","--format","iso")
Check "fecha -100 dias = 08/07" ($r -like '*"2026-07-08T00:00:00.000-05:00"*')
$r = RunCli @("--fecha","2026-10-16","--suma","P1Y2M3D","--zone","UTC","--format","iso")
Check "fecha + ISO-8601 P1Y2M3D" ($r -like '*"2027-12-19T00:00:00.000+00:00"*')

# ---------------- CLI: lenguaje natural ----------------
$r = RunCli @("--fecha","ultimo lunes de mayo de 2026","--zone","UTC","--format","iso")
Check "natural: ultimo lunes de mayo 2026" ($r -like '*"2026-05-25T00:00:00.000+00:00"*')
$r = RunCli @("--fecha","primer dia de febrero de 2027","--zone","UTC","--format","iso")
Check "natural: primer dia de febrero 2027" ($r -like '*"2027-02-01T00:00:00.000+00:00"*')

# ---------------- CLI: DST ----------------
$r = RunCli @("--fecha","2026-07-15","--zone","New York","--format","iso")
Check "DST NY verano -04:00" ($r -like '*-04:00*')
$r = RunCli @("--fecha","2026-01-15","--zone","New York","--format","iso")
Check "DST NY invierno -05:00" ($r -like '*-05:00*')
$r = RunCli @("--fecha","2026-07-15","--zone","Madrid","--format","iso")
Check "DST Madrid verano +02:00" ($r -like '*+02:00*')

# ---------------- CLI: dif ----------------
$r = RunCli @("--desde","01/01/2026","--hasta","25/12/2026")
Check "dif total 358 dias" ($r -like '*"total":358*')
$r = RunCli @("--desde","01/01/2026","--hasta","01/01/2026")
Check "dif mismo dia 0" ($r -like '*"total":0*')

# ---------------- CLI: laborable ----------------
$r = RunCli @("--modo","contar","--desde","2026-01-01","--hasta","2026-02-01","--pais","pe")
Check "laborable contar PE = 21" ($r -like '*"laborables":21*')
$r = RunCli @("--modo","contar","--desde","2026-01-01","--hasta","2026-02-01")
Check "laborable contar sin pais = 22" ($r -like '*"laborables":22*')
$r = RunCli @("--modo","sumar","--fecha","2026-01-02","--dias","1")
Check "laborable sumar vie+1 = lunes 05" ($r -like '*"resultado":"2026-01-05*')
$r = RunCli @("--modo","sumar","--fecha","2026-01-05","--dias","-1")
Check "laborable sumar lun-1 = viernes 02" ($r -like '*"resultado":"2026-01-02*')
$r = RunCli @("--modo","es","--fecha","2026-12-25","--pais","pe")
Check "laborable es 25 dic PE = feriado" (($r -like '*"laborable":false*') -and ($r -like '*"motivo":"feriado"*'))
$r = RunCli @("--modo","es","--fecha","2026-12-25")
Check "laborable es 25 dic (vie) = laborable" ($r -like '*"laborable":true*')
$r = RunCli @("--modo","es","--fecha","2026-07-28","--feriados","07-28")
Check "laborable feriado personalizado MM-DD" ($r -like '*"motivo":"feriado"*')

# ---------------- CLI: detalle ----------------
$r = RunCli @("--detalle","--fecha","2026-10-16")
Check "detalle day_of_year 289" ($r -like '*"day_of_year":289*')
Check "detalle weekday viernes" ($r -like '*"weekday":"viernes"*')
Check "detalle quarter 4" ($r -like '*"quarter":4*')
Check "detalle iso_week 2026-W42-5" ($r -like '*"iso_week":"2026-W42-5"*')
$r = RunCli @("--detalle","--fecha","2024-02-29")
Check "detalle bisiesto 2024" (($r -like '*"is_leap":true*') -and ($r -like '*"days_in_month":29*'))

# ---------------- CLI: epoca ----------------
$r = RunCli @("--epoca","--fecha","2026-10-16")
Check "epoca julian 2461329.5" ($r -like '*"julian_day":2461329.500000*')
Check "epoca mjd 61329" ($r -like '*"mjd":61329.000000*')
Check "epoca excel 46311" ($r -like '*"excel_serial":46311.000000*')
Check "epoca iso_ordinal 2026-289" ($r -like '*"iso_ordinal":"2026-289"*')
Check "epoca unix_ms" ($r -like '*"unix_ms":1792126800000*')

# ---------------- CLI: formato ----------------
$r = RunCli @("--patron","%Y-%m-%d","--fecha","2026-10-16","--zone","UTC")
Check "formato Y-m-d" ($r -like '*"format":"2026-10-16"*')
$r = RunCli @("--patron","%A","--fecha","2026-10-16","--zone","UTC")
Check "formato %A viernes" ($r -like '*"format":"viernes"*')
$r = RunCli @("--patron","%V","--fecha","2026-10-16","--zone","UTC")
Check "formato %V 42" ($r -like '*"format":"42"*')
$r = RunCli @("--formato","--patron","%A %d de %B","--fecha","2026-10-16","--zone","UTC")
Check "formato: solo patron (sin base)" (($r -like '*"format":"viernes 16 de octubre"*') -and ($r -notlike '*"base":*'))
Check "formato %X invalido" ((RunCliCode @("--patron","%X","--fecha","2026-10-16")) -ne 0)

# ---------------- CLI: ayuda y errores ----------------
$r = RunCli @("--help")
Check "help contiene Uso: world-time" ($r -like '*Uso: world-time*')
$r = RunCli @("--help-topic","zones")
Check "help-topic zones" ($r -like '*America/Lima*')
Check "help-topic invalido exit != 0" ((RunCliCode @("--help-topic","bogus")) -ne 0)
Check "zona invalida exit 2" ((RunCliCode @("--zone","neverland")) -eq 2)
Check "format invalido exit 2" ((RunCliCode @("--format","bogus")) -eq 2)
Check "fecha invalida exit 2" ((RunCliCode @("--fecha","32 de octubre de 2026")) -eq 2)

# ---------------- MCP ----------------
$out = Mcp @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
Check "mcp initialize name mcp-time" ($out -like '*"name":"mcp-time"*')
$ver = (& $exe --registro | ConvertFrom-Json).version
Check "mcp initialize version $ver" ($out -like ('*"version":"' + $ver + '"*'))
Check "mcp protocol 2024-11-05" ($out -like '*"protocolVersion":"2024-11-05"*')
$out = Mcp @('{"jsonrpc":"2.0","id":1,"method":"ping"}')
Check "mcp ping {}" ($out -like '*"result":{}*')
$out = Mcp @('{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
Check "tools/list incluye laborable" ($out -like '*"name":"laborable"*')
Check "tools/list incluye epoca" ($out -like '*"name":"epoca"*')
Check "tools/list incluye detalle" ($out -like '*"name":"detalle"*')
Check "tools/list incluye formato" ($out -like '*"name":"formato"*')
Check "tools/list incluye get_lima_time" ($out -like '*"name":"get_lima_time"*')
$out = Mcp @('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"epoca","arguments":{"fecha":"2026-10-16","zone":"UTC"}}}')
Check "mcp epoca unix_ns" ($out -like '*unix_ns*')
$out = Mcp @('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"laborable","arguments":{"modo":"contar","desde":"2026-01-01","hasta":"2026-02-01","pais":"pe"}}}')
Check "mcp laborable 21" ($out -like '*laborables\":21*')
$out = Mcp @('{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"detalle","arguments":{"fecha":"2026-10-16"}}}')
Check "mcp detalle doy 289" ($out -like '*day_of_year\":289*')
$out = Mcp @('{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"formato","arguments":{"patron":"%A","fecha":"2026-10-16"}}}')
Check "mcp formato viernes" ($out -like '*\"format\":\"viernes*')
$out = Mcp @('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"time","arguments":{"zone":"neverland"}}}')
Check "mcp zona invalida isError" ($out -like '*"isError":true*')
$out = Mcp @('{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"noexiste","arguments":{}}}')
Check "mcp tool desconocida isError" ($out -like '*"isError":true*')
$out = Mcp @('{"jsonrpc":"2.0","id":7,"method":"metodo/raro"}')
Check "mcp method not found -32601" ($out -like '*-32601*')
$out = Mcp @('{no es json}')
Check "mcp parse error -32700 bien formado" (($out -like '*-32700*') -and ($out -notlike '*""Parse*'))

Write-Host ""
Write-Host ("RESULTADO: {0} ok, {1} fail (total {2})" -f $script:pass, $script:fail, ($script:pass + $script:fail))
if ($script:fail -gt 0) { exit 1 }
exit 0
