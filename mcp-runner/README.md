# mcp-runner — Runner Multi-lenguaje en Disco RAM (Zig)

Servidor **MCP (Model Context Protocol)** escrito en **Zig 0.17.0** para compilar y ejecutar código fuente de forma aislada y rápida en disco RAM (`R:\runner` por defecto).

## Herramientas que expone

| Herramienta | Qué hace |
|---|---|
| `run_code` | Compila y ejecuta código en `rust`, `zig`, `c`, `cpp`, `python`, `ts` o `js` (`code` o `file`, `ramdisk`, `max_bytes`, `timeout_ms`). |
| `runner_help` | Ayuda en Markdown (`topic`: `all\|run_code`). |

## Estructura del código

```text
mcp-runner/
├── src/
│   └── registro.zig      # Fuente única de identidad y schemas JSON-RPC
├── test/
│   ├── safe.ps1          # Pruebas de seguridad y límites
│   └── timing.py         # Benchmark de latencia
└── README.md
```

## Pruebas unitarias (Zig 0.17.0)

```sh
zig test mcp-runner/src/registro.zig
```

## Licencia

Distribuido bajo la licencia **Apache 2.0**. Consulta [../LICENSE](../LICENSE).

