// Raíz de tests de la librería secp256k1-fast.
//
// No forma parte del árbol de importación del servidor: existe para que
// `zig build test` pueda ejecutar los tests que viven fuera de `root.zig`
// (motor de entropía + ChaCha20 en `rng/`, y la suite de aritmética de
// campo/bigint en `bigint/tests.zig`). La raíz de esta raíz de tests es
// `secp256k1-fast/`, así que los imports relativos hacia `rng/*` y
// `bigint/*` son válidos.

test {
    _ = @import("rng/chacha20.zig");
    _ = @import("rng/entropy.zig");
    _ = @import("bigint/tests.zig");
    _ = @import("generator/tests.zig");
    _ = @import("glv/tests.zig");
    _ = @import("schnorr/tests.zig");
    _ = @import("bip39/tests.zig");
}
