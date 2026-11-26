# emcp — orquestador MCP dinámico (Zig)

Servidor MCP delgado que **no tiene herramientas integradas**: expone las
herramientas de los MCPs que estén **registrados** en disco (`mcps/index.json`),
más 3 meta-herramientas de registro. Sumar o quitar un MCP **no recompila**
nada: se registra/desregistra y listo.

Todo el servidor está escrito en **Zig 0.16.0**, sin dependencias externas.
La criptografía de firma vive en la librería `secp256k1-fast` del proyecto
hermano **`mcp-crypto`** (se importa como módulo `secp`).

## Herramientas que expone

`tools/list` = **3 meta-tools** + **las herramientas de cada MCP registrado**:

| Meta-tool      | Qué hace                                                               |
| -------------- | ---------------------------------------------------------------------- |
| `registrar`    | Instala/actualiza un MCP externo (valida hash + firma, handshake MCP). |
| `desregistrar` | Quita un MCP registrado (borra carpeta + entrada).                     |
| `registrados`  | Lista los MCPs registrados y su estado.                                |

Los **esquemas** de las herramientas registradas se copian **tal cual** del
`tools/list` real del MCP durante el registro, así nunca se desincronizan.
La guía de uso para IAs está en **`USO.md`**.

## MCPs registrados (sin recompiar)

`emcp` lee `mcps/index.json` al arrancar y publica las herramientas de
cada entrada; cada `tools/call` se reenvía por JSON-RPC al binario del MCP por un
**worker persistente** (un proceso por MCP, vivo entre llamadas), de modo que la
llamada solo cuesta escribir y leer una línea.

```bat
:: registrar (requiere el <bin>.registro.json hermano)
emcp --registrar ..\mcp-time\zig-out\bin\world-time.exe
emcp --registrados
emcp --desregistrar mcp-time

:: o por MCP
{"name":"registrar","arguments":{"origen":"https://ejemplo/mi-mcp.exe"}}
```

Un binario es registrable si:

1. trae su **`<bin>.registro.json`** (identidad + `bin_sha256` + `creador` +
   `firma`), y
2. habla MCP (`initialize` + `tools/list`).

Se valida el `sha256` del binario contra el del registro y se **exige** la
firma, que debe provenir del **creador verificado** embebido (Schnorr BIP-340).
Sin firma válida el registro se **rechaza**. Ver `../DEVELOPER.md` §3-§5.

Además, **al arrancar**, `emcp` **re-verifica** cada binario (existe +
`sha256` + firma contra el creador embebido) **una sola vez**. Si un binario fue
sustituido o alterado, ese MCP queda **no disponible** y su `tools/call`
responde error. Al hacerlo al inicio, el camino de ejecución (`tools/call`)
queda **libre de hashing**: las llamadas son lo más rápidas posible (la
seguridad fuerte vive en el registro). Diagnostícalo con `emcp --verificar`.

## Utilidades de registro y firma (CLI)

```bat
emcp --generar-clave                      :: par de claves secp256k1
emcp --generar-registro <bin> --clave HEX [--salida R]
                                                :: crea <bin>.registro.json FIRMADO (--clave obligatoria)
emcp --firmar <registro.json> --clave HEX :: firma/re-firma un registro
emcp --registro                           :: imprime el manifiesto del servidor
```

## Diagnóstico y opciones

```bat
emcp --version                 :: versión del servidor
emcp --verificar               :: valida mcps/index.json (existencia + hash + firma)
                                     :: (alias --diag; sale con código 2 si algo falla)
emcp --registrados             :: estado de cada MCP (integridad + firma)
emcp --mcps <dir>              :: carpeta mcps/ alternativa
EMCP_MCPS=<dir>                :: lo mismo, por entorno
EMCP_TIMEOUT_MS=<ms>           :: timeout de reenvío de tools/call (por defecto 125000)
```

