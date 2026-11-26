# mcp-sys — Servidor MCP de Sistema y Archivos (Zig)

Servidor **MCP (Model Context Protocol)** por `stdio` escrito en **Zig 0.17.0** sin dependencias externas para ejecutar comandos, gestionar trabajos en segundo plano, leer/escribir/editar archivos y buscar texto o rutas en el sistema de archivos.

## Herramientas que expone

| Herramienta | Qué hace |
|---|---|
| `exec` | Ejecuta un comando shell con `timeout_ms`, `cwd` y control de salida. |
| `job` | Gestiona comandos en segundo plano (`start`, estado, logs). |
| `read` / `write` / `edit` | Lectura paginada, escritura y edición quirúrgica de archivos. |
| `search` / `list` | Búsqueda de texto (con regex/glob) y listado de directorios. |
| `sys` | Operaciones de sistema (`info`, `env`, `stat`, `mkdir`, `rm`, `mv`, `cp`). |
| `sys_help` | Ayuda integrada en Markdown (`topic`: `all\|exec\|fs\|sys`). |

## Estructura del código

```text
mcp-sys/
├── src/
│   ├── root.zig          # Re-exportación de módulos
│   ├── ayuda.zig         # Textos de ayuda Markdown y sugerencias CLI
│   ├── cli/              # Utilidades y dispatcher CLI
│   ├── core/             # Protocolo JSON-RPC y herramientas de sistema
│   ├── exec/job.zig      # Ejecución asíncrona de trabajos
│   ├── fs/fssearch.zig   # Búsqueda en sistema de archivos
│   ├── mcp/              # Handlers de exec y search
│   └── regex/tests.zig   # Pruebas del motor regex
├── tests/unix.sh
└── README.md
```

## Licencia

Distribuido bajo la licencia **Apache 2.0**. Consulta [../LICENSE](../LICENSE).

