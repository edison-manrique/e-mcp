# mcp-math — Motor Matemático MCP (Zig)

Servidor **MCP (Model Context Protocol)** por `stdio` y CLI efímero escrito en **Zig 0.17.0** sin dependencias externas. Combina evaluación de expresiones matemáticas, aritmética de precisión arbitraria (`bigint` / `abig`), aritmética modular en $\mathbb{F}_p$ y operaciones sobre curvas elípticas.

## Herramientas que expone

| Herramienta | Qué hace |
|---|---|
| `calc` | Evalúa expresiones matemáticas (`expr`, `digits`, `frac`) con soporte de fracciones exactas. |
| `big` | Aritmética de precisión arbitraria (`add`, `sub`, `mul`, `div`, `mod`, `gcd`, `cmp`), punto flotante de alta precisión (`fadd`, `fsub`, `fmul`, `fdiv`, `fsqrt`), aritmética modular (`madd`, `msub`, `mmul`, `mdiv`, `mpow`, `msqrt`) y curvas elípticas (`econcurve`, `ecadd`, `ecneg`, `ecmul`, `ecgen`, `ecdecomp`, `ecenum`, `ecord`). |
| `math_help` | Ayuda integrada en Markdown (`topic`: `all\|ops\|ejemplos\|calc\|big`). |

## Estructura del código

```text
mcp-math/
├── src/
│   ├── main.zig          # Dispatcher MCP (stdio) y CLI (--expr, --op, --registro, --help)
│   ├── protocol.zig      # Framing NDJSON y respuestas JSON-RPC 2.0
│   ├── abig/float.zig    # Flotantes de precisión arbitraria (1..500 dígitos)
│   ├── bigint/
│   │   ├── addsub.zig    # Suma y resta de enteros grandes
│   │   └── reduce.zig    # Reducción modular de enteros grandes
│   └── ec/
│       ├── field.zig     # Campo finito F_p
│       └── curve.zig     # Operaciones de curva elíptica
└── README.md
```

## Uso en modo CLI

```sh
math --version
math --registro
math --expr "2^10 + sqrt(144)" --digits 6
math --op add --a 99999999999999999999 --b 1
math --help
```

## Pruebas unitarias (Zig 0.17.0)

```sh
zig test mcp-math/src/protocol.zig
zig test mcp-math/src/bigint/addsub.zig
```

## Licencia

Distribuido bajo la licencia **Apache 2.0**. Consulta [../LICENSE](../LICENSE).