**Cómo se resuelve `mcps/`** (en este orden): `--mcps <dir>` → `EMCP_MCPS`
→ `<exe>/mcps` (instalación autocontenida) → `<exe>/../../mcps` (layout de
desarrollo `proyecto/zig-out/bin/`). Con `--mcps`/env puedes reubicar el
servidor sin depender de la estructura de carpetas.

Un JSON-RPC desconocido o una bandera inválida del CLI devuelven error y código
`!= 0` (no arrancan el servidor en silencio). En `tools/call`, `params`/`name`
faltantes o `arguments` no-objeto se responden con `-32602` **antes** de
ejecutar ningún MCP.

El mensaje firmado es el texto exacto:

```text
mcp-registro/1
<nombre>
<version>
<bin_sha256>
```

La clave del creador verificado se embebe en el binario y se puede cambiar sin
tocar el código:

```bat
zig build -Dcreador=<hex>
```

`-Dcreador` acepta una pubkey **x-only** (64 hex) o **comprimida** (66 hex,
prefijo `02`/`03`).

## Requisitos

- **Zig 0.16.0** (solo para compilar).
- El proyecto hermano **`mcp-crypto/`** (para la librería `secp256k1-fast`): el
  `build.zig` la referencia en `../mcp-crypto/secp256k1-fast/root.zig`.

Los MCPs que registres son binarios ya compilados (`mcp-time`, `mcp-math`,
`mcp-sys`, `mcp-crypto`, `mcp-ml`, `mcp-runner`); `emcp` no los compila.

## Compilación

```bat
cd emcp
zig build
```

> `zig build` ya compila en **ReleaseFast** (el orquestador parsea JSON en cada
> llamada). Para un binario más chico: `zig build -Doptimize=ReleaseSmall`.

Genera `zig-out/bin/emcp.exe`. Pasos del `build.zig`:

| Paso              | Qué hace                                           |
| ----------------- | -------------------------------------------------- |
| `zig build run`   | Compila y ejecuta el servidor                      |
| `zig build test`  | Corre los tests unitarios                          |
| `zig build linux` | Cross-compila (sin ejecutar) a `x86_64-linux-gnu`  |
| `zig build musl`  | Cross-compila (sin ejecutar) a `x86_64-linux-musl` |
| `zig build check` | `test` + `linux` + `musl`                          |

