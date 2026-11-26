# Servidor MCP de Tiempo (mcp-time v3)

Servidor MCP escrito en Zig 0.16.0 para trabajar con **fechas y horas en
español**: hora actual con **horario de verano (DST) real**, conversión de
fechas (ISO, `D/M/A`, `D de mes de A`, timestamps unix, eventos), **lenguaje
natural** (`próximo viernes`, `en 3 semanas`, `fin de mes`), sumas y restas
(`100 dias`, `P1Y2M3D`), diferencias, **días laborables y feriados**, desglose
(semana ISO-8601, día del año, trimestre), **epoch y estándares** (Unix, Julian
Day, MJD, Excel, RFC 3339) y **formato `strftime`**.

Se comunica por `stdio` con JSON-RPC 2.0 y no necesita dependencias ni conexión
a internet. Todo el cálculo es propio (calendario gregoriano proléptico, motor
de reglas DST, algoritmo de Pascua).

(El binario sigue llamándose `world-time` por compatibilidad con instalaciones
y con el orquestador; funcionalmente es el MCP de tiempo/`mcp-time`.)

## Requisitos

- Zig 0.16.0
- Windows, Linux o macOS (binario nativo, sin runtime)

## Compilación y pruebas

```sh
cd mcp-time
zig build                        # ReleaseFast por defecto -> zig-out/bin/world-time.exe
zig build test --summary all     # tests unitarios (26)
zig build unix                   # cross-compile Linux x86_64 (musl)
```

> `zig build` ya compila en **ReleaseFast**. Para un binario más chico:
> `zig build -Doptimize=ReleaseSmall`.

- `zig-out/bin/world-time.exe` — binario local.
- `zig-out/unix/world-time` — binario Linux/musl (se usa en WSL).
- Tests de casos de uso: `tests/usecases.ps1` (Windows) y `tests/unix.sh`
  (POSIX/Linux). Ambos prueban CLI y servidor MCP por `stdio`.

## Modo CLI (una llamada, un proceso)

Sin argumentos el binario es servidor MCP persistente. Con argumentos ejecuta
**una vez, imprime y termina** (ideal para que el orquestador lo llame por cada
pedido):

```bat
world-time --zone Tokyo --format iso
world-time --zone UTC-5
world-time --fecha "próximo viernes" --patron "%A %d/%m/%Y"
world-time --suma "-100 dias"
world-time --desde 01/01/2026 --hasta 25/12/2026 --en dias
world-time --modo contar --desde 2026-01-01 --hasta 2026-02-01 --pais pe
world-time --detalle --fecha 2026-10-16
world-time --epoca   --fecha 2026-10-16
world-time --formato --patron "%A %d de %B de %Y" --zone Madrid
world-time --help-topic zones
world-time --help
```

Opciones:

| Opción | Alias | Descripción |
|--------|-------|-------------|
| `--zone Z` | `-z` | Ciudad, IANA u offset UTC (def. `Lima`) |
| `--format F` | `-f` | `all\|iso\|human\|unix` (def. `all`) |
| `--patron P` | | Formato `strftime` (ej. `"%A %d de %B"`) |
| `--fecha F` | | Base: `ahora\|ISO\|D/M/A\|natural\|unix` |
| `--suma S` | | Desplazamiento: `-100 dias`, `P1Y2M3D` |
| `--desde A` `--hasta B` | | Diferencia (`--hasta` def. ahora) |
| `--en U` | | `segundos\|minutos\|horas\|dias\|semanas` (def. `dias`) |
| `--modo M` | | `contar\|sumar\|es` (días laborables) |
| `--dias N` | | Entero (puede ser negativo) para `--modo sumar` |
| `--pais P` | | `pe\|us\|mx\|es\|cl\|ar` (feriados) |
| `--feriados L` | | Lista por comas: `"MM-DD,2026-07-28"` |
| `--detalle` | | Desglose (semana ISO, día del año, trimestre…) |
| `--epoca` | | Estándares (Unix, Julian, Excel, RFC 3339…) |
| `--formato` | | Aplica solo el `--patron` |
| `--help-topic T` | | `all\|time\|fecha\|dif\|laborable\|detalle\|epoca\|formato\|zones` |
| `--help` | `-h` | Ayuda |

El resultado va a `stdout` con código `0`; los errores van a `stderr` con
código `2`.

## Configuración en opencode

La forma recomendada es entrar por el **servidor** (`emcp`, una
sola entrada para todas las apps):

```json
{
  "mcp": {
    "emcp": {
      "type": "local",
      "command": ["emcp"],
      "enabled": true
    }
  }
}
```

