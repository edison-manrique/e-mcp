# e-mcp

Orquestador dinámico de servidores **MCP (Model Context Protocol)** por `stdio` y colección de servidores MCP de alto rendimiento escritos en **Zig 0.17.0**.

## Estructura del proyecto

| Módulo | Descripción |
| :--- | :--- |
| `emcp/` | Orquestador MCP dinámico con pool de workers persistentes y verificación de firmas Schnorr (BIP-340). Ver [emcp/README.md](emcp/README.md). |
| `mcp-crypto/` | Herramientas criptográficas y librería `secp256k1-fast` (Schnorr, ECDSA, BIP-32/39, direcciones). |
| `mcp-math/` | Calculadora avanzada, enteros de precisión arbitraria y operaciones de curva elíptica. |
| `mcp-ml/` | Descubrimiento simbólico (SINDy/STLSQ), Koopman/EDMD, DMD, SVD, SequenceAI y PDE-FIND. Ver [mcp-ml/README.md](mcp-ml/README.md). |
| `mcp-runner/` | Compilación y ejecución rápida de código (Rust, Zig, C, C++, Python, TS, JS) en disco RAM. |
| `mcp-sys/` | Herramientas de sistema, búsqueda en archivos y ejecución controlada de comandos. |
| `mcp-time/` | Zonas horarias, fechas en español, días laborables/feriados, épocas y formato `strftime`. Ver [mcp-time/README.md](mcp-time/README.md). |

## Requisitos

- **Zig 0.17.0**

## Uso rápido con `emcp`

Configura `emcp` como servidor MCP local en tu cliente (por ejemplo OpenCode):

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

## Licencia

Distribuido bajo la licencia **Apache 2.0**. Consulta el archivo [LICENSE](LICENSE) para más detalles.