### Pruebas end-to-end (cliente MCP real)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/e2e.ps1
```

Arranca el servidor con **stdin ABIERTO** (uso real de una IA, sin cerrarlo) y
comprueba, con _watchdog_ por lectura: handshake, `tools/list` (todas las
herramientas registradas, bien formadas), que **todas responden sin cuelgues**,
llamadas reales por MCP, reutilización del pool (el flag `EMCP_POOL=0` se
ignora), errores `-32700/-32601/-32602`, el **tiempo límite** (una llamada lenta
se corta y la sesión se recrea) y que al salir **no quedan workers huérfanos**.
Sale con código `1` si algo falla.

## Uso

El lanzador `emcp` (o `emcp.cmd` en Windows) arranca el servidor
compilado sin rutas absolutas:

```bat
emcp
```

## Configuración en opencode

Una sola entrada, con el **nombre del comando**:

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

### Por qué el nombre aparece dos veces

No son lo mismo, solo coinciden por comodidad:

| Dónde                 | Qué es                                                                                            |
| --------------------- | ------------------------------------------------------------------------------------------------- |
| `"emcp": {` (clave)   | **Etiqueta** con la que verás el servidor en opencode. Podría llamarse `"herramientas"`.          |
| `"command": ["emcp"]` | **Programa real** que el sistema ejecuta para arrancar el servidor (el lanzador de esta carpeta). |

### Para qué sirve `enabled`

Interruptor: `true` lo activa, `false` lo desactiva sin borrar la configuración.

### Activar el nombre corto (una sola vez)

```bat
setx PATH "%PATH%;C:\EMC\GDRIVE\app-center\GITHUB\emcp"
```

Cierra y reabre la terminal u opencode para que tome el cambio.

## Workers persistentes (pool) y modo efímero

El protocolo MCP por `stdio` obliga a que el servidor esté abierto mientras dura
la sesión. Lo que se elige es **dónde vive el trabajo pesado**:

- **Servidor monolítico persistente**: todo el trabajo y sus datos se acumulan
  en un proceso durante toda la sesión.
- **Orquestador + MCPs** (este diseño): el servidor es delgado y delega en los
  binarios registrados.

Para el reenvío, `emcp` usa un **pool**: la primera llamada a un MCP abre
su worker y lo mantiene vivo; las siguientes solo escriben una petición y leen
una respuesta. Medido en Windows: **~10 ms → ~0,2 ms por llamada** en el camino
del orquestador (el cálculo del propio tool no cambia).

- **Anti-cuelgue**: cada lectura tiene un _deadline_ absoluto
  (`EMCP_TIMEOUT_MS`). Al vencer, se mata el árbol completo (Job Object en
  Windows) y la sesión se descarta; la siguiente llamada la recrea. Al salir el
  servidor, sus Jobs matan todos los workers: no quedan huérfanos.
- Los workers deben hacer **flush tras cada respuesta** (1 JSON por línea) para
  que el pool lea sin esperar al EOF; los 6 workers del repo lo cumplen.
- El pool es el único camino de `tools/call`; no hay modo efímero por llamada.
- Un MCP que necesite estado propio puede seguir siendo persistente (por
  ejemplo, `mcp-sys` con `job`).

## Contrato del MCP (cómo hacer un binario registrable)

Cualquier `.exe` sirve si cumple esto:

1. Sin argumentos: **servidor MCP** por stdio (1 JSON por línea; responde
   `initialize` + `tools/list` + `tools/call`).
2. Con argumentos: **CLI efímero** (resultado a `stdout`, código `!= 0` si falla).
3. `--registro` sin más args: imprime su **manifiesto** (1 JSON) y sale con `0`.
4. Trae su `<bin>.registro.json` (lo genera `emcp --generar-registro`).

Ver `../DEVELOPER.md` §2-§3 para el formato exacto.

## Módulos

```text
src/
├── main.zig            bucle stdio + dispatch JSON-RPC + CLI
├── root.zig            puerta del módulo reutilizable (tests)
├── registro.zig        identidad de ESTE servidor (versión/desc/meta-tools)
├── ayuda.zig           textos del CLI (`--help`)
├── core/
│   ├── proto.zig       transporte stdio + respuestas JSON-RPC
│   ├── jsonw.zig       escape JSON (eco de initialize)
│   ├── args.zig        lectura tolerante de `arguments`
│   ├── version.zig     versión del servidor (alias de `registro.zig`)
│   ├── registro.zig    parser del `registro.json` de terceros (formato)
│   ├── firma.zig       firmar/verificar secp256k1 (Schnorr BIP-340)
│   ├── run.zig         ejecución efímera + timeout + tree-kill
│   ├── proc.zig        utilidades de procesos (Job Object / kill grupo)
│   ├── mcp_client.zig  cliente MCP (reenvío efímero de tools/call)
│   └── pool.zig        workers persistentes (1 proceso por MCP) + deadline
└── mcp/
    ├── tools.zig       `tools/list`: meta-tools + MCPs registrados
    ├── registry.zig    MCPs registrados (mcps/index.json) + integridad + enrutado
    └── meta.zig        registrar / desregistrar / registrados + firma
```

- **`core/`** no sabe nada de herramientas concretas: transporte, JSON, args,
  registro, firma y ejecución de procesos.
- **`mcp/`** describe el registro y las meta-tools.

## Archivos

- `build.zig` / `build.zig.zon` — build y manifiesto (Zig 0.16.0).
- `src/` — servidor modular (ver arriba).
- `mcps/` — MCPs registrados en disco (`index.json` + `mcps/<nombre>/`).
- `tests/e2e.ps1` — pruebas end-to-end como cliente MCP real (ver arriba).
- `emcp.cmd` / `emcp` — lanzadores con el nombre corto
  (Windows / Linux-macOS); llaman al binario en `zig-out/bin/`.