Entrada directa (alternativa, sin el servidor). La configuración usa solo el
**nombre del comando**, sin rutas absolutas:

```json
{
  "mcp": {
    "world-time": {
      "type": "local",
      "command": ["world-time"],
      "enabled": true
    }
  }
}
```

### Qué significa cada campo

| Campo | Para qué sirve |
|-------|----------------|
| `world-time` | Nombre con el que verás el servidor en opencode. Es solo una etiqueta. |
| `type: "local"` | El servidor corre en tu máquina (por `stdio`), no es un servicio remoto por URL. |
| `command` | **El programa que el sistema ejecuta para arrancar el servidor.** Es UNA sola orden del sistema operativo: el lanzador `world-time` de esta carpeta, que a su vez ejecuta el binario de `zig-out/bin/`. Si alguna vez necesitara argumentos, irían como elementos extra del arreglo, ej. `["world-time", "--puerto", "8080"]`; este servidor no necesita ninguno. |
| `enabled` | Interruptor: `true` lo activa, `false` lo **desactiva sin borrar la configuración**. Sirve para apagar el servidor temporalmente (si falla, si estorba o si no lo necesitas ahora) sin perder su entrada; para reactivarlo solo cambias a `true`. |

### Aclaración: en `command` NO van `time_help`, `time`, etc.

Esos nombres (`time`, `fecha`, `dif`, `laborable`, `detalle`, `epoca`,
`formato`, `time_help`, `get_lima_time`) son **herramientas MCP**, no comandos del
sistema, y **no se escriben en la configuración**. Las llama la IA sola, a
través del protocolo MCP (`tools/call`), cada vez que necesita la hora. Tú no
tienes que invocarlas a mano.

