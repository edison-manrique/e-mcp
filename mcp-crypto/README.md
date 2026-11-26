# mcp-crypto — Servidor MCP de Criptografía y `secp256k1-fast` (Zig)

Servidor **MCP (Model Context Protocol)** por `stdio` y CLI efímero escrito en **Zig 0.17.0** sin dependencias externas. Incluye la librería `secp256k1-fast` (aritmética de curva con GLV, Schnorr BIP-340, ECDSA, BIP-32/39, vanity, Pollard's Kangaroo y cifrado AEAD ChaCha20/XChaCha20-Poly1305 multicore).

## Herramientas que expone

| Categoría | Herramientas |
|---|---|
| **Claves y BIP-32/39** | `derivar`, `generar`, `mnemonico` |
| **Firmas Schnorr (BIP-340)** | `firmar`, `verificar` |
| **Búsqueda y Puzzle** | `vanity`, `puzzle`, `entropia` |
| **Curva elíptica secp256k1** | `punto_mul`, `punto_add`, `punto_neg`, `punto_sub`, `punto_div`, `hexagono` |
| **Cifrado AEAD** | `cifrar`, `descifrar`, `poly1305` |
| **Ayuda** | `crypto_help` |

## Estructura del código

```text
mcp-crypto/
├── build.zig
├── build.zig.zon
├── secp256k1-fast/       # Librería criptográfica secp256k1 (GLV, Schnorr, BIP-32/39, Kangaroo)
└── src/
    ├── main.zig          # Dispatcher MCP y CLI
    ├── registro.zig      # Fuente única de identidad y schemas JSON-RPC
    ├── core/proto.zig    # Framing NDJSON y respuestas JSON-RPC 2.0
    ├── bc/               # Claves, firma y mnemónicos
    └── mcp/handlers.zig  # Handlers de herramientas MCP
```

## Pruebas unitarias (Zig 0.17.0)

```sh
zig test mcp-crypto/src/registro.zig
```

## Licencia

Distribuido bajo la licencia **Apache 2.0**. Consulta [../LICENSE](../LICENSE).

