//! Textos de ayuda de emcp (fuente unica: CLI `--help`).
//! La version de la cabecera sale de `registro.zig` (fuente unica).

const registro = @import("registro.zig");

pub const USAGE_CLI =
    "emcp — orquestador MCP dinamico (Zig) v" ++ registro.VERSION ++ "\n" ++
    \\
    \\Sin argumentos: servidor MCP por stdio (expone los MCPs registrados).
    \\
    \\Opciones generales:
    \\  --version, -V           Imprime la version.
    \\  --verificar, --diag     Diagnostica mcps/index.json (existencia + hash + firma).
    \\                          Sale con codigo 2 si algun MCP no esta disponible.
    \\  --mcps <dir>            Carpeta mcps/ a usar. Por defecto: <exe>/mcps si
    \\                          existe; si no, <exe>/../../mcps (layout zig-out/bin).
    \\  Entorno:                EMCP_MCPS=<dir> y EMCP_TIMEOUT_MS=<ms>.
    \\                          El pool de workers persistentes esta siempre activo.
    \\
    \\Registro:
    \\  emcp --registro                 Imprime el manifiesto del servidor.
    \\  emcp --registrados              Lista los MCPs registrados.
    \\  emcp --registrar <origen> [opciones]
    \\        origen: ruta local a un binario o URL https://
    \\        Requiere el `<bin>.registro.json` hermano (hash + FIRMA obligatoria).
    \\        Si el nombre ya existe, se ACTUALIZA (no da error).
    \\        --nombre <n>   Nombre corto (^[a-z0-9][a-z0-9-]{0,30}$).
    \\        --tipo <t>     auto (por defecto) | mcp
    \\        --sha256 <h>   Hash esperado del binario (hex).
    \\        --forzar       Compatibilidad (ya no hace falta para actualizar).
    \\  emcp --desregistrar <nombre>    Quita un MCP registrado.
    \\
    \\Firma (secp256k1 / Schnorr BIP-340) — OBLIGATORIA para registrar:
    \\  emcp --generar-clave            Genera un par de claves (privada+publica).
    \\  emcp --generar-registro <bin> --clave HEX [--salida R]
    \\        Crea `<bin>.registro.json` desde `<bin> --registro` + su sha256.
    \\        --clave HEX (32 bytes) es OBLIGATORIA: el registro queda FIRMADO.
    \\  emcp --firmar <registro.json> --clave HEX
    \\        Firma/re-firma un registro existente.
    \\
    \\Los MCPs registrados se guardan en mcps/ y se exponen al reiniciar.
    \\Al arrancar, cada MCP se re-verifica UNA vez (sha256 + firma); en ejecucion
    \\no se repite, para que `tools/call` sea lo mas rapido posible.
    \\
;