Esto es lo que la IA envía internamente cuando quiere la ayuda de zonas (tú
solo lo verías en un registro de depuración):

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"help","arguments":{"topic":"zones"}}}
```

### Activar el nombre corto (una sola vez)

Para que el nombre `world-time` se resuelva, agrega esta carpeta al `PATH` de
tu usuario:

```bat
setx PATH "%PATH%;C:\EMC\GDRIVE\app-center\GITHUB\e-mcp\mcp-time"
```

Cierra y reabre la terminal u opencode para que tome el cambio. En Linux/macOS
agrega la carpeta al `PATH` en tu `~/.bashrc` o similar, y usa el lanzador
`world-time` sin extensión.

Así el cliente solo conoce el nombre corto, y el lanzador dentro de la carpeta
MCP se encarga de ejecutar el binario correcto de `zig-out/bin/`.

## Herramientas

| Herramienta | Para qué sirve | Parámetros |
|---|---|---|
| `time` | Hora actual en cualquier zona | `zone`, `format`, `patron` |
| `fecha` | Convierte y suma/resta fechas (español + natural) | `fecha`, `suma`, `zone`, `format`, `patron` |
| `dif` | Diferencia entre dos fechas | `desde`, `hasta`, `en`, `zone` |
| `laborable` | Días laborables (contar/sumar/es) | `modo`, `desde`, `hasta`, `fecha`, `dias`, `pais`, `feriados`, `zone` |
| `detalle` | Día de la semana, semana ISO, día del año, trimestre | `fecha`, `zone` |
| `epoca` | Unix, Julian Day, MJD, Excel, RFC 3339, ISO ordinal | `fecha`, `zone` |
| `formato` | Formato `strftime` personalizado | `patron`, `fecha`, `zone` |
| `time_help` | Ayuda en Markdown | `topic` |
| `get_lima_time` | Alias de `time` con `zone=Lima` | `format`, `patron` |

### `time` — hora en cualquier zona horaria

| Parámetro | Tipo  | Obligatorio | Valor por defecto | Descripción |
|-----------|-------|-------------|-------------------|-------------|
| `zone`    | texto | no          | `Lima`            | Ciudad, nombre IANA u offset UTC. `time_help` muestra un resumen. |
| `format`  | texto | no          | `all`             | `all`, `iso`, `human` o `unix`. |
| `patron`  | texto | no          | (ninguno)         | Formato `strftime`, ej. `%A %d de %B de %Y %H:%M`. |

Ejemplos de `zone` válidos: `Lima`, `Tokyo`, `Madrid`, `America/Lima`,
`Asia/Tokyo`, `UTC`, `UTC-5`, `GMT+9`, `UTC+5:30`, `+9`, `-3:30`. No importan
las mayúsculas, y da igual usar espacio, `_` o `/` (`New York`, `New_York` y
`America/New_York` son lo mismo).

Respuesta con `format=all`:

```json
{
  "iso": "2026-10-15T22:52:22.563-05:00",
  "human": "15 de octubre de 2026, 22:52:22 (Lima)",
  "weekday": "jueves",
  "timezone": "America/Lima",
  "utc_offset": "-05:00",
  "dst": false,
  "unix_sec": 1792122742,
  "unix_ms": 1792122742563
}
```

El campo `dst` es `true` si la zona está en horario de verano en ese instante.

### `fecha` — convierte y desplaza fechas en español

| Parámetro | Tipo  | Obligatorio | Valor por defecto | Descripción |
|-----------|-------|-------------|-------------------|-------------|
| `fecha`   | texto | no          | `ahora`           | Base (ver abajo) |
| `suma`    | texto | no          | (sin cambio)      | `100 dias`, `-3 horas`, `1 mes`, `2 horas, 30 minutos`, ISO `P1Y2M3D` |
| `zone`    | texto | no          | `Lima`            | Ciudad, IANA u offset UTC |
| `format`  | texto | no          | `all`             | `all`, `iso`, `human` o `unix` |
| `patron`  | texto | no          | (ninguno)         | Formato `strftime` |

Formatos de `fecha` (años 1-9999, gregoriano proléptico):

- **Relativos**: `ahora`, `hoy`, `ayer`, `mañana`, `anteayer`.
- **Unix**: `1792126800` (segundos), `1792126800000` (ms), `@...`, negativos.
- **ISO**: `2026-10-16`, `2026-10-16T14:30`, `2026-10-16T14:30:00-05:00`, `...Z`.
- **D/M/A**: `16/10/2026 14:30`.
- **Español**: `16 de octubre de 2026`.
- **Eventos**: `segunda guerra mundial`, `apollo 11`, `muro de berlin`,
  `11s`, `halley`, `eclipses 2026/2027`, `año 2400`, etc.
- **Lenguaje natural**:
  - `próximo viernes`, `este sábado`, `el lunes que viene`, `next friday`;
  - `último lunes de mayo`, `primer día de febrero de 2027`, `segundo martes de marzo`;
  - `fin de mes`, `principio de mes`, `fin de año`, `inicio de año`;
  - `en 3 semanas`, `dentro de 2 dias`, `hace 2 meses`;
  - `mañana a las 9`, `hoy a las 14:30`, `próximo lunes a las 8`;
  - `medianoche`, `mediodía`, `próxima semana`, `mes que viene`, `año que viene`.

Responde igual que `time` + `relacion` (`hace 100 días`, `en 2 horas`, `ahora
mismo`), `base`, `suma` aplicada y (si se pide) `format`. Los meses y años se
suman por calendario: `31 ene + 1 mes = 28 feb`.

### `dif` — diferencia entre dos fechas

| Parámetro | Tipo  | Obligatorio | Valor por defecto | Descripción |
|-----------|-------|-------------|-------------------|-------------|
| `desde`   | texto | sí          | —                 | Mismos formatos que `fecha` |
| `hasta`   | texto | no          | `ahora`           | Mismos formatos que `fecha` |
| `en`      | texto | no          | `dias`            | `segundos\|minutos\|horas\|dias\|semanas` |
| `zone`    | texto | no          | `Lima`            | Zona de interpretación |

Responde `total` (en la unidad pedida), `desglose` (`358 días`), `desde_rel` y
`hasta_rel` (pasado/presente/futuro en español).

### `laborable` — días laborables (L-V menos feriados)

| Parámetro | Tipo  | Obligatorio | Valor por defecto | Descripción |
|-----------|-------|-------------|-------------------|-------------|
| `modo`    | texto | no          | `contar`          | `contar`, `sumar` o `es` |
| `desde`   | texto | sí (contar) | —                 | Inicio del rango |
| `hasta`   | texto | no          | `ahora`           | Fin del rango (no inclusive) |
| `fecha`   | texto | sí (sumar/es) | `ahora`         | Fecha base |
| `dias`    | entero| sí (sumar)  | —                 | Positivo avanza, negativo retrocede |
| `pais`    | texto | no          | (ninguno)         | `pe\|us\|mx\|es\|cl\|ar` |
| `feriados`| lista | no          | (ninguno)         | `"MM-DD"` (anual) o fechas exactas |
| `zone`    | texto | no          | `Lima`            | Zona de los días civiles |

- `contar`: nº de laborables en `[desde, hasta)`. Negativo si `hasta < desde`.
- `sumar`: fecha resultante tras sumar `dias` laborables (conserva la hora).
- `es`: `laborable` (bool) + `motivo` (`laborable`, `fin de semana`, `feriado`).

Los presets incluyen los feriados nacionales principales. No se modelan los
"traslados" (feriados movidos al lunes) ni feriados regionales.

### `detalle` — desglose de una fecha

| Parámetro | Tipo  | Obligatorio | Valor por defecto |
|-----------|-------|-------------|-------------------|
| `fecha`   | texto | no          | `ahora`           |
| `zone`    | texto | no          | `Lima`            |

Devuelve: `iso`, `human`, `weekday`/`weekday_num`, `day_of_year`, `iso_week`
(`YYYY-Www-D`), `iso_year`/`iso_week_num`/`iso_weekday`, `quarter`,
`month`/`month_num`, `days_in_month`, `is_leap`, `is_weekend`, `timezone`,
`utc_offset`, `dst`, `unix_sec`, `unix_ms`.

### `epoca` — estándares de fecha

| Parámetro | Tipo  | Obligatorio | Valor por defecto |
|-----------|-------|-------------|-------------------|
| `fecha`   | texto | no          | `ahora`           |
| `zone`    | texto | no          | `Lima`            |

Devuelve: `iso`, `rfc3339`, `unix_sec`, `unix_ms`, `unix_us`, `unix_ns`,
`julian_day`, `mjd`, `excel_serial`, `iso_ordinal` (`YYYY-DDD`) e `iso_week`.

### `formato` — formato `strftime` en español

| Parámetro | Tipo  | Obligatorio | Valor por defecto |
|-----------|-------|-------------|-------------------|
| `patron`  | texto | sí          | —                 |
| `fecha`   | texto | no          | `ahora`           |
| `zone`    | texto | no          | `Lima`            |

Especificadores: `%Y %y %C %m %d %e %H %I %M %S %j %V %G %g %u %w %A %a %B %b %h
%p %P %Z %z %s %q %F %T %R %D %% %n %t`. Nombres de día y mes en español.

### `time_help` — ayuda en Markdown

| Parámetro | Tipo  | Obligatorio | Valor por defecto | Descripción |
|-----------|-------|-------------|-------------------|-------------|
| `topic`   | texto | no          | `all`             | `all`, `time`, `fecha`, `dif`, `laborable`, `detalle`, `epoca`, `formato` o `zones` |

### `get_lima_time` — alias de compatibilidad

Es lo mismo que `time` con `zone=Lima`. Acepta `format` y `patron`. Existe para
no romper clientes de la versión 1.

## Zonas soportadas

Las zonas con nombre aplican **DST por reglas** (tabla `nth-weekday-of-month`
con la zona aportando el offset estándar). Entre paréntesis, el offset de
verano cuando aplica.

| Zona | Ciudad | Estándar | Verano |
|------|--------|----------|--------|
| `UTC` | UTC | +00:00 | — |
| `America/Lima` | Lima | -05:00 | — |
| `America/Bogota` | Bogotá | -05:00 | — |
| `America/Mexico_City` | Ciudad de México | -06:00 | (abolido 2022) |
| `America/New_York` | Nueva York | -05:00 | -04:00 |
| `America/Chicago` | Chicago | -06:00 | -05:00 |
| `America/Denver` | Denver | -07:00 | -06:00 |
| `America/Los_Angeles` | Los Ángeles | -08:00 | -07:00 |
| `America/Sao_Paulo` | São Paulo | -03:00 | — |
| `America/Buenos_Aires` | Buenos Aires | -03:00 | — |
| `America/Santiago` | Santiago | -04:00 | -03:00 |
| `America/Caracas` | Caracas | -04:00 | — |
| `Pacific/Honolulu` | Honolulu | -10:00 | — |
| `Europe/London` | Londres | +00:00 | +01:00 |
| `Europe/Madrid` | Madrid | +01:00 | +02:00 |
| `Europe/Paris` | París | +01:00 | +02:00 |
| `Europe/Berlin` | Berlín | +01:00 | +02:00 |
| `Europe/Moscow` | Moscú | +03:00 | — |
| `Africa/Cairo` | El Cairo | +02:00 | +03:00 |
| `Africa/Lagos` | Lagos | +01:00 | — |
| `Africa/Johannesburg` | Johannesburgo | +02:00 | — |
| `Asia/Dubai` | Dubái | +04:00 | — |
| `Asia/Karachi` | Karachi | +05:00 | — |
| `Asia/Kolkata` | Nueva Delhi | +05:30 | — |
| `Asia/Dhaka` | Daca | +06:00 | — |
| `Asia/Bangkok` | Bangkok | +07:00 | — |
| `Asia/Singapore` | Singapur | +08:00 | — |
| `Asia/Shanghai` | Shanghái | +08:00 | — |
| `Asia/Tokyo` | Tokio | +09:00 | — |
| `Asia/Seoul` | Seúl | +09:00 | — |
| `Australia/Sydney` | Sídney | +10:00 | +11:00 |
| `Pacific/Auckland` | Auckland | +12:00 | +13:00 |

Además, los offsets genéricos `UTC±H` (0 a 14) y `UTC±H:MM` (minutos 00, 15,
30 o 45) siempre funcionan y son exactos.

## Ejemplos del protocolo (lo que la IA envía)

Estos mensajes NO los escribes tú: son lo que la IA manda al servidor por
`stdio` cuando usa las herramientas. Sirven para probar el servidor a mano o
entender el protocolo.

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"time","arguments":{"zone":"Tokyo","format":"iso"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fecha","arguments":{"fecha":"próximo viernes"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"laborable","arguments":{"modo":"contar","desde":"2026-01-01","hasta":"2026-02-01","pais":"pe"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"epoca","arguments":{"fecha":"2026-10-16"}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"help","arguments":{"topic":"zones"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/list","params":{}}
```

## Errores

- Zona desconocida: devuelve `isError: true` y sugiere usar `time_help` con
  `topic=zones`.
- Herramienta desconocida: devuelve `isError: true` y sugiere usar `time_help`.
- Fecha/duración/patrón inválidos: `isError: true` con un mensaje accionable.
- Las notificaciones (`notifications/*`) y los mensajes sin `id` no generan
  respuesta, según la norma JSON-RPC.

## Cómo agregar una herramienta nueva

El servidor está dividido en módulos por dominio dentro de `src/`:

1. Escribir el handler `pub fn runMiTool(ctx: proto.Ctx) !void` en
   `src/mcp/handlers.zig`.
2. Agregar su descripción JSON `LIST_MI_TOOL` en `src/mcp/tools.zig`.
3. Registrar una línea en la tabla `TOOLS`. Listo: `tools/list` + `tools/call`
   funcionan solos, y el CLI suma la opción que decidas en `src/cli/cli.zig`.

La lógica reutilizable vive en `src/time/`; la presentación JSON en
`src/core/jsonw.zig`; los textos en `src/cli/ayuda.zig`.

## Notas importantes

- Las zonas con nombre usan **DST por reglas** para ~1981–2100; fuera de ese
  rango se usa la hora estándar. Los offsets explícitos (`UTC±N`) siempre son
  exactos.
- La hora sale del **reloj del sistema**; mantén NTP sincronizado.
- Años válidos **1–9999** (gregoriano proléptico).
- Cada mensaje es un JSON compacto por línea. El servidor también acepta JSON
  multilínea (pretty-printed) acumulándolo hasta balancear llaves.

## Archivos

```
mcp-time/
  build.zig            compilación (exe, tests, cross-compile `unix`)
  build.zig.zon        nombre del paquete y versión
  src/
    main.zig           entrada delgada: transporte, dispatch, arranque CLI
    root.zig           puerta del paquete + registro de tests
    time/              dominio puro (sin IO)
      errs.zig         conjunto de errores compartido
      civil.zig        calendario gregoriano proléptico
      dst.zig          motor de reglas de horario de verano
      zona.zig         tabla de zonas + resolución tolerante + `Z`
      fecha.zig        parseo (clásico + natural), aritmética, relativos
      dur.zig          duraciones español + ISO-8601
      feriados.zig     presets por país + Pascua + feriados propios
      laborable.zig    días laborables (contar/sumar/es)
      strftime.zig     formato personalizado
      epoca.zig        semana ISO, día del año, Julian/MJD/Excel
      tmtool.zig       fachada: VERSION, mensajes, "ahora"
    core/
      proto.zig        stdio + JSON-RPC 2.0
      jsonw.zig        escritores JSON de resultados
    mcp/
      tools.zig        registro de herramientas (`tools/list`)
      handlers.zig     un handler por herramienta
    cli/
      ayuda.zig        textos de ayuda y uso CLI (fuente única)
      cli.zig          CLI efímero (1 llamada = 1 proceso)
  tests/
    usecases.ps1       casos de uso en Windows (CLI + MCP)
    unix.sh            casos de uso en Linux (CLI + MCP)
  world-time.cmd       lanzador con nombre corto (Windows)
  world-time           lanzador con nombre corto (Linux/macOS)
  zig-out/bin/         binario compilado
```
