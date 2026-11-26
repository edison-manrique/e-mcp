//! Fuente UNICA de identidad y herramientas de mcp-crypto.
//!
//! Lo consumen `--registro` (manifiesto firmado), `tools/list` (schemas) y la
//! ayuda. Actualizar version, descripcion o herramientas = editar SOLO aqui;
//! `comandos` y el manifiesto se derivan en comptime.

// ---------- Identidad ----------
pub const NOMBRE = "mcp-crypto";
pub const SERVIDOR = "mcp-crypto";
pub const VERSION = "1.10.0";
pub const DESCRIPCION = "Claves y direcciones BTC/ETH, BIP-39, Schnorr, ECDSA, vanity, puzzle, aritmetica de puntos secp256k1 (GLV) y cifrado AEAD de texto/archivos (ChaCha20/XChaCha20-Poly1305) con multicore adaptativo.";
pub const PROTOCOLO = "2024-11-05";

// ---------- Herramientas (nombre + schema para `tools/list`) ----------
pub const DERIVAR = "derivar";
pub const GENERAR = "generar";
pub const MNEMONICO = "mnemonico";
pub const FIRMAR = "firmar";
pub const VERIFICAR = "verificar";
pub const VANITY = "vanity";
pub const PUZZLE = "puzzle";
pub const ENTROPIA = "entropia";
pub const PUNTO_MUL = "punto_mul";
pub const PUNTO_ADD = "punto_add";
pub const PUNTO_NEG = "punto_neg";
pub const PUNTO_SUB = "punto_sub";
pub const PUNTO_DIV = "punto_div";
pub const HEXAGONO = "hexagono";
pub const CIFRAR = "cifrar";
pub const DESCIFRAR = "descifrar";
pub const POLY1305 = "poly1305";
pub const AYUDA = "crypto_help";

pub const JSON_DERIVAR =
    "{\"name\":\"derivar\",\"description\":\"Deriva direcciones BTC/ETH, pubkeys, WIF y decimal desde una clave privada. Tambien acepta un mnemotico BIP-39 (mnemonico|frase) y deriva la clave de la ruta estandar del tipo (p2pkh m/44', p2sh m/49', p2wpkh m/84', p2tr m/86', eth m/44'/60') o de 'ruta'. Parametros: clave (hex de 64 o con 0x, decimal, o WIF '5/K/L...') O mnemonico|frase; tipo; ruta; cuenta/cambio/indice; passphrase; idioma (en|es; si lo omites se autodetecta).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"clave\":{\"type\":\"string\",\"description\":\"Clave privada: hex (64, opcional 0x), decimal, o WIF\"},\"mnemonico\":{\"type\":\"string\",\"description\":\"Frase BIP-39 de la que derivar (alternativa a 'clave')\"},\"frase\":{\"type\":\"string\",\"description\":\"Alias de mnemonico\"},\"tipo\":{\"type\":\"string\",\"enum\":[\"p2pkh\",\"p2sh\",\"p2wpkh\",\"p2tr\",\"eth\",\"btc-p2pkh\",\"btc-p2sh\",\"btc-p2wpkh\",\"btc-segwit\",\"btc-p2tr\",\"btc-taproot\",\"ethereum\"],\"description\":\"Ruta estandar si el origen es un mnemotico (def p2pkh)\"},\"ruta\":{\"type\":\"string\",\"description\":\"Ruta BIP-32 explicita (ignora tipo/cuenta/cambio/indice)\"},\"cuenta\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647,\"default\":0},\"cambio\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647,\"default\":0},\"indice\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647,\"default\":0},\"passphrase\":{\"type\":\"string\"},\"idioma\":{\"type\":\"string\",\"enum\":[\"en\",\"es\"],\"description\":\"Diccionario BIP-39; si lo omites se autodetecta\"}},\"examples\":[{\"clave\":\"0000000000000000000000000000000000000000000000000000000000000001\"},{\"mnemonico\":\"abandon ability able about above absent absorb abstract absurd abuse access accident\",\"tipo\":\"p2wpkh\",\"indice\":5}],\"additionalProperties\":false}}";

pub const JSON_GENERAR =
    "{\"name\":\"generar\",\"description\":\"Genera N claves privadas aleatorias con su direccion, pubkey y WIF. Entropia del sistema por defecto (ChaCha20 + SHA-256 con fuentes del SO, jitter y ASLR; funciona en VPS sin CSPRNG). Determinista si pasas semilla (CUALQUIER texto, se hashea con SHA-256) o semilla_hex (32 bytes hex, expert). Parametros: tipo (p2pkh|p2sh|p2wpkh|p2tr|eth; alias btc-p2pkh, btc-segwit, btc-taproot, ethereum), cantidad (1-1000), comprimida, semilla, semilla_hex.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"tipo\":{\"type\":\"string\",\"enum\":[\"p2pkh\",\"p2sh\",\"p2wpkh\",\"p2tr\",\"eth\",\"btc-p2pkh\",\"btc-p2sh\",\"btc-p2wpkh\",\"btc-segwit\",\"btc-p2tr\",\"btc-taproot\",\"ethereum\"],\"default\":\"p2pkh\"},\"cantidad\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000,\"default\":1},\"comprimida\":{\"type\":\"boolean\",\"default\":true},\"semilla\":{\"type\":\"string\",\"description\":\"Cualquier texto; se hashea (SHA-256) y define la secuencia\"},\"semilla_hex\":{\"type\":\"string\",\"description\":\"Expert: material crudo de 32 bytes en hex\"}},\"examples\":[{\"tipo\":\"p2wpkh\",\"cantidad\":3},{\"tipo\":\"eth\",\"cantidad\":1}],\"additionalProperties\":false}}";

pub const JSON_MNEMONICO =
    "{\"name\":\"mnemonico\",\"description\":\"Genera N mnemonicos BIP-39 aleatorios (12/15/18/21/24 palabras) y deriva sus direcciones BIP-44/49/84/86. Si pasas 'mnemonico' (o 'frase') con una frase existente, la valida y deriva SUS direcciones (no genera). Parametros: palabras (12|15|18|21|24, def 12), cantidad (1-20, def 1; ignorado si das una frase), passphrase (frase de paso BIP-39), tipo (todos|p2pkh|p2sh|p2wpkh|p2tr|eth; alias), ruta (ruta BIP-32 explicita, ej. m/84'/0'/0'/0/0; ignora cuenta/cambio/indice), cuenta/cambio/indice (componentes BIP-44, def 0), semilla (cualquier texto, se hashea) / semilla_hex, idioma (en|es; diccionario BIP-39 espanol en NFKD; si omites idioma al derivar una frase, se autodetecta en|es).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"mnemonico\":{\"type\":\"string\",\"description\":\"Frase BIP-39 existente a derivar (opcional)\"},\"frase\":{\"type\":\"string\",\"description\":\"Alias de mnemonico\"},\"palabras\":{\"type\":\"integer\",\"enum\":[12,15,18,21,24],\"default\":12},\"cantidad\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":20},\"passphrase\":{\"type\":\"string\"},\"idioma\":{\"type\":\"string\",\"enum\":[\"en\",\"es\"],\"description\":\"Diccionario BIP-39: en o es; si lo omites al derivar una frase, se autodetecta\"},\"tipo\":{\"type\":\"string\",\"enum\":[\"todos\",\"p2pkh\",\"p2sh\",\"p2wpkh\",\"p2tr\",\"eth\",\"btc-p2pkh\",\"btc-p2sh\",\"btc-p2wpkh\",\"btc-segwit\",\"btc-p2tr\",\"btc-taproot\",\"ethereum\"]},\"ruta\":{\"type\":\"string\"},\"cuenta\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647,\"default\":0},\"cambio\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647,\"default\":0},\"indice\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647,\"default\":0},\"semilla\":{\"type\":\"string\"},\"semilla_hex\":{\"type\":\"string\"}},\"examples\":[{\"palabras\":24,\"cantidad\":2,\"tipo\":\"todos\"},{\"mnemonico\":\"abandon ability able about above absent absorb abstract absurd abuse access accident\",\"tipo\":\"p2wpkh\"}],\"additionalProperties\":false}}";

pub const JSON_FIRMAR =
    "{\"name\":\"firmar\",\"description\":\"Firma Schnorr BIP-340 (x-only) de un mensaje con una clave privada. Rapido y NO constant-time (pensado para entornos seguros), sin MuSig. Parametros: clave (hex de 64, decimal o WIF), mensaje (texto UTF-8) o mensaje_hex (hex, prioritario), hasta 1024 bytes (vacio valido), aux (32 bytes hex; si falta se deriva del motor de entropia, o de semilla/semilla_hex para reproducir). Salida: pubkey_xonly, firma (r||s), r, s, aux usada y mensaje_hex.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"clave\":{\"type\":\"string\",\"description\":\"Clave privada: hex (64, opcional 0x), decimal, o WIF\"},\"mensaje\":{\"type\":\"string\",\"description\":\"Mensaje en texto (UTF-8), hasta 1024 bytes; vacio es valido\"},\"mensaje_hex\":{\"type\":\"string\",\"description\":\"Mensaje en hex (tiene prioridad sobre 'mensaje'; hasta 1024 bytes)\"},\"aux\":{\"type\":\"string\",\"description\":\"Aleatoriedad auxiliar BIP-340: 32 bytes en hex\"},\"semilla\":{\"type\":\"string\",\"description\":\"Texto para derivar la 'aux' de forma reproducible\"},\"semilla_hex\":{\"type\":\"string\",\"description\":\"Expert: material crudo de 32 bytes en hex\"}},\"examples\":[{\"clave\":\"0000000000000000000000000000000000000000000000000000000000000001\",\"mensaje\":\"hola\"}],\"required\":[\"clave\"],\"additionalProperties\":false}}";

pub const JSON_VERIFICAR =
    "{\"name\":\"verificar\",\"description\":\"Verifica una firma Schnorr BIP-340. Una firma invalida NO es error: devuelve valida=false. Parametros: pubkey (x-only de 32 bytes hex, o comprimida 02/03... de 33), firma (64 bytes hex = r||s), mensaje (texto UTF-8) o mensaje_hex (hex, prioritario), hasta 1024 bytes (vacio valido).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey\":{\"type\":\"string\",\"description\":\"Clave publica x-only (64 hex) o comprimida (66 hex)\"},\"clave_publica\":{\"type\":\"string\",\"description\":\"Alias de 'pubkey'\"},\"firma\":{\"type\":\"string\",\"description\":\"Firma BIP-340: 64 bytes en hex (r||s)\"},\"mensaje\":{\"type\":\"string\",\"description\":\"Mensaje en texto (UTF-8), hasta 1024 bytes; vacio es valido\"},\"mensaje_hex\":{\"type\":\"string\",\"description\":\"Mensaje en hex (tiene prioridad; hasta 1024 bytes)\"}},\"examples\":[{\"pubkey\":\"f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\",\"firma\":\"e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0\",\"mensaje\":\"hola\"}],\"required\":[\"pubkey\",\"firma\"],\"additionalProperties\":false}}";

pub const JSON_VANITY =
    "{\"name\":\"vanity\",\"description\":\"Busca direcciones vanity (multihilo, presupuesto de tiempo). El patron debe usar el alfabeto del tipo (eth: hex sin 0x; p2pkh/p2sh: Base58 sin 0 O I l; p2wpkh/p2tr: bech32) o se rechaza. Parametros: patron (o patrones[]), tipo (p2pkh|p2sh|p2wpkh|p2tr|eth; alias btc-p2pkh, btc-segwit, btc-taproot, ethereum), modo (prefijo|sufijo|contiene; alias empieza|termina), sensible, cantidad (max resultados, def 1), segundos/max_time (1-120, def 15), max_intentos, hilos, semilla (cualquier texto, se hashea) / semilla_hex.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"patron\":{\"type\":\"string\",\"description\":\"Patron a buscar, ej. '777' o 'dead'\"},\"patrones\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"maxItems\":8},\"tipo\":{\"type\":\"string\",\"enum\":[\"p2pkh\",\"p2sh\",\"p2wpkh\",\"p2tr\",\"eth\",\"btc-p2pkh\",\"btc-p2sh\",\"btc-p2wpkh\",\"btc-segwit\",\"btc-p2tr\",\"btc-taproot\",\"ethereum\"],\"default\":\"p2pkh\"},\"modo\":{\"type\":\"string\",\"enum\":[\"prefijo\",\"sufijo\",\"contiene\",\"empieza\",\"termina\"],\"default\":\"prefijo\"},\"sensible\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Distinguir mayusculas/minusculas (def false = insensitivo)\"},\"cantidad\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":1000,\"default\":1},\"segundos\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":120,\"default\":15},\"max_time\":{\"type\":\"integer\",\"description\":\"Alias de segundos\"},\"max_intentos\":{\"type\":\"integer\"},\"hilos\":{\"type\":\"integer\",\"description\":\"0 = todos los nucleos\"},\"semilla\":{\"type\":\"string\",\"description\":\"Cualquier texto; se hashea (SHA-256)\"},\"semilla_hex\":{\"type\":\"string\"}},\"examples\":[{\"patron\":\"777\",\"tipo\":\"p2pkh\",\"segundos\":15},{\"patrones\":[\"dead\",\"beef\"],\"tipo\":\"eth\",\"modo\":\"prefijo\"}],\"additionalProperties\":false}}";

pub const JSON_PUZZLE =
    "{\"name\":\"puzzle\",\"description\":\"Resuelve el logaritmo discreto (puzzle de Bitcoin) con Pollard's Kangaroo, con presupuesto de tiempo. Parametros: pubkey (hex 33/65), bits (2-256) o rango ('min:max' hex), segundos/max_time (1-120, def 30), max_iteraciones, hilos, dist_bits, jump_size, semilla (cualquier texto; perturba la tabla de saltos).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey\":{\"type\":\"string\",\"description\":\"Clave publica objetivo: 02/03... (33B) o 04... (65B)\"},\"bits\":{\"type\":\"integer\",\"minimum\":2,\"maximum\":256,\"description\":\"Rango [2^(bits-1), 2^bits-1]\"},\"rango\":{\"type\":\"string\",\"description\":\"Rango explicito 'min:max' en hex\"},\"segundos\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":120,\"default\":30},\"max_time\":{\"type\":\"integer\"},\"max_iteraciones\":{\"type\":\"integer\"},\"hilos\":{\"type\":\"integer\"},\"dist_bits\":{\"type\":\"integer\"},\"jump_size\":{\"type\":\"integer\"},\"semilla\":{\"type\":\"string\"},\"semilla_hex\":{\"type\":\"string\"}},\"examples\":[{\"pubkey\":\"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798\",\"bits\":40,\"segundos\":30}],\"required\":[\"pubkey\"],\"additionalProperties\":false}}";

pub const JSON_ENTROPIA =
    "{\"name\":\"entropia\",\"description\":\"Diagnostico del motor de entropia: prueba de humo (16 muestras, sin duplicados ni bits clavados), self-test SHA-256 (KAT) y QUE FUENTES DEL SO estan disponibles (getrandom/bcrypt/arc4random/urandom) mas jitter y ASLR. Util en VPS/sandbox para saber si hay CSPRNG del sistema. Sin parametros.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{},\"examples\":[{}],\"additionalProperties\":false}}";

pub const JSON_PUNTO_MUL =
    "{\"name\":\"punto_mul\",\"description\":\"Multiplica un punto secp256k1 por un escalar: R = k*P (GLV, microsegundos). P: x-only de 64 hex, comprimida de 66, sin comprimir de 130, o 'generador'. Escalar: hex de hasta 64 digitos o decimal, 1..N-1 (solo digitos = decimal; prefija 0x para hex). Salida: pubkeys comprimida/sin comprimir, X/Y decimal y hex, paridad_y, on_curve (o infinito:true).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey\":{\"type\":\"string\",\"description\":\"Punto: x-only 64 hex, comprimida 66, sin comprimir 130, o 'generador' (def)\"},\"escalar\":{\"type\":\"string\",\"description\":\"k en hex (hasta 64 digitos) o decimal, 1..N-1 (solo digitos = decimal; 0x fuerza hex)\"},\"y_impar\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Solo x-only: elige Y impar (def par, BIP-340)\"}},\"examples\":[{\"pubkey\":\"generador\",\"escalar\":\"2\"},{\"pubkey\":\"02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\",\"escalar\":\"deadbeef\"}],\"required\":[\"escalar\"],\"additionalProperties\":false}}";

pub const JSON_PUNTO_ADD =
    "{\"name\":\"punto_add\",\"description\":\"Suma dos puntos secp256k1: R = A + B. Si A = -B devuelve infinito:true. Acepta x-only de 64 hex, comprimida de 66 o sin comprimir de 130.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey_a\":{\"type\":\"string\",\"description\":\"Primer punto (x-only/33/65)\"},\"pubkey_b\":{\"type\":\"string\",\"description\":\"Segundo punto (x-only/33/65)\"},\"y_impar\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Solo x-only: elige Y impar (def par)\"}},\"examples\":[{\"pubkey_a\":\"02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\",\"pubkey_b\":\"03f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\"}],\"required\":[\"pubkey_a\",\"pubkey_b\"],\"additionalProperties\":false}}";

pub const JSON_PUNTO_NEG =
    "{\"name\":\"punto_neg\",\"description\":\"Niega un punto secp256k1: -P (flipa la paridad de Y; X no cambia).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey\":{\"type\":\"string\",\"description\":\"Punto (x-only/33/65)\"},\"y_impar\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Solo x-only: elige Y impar (def par)\"}},\"examples\":[{\"pubkey\":\"02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\"}],\"required\":[\"pubkey\"],\"additionalProperties\":false}}";

pub const JSON_PUNTO_SUB =
    "{\"name\":\"punto_sub\",\"description\":\"Resta dos puntos secp256k1: R = A - B (A + -B). Si A = B devuelve infinito:true. Acepta x-only de 64 hex, comprimida de 66 o sin comprimir de 130.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey_a\":{\"type\":\"string\",\"description\":\"Minuendo (x-only/33/65)\"},\"pubkey_b\":{\"type\":\"string\",\"description\":\"Sustraendo (x-only/33/65)\"},\"y_impar\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Solo x-only: elige Y impar (def par)\"}},\"examples\":[{\"pubkey_a\":\"02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\",\"pubkey_b\":\"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798\"}],\"required\":[\"pubkey_a\",\"pubkey_b\"],\"additionalProperties\":false}}";

pub const JSON_PUNTO_DIV =
    "{\"name\":\"punto_div\",\"description\":\"Divide un punto secp256k1 por un escalar: P/m = (m^-1 mod N)*P. Siempre existe y es unico: (P/m)*m = P (N es primo, m en 1..N-1). Con m=2 es la mitad del punto; con m=3, el punto que triplicado da P. El escalar solo-digitos se lee como decimal; prefija 0x para hex. Salida: resultado + verificado (ida y vuelta).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey\":{\"type\":\"string\",\"description\":\"Punto (x-only/33/65)\"},\"divisor\":{\"type\":[\"string\",\"integer\"],\"default\":2,\"description\":\"m: hex o decimal, 1..N-1 (def 2); solo digitos = decimal, 0x fuerza hex\"},\"y_impar\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Solo x-only: elige Y impar (def par)\"}},\"examples\":[{\"pubkey\":\"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5\",\"divisor\":2},{\"pubkey\":\"022f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4\",\"divisor\":3}],\"required\":[\"pubkey\"],\"additionalProperties\":false}}";

pub const JSON_HEXAGONO =
    "{\"name\":\"hexagono\",\"description\":\"Hexagono GLV de un punto: 3 X {X, beta*X, beta^2*X} y 6 vertices {+-P, +-lambda*P, +-lambda^2*P}. Con 'escalar' anade los 6 escalares y verifica X(lambda*P)=beta*X, X(lambda^2*P)=beta^2*X y phi(P)=lambda*P. Con pubkey y escalar a la vez exige que coincidan (P = k*G).\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pubkey\":{\"type\":\"string\",\"description\":\"Punto (x-only/33/65) o 'generador'; opcional si das escalar\"},\"escalar\":{\"type\":\"string\",\"description\":\"k en hex o decimal, 1..N-1; opcional si das pubkey (solo digitos = decimal; 0x fuerza hex)\"},\"y_impar\":{\"type\":\"boolean\",\"default\":false,\"description\":\"Solo x-only: elige Y impar (def par)\"}},\"examples\":[{\"escalar\":\"1\"},{\"pubkey\":\"02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9\"}],\"additionalProperties\":false}}";

pub const JSON_CIFRAR =
    "{\"name\":\"cifrar\",\"description\":\"Cifra texto o archivos. Algoritmos: xchacha20poly1305 (def), chacha20poly1305, xchacha20, chacha20. Para archivo usa 'ruta' (y opcional 'salida'); se escribe un contenedor MCPC con algoritmo+nonce y tag AEAD al final. hilos=0 auto: usa multicore solo si el dato es grande; 1 fuerza un core. Si omites clave/nonce se generan al azar y se devuelven. Salida texto: ciphertext_hex, tag, combinado_hex, clave_hex, nonce_hex. Salida archivo: ruta, salida, bytes, bytes_archivo, hilos, paralelo, tag. ChaCha20/XChaCha20 solos NO autentican.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"algoritmo\":{\"type\":\"string\",\"enum\":[\"xchacha20poly1305\",\"chacha20poly1305\",\"xchacha20\",\"chacha20\"],\"default\":\"xchacha20poly1305\"},\"clave\":{\"type\":\"string\",\"description\":\"Clave de 32 bytes en hex (64 digitos). Si falta se genera\"},\"nonce\":{\"type\":\"string\",\"description\":\"12 bytes (24 hex) para chacha20; 24 bytes (48 hex) para xchacha20. Si falta se genera\"},\"texto\":{\"type\":\"string\",\"description\":\"Texto UTF-8 a cifrar\"},\"texto_hex\":{\"type\":\"string\",\"description\":\"Datos binarios en hex (prioritario sobre texto)\"},\"ruta\":{\"type\":\"string\",\"description\":\"Archivo de entrada. Si se usa, no envies texto/texto_hex\"},\"salida\":{\"type\":\"string\",\"description\":\"Archivo de salida. Por defecto <ruta>.enc\"},\"hilos\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":256,\"default\":0,\"description\":\"0 = auto (multicore solo para datos grandes); 1 = un core; >1 = maximo de hilos\"},\"aad\":{\"type\":\"string\",\"description\":\"Datos asociados (texto UTF-8); solo AEAD\"},\"aad_hex\":{\"type\":\"string\",\"description\":\"Datos asociados en hex (prioritario); solo AEAD\"}},\"examples\":[{\"algoritmo\":\"xchacha20poly1305\",\"texto\":\"hola mundo\",\"aad\":\"cabecera\"},{\"algoritmo\":\"xchacha20poly1305\",\"ruta\":\"C:\\\\datos\\\\informe.pdf\",\"hilos\":0},{\"algoritmo\":\"chacha20\",\"texto\":\"flujo sin autenticar\"}],\"additionalProperties\":false}}";

pub const JSON_DESCIFRAR =
    "{\"name\":\"descifrar\",\"description\":\"Descifra texto o archivos. Con 'ruta' lee el contenedor MCPC (algoritmo y nonce incluidos), verifica el tag AEAD en una primera pasada y solo escribe la salida si es valido. Sin 'ruta' acepta combinado_hex (ciphertext||tag) o ciphertext_hex + tag; si el tag no cuadra devuelve valido=false y NO entrega plaintext. hilos=0 auto. La clave siempre es obligatoria.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"algoritmo\":{\"type\":\"string\",\"enum\":[\"xchacha20poly1305\",\"chacha20poly1305\",\"xchacha20\",\"chacha20\"],\"description\":\"Opcional en modo archivo (se lee de la cabecera); en texto, def xchacha20poly1305\"},\"clave\":{\"type\":\"string\",\"description\":\"Clave de 32 bytes en hex (64 digitos)\"},\"nonce\":{\"type\":\"string\",\"description\":\"12 bytes (24 hex) para chacha20; 24 bytes (48 hex) para xchacha20. En modo archivo es opcional y debe coincidir con la cabecera\"},\"combinado_hex\":{\"type\":\"string\",\"description\":\"ciphertext || tag (prioritario)\"},\"ciphertext_hex\":{\"type\":\"string\",\"description\":\"Ciphertext sin tag (requiere 'tag')\"},\"tag\":{\"type\":\"string\",\"description\":\"Tag Poly1305 de 16 bytes en hex\"},\"ruta\":{\"type\":\"string\",\"description\":\"Archivo cifrado de entrada. Si se usa, no envies ciphertext\"},\"salida\":{\"type\":\"string\",\"description\":\"Archivo de salida. Por defecto quita .enc o usa <ruta>.dec\"},\"hilos\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":256,\"default\":0,\"description\":\"0 = auto (multicore solo para datos grandes); 1 = un core; >1 = maximo de hilos\"},\"aad\":{\"type\":\"string\"},\"aad_hex\":{\"type\":\"string\"}},\"required\":[\"clave\"],\"examples\":[{\"algoritmo\":\"xchacha20poly1305\",\"combinado_hex\":\"...\",\"clave\":\"...\",\"nonce\":\"...\"},{\"ruta\":\"C:\\\\datos\\\\informe.pdf.enc\",\"clave\":\"...\"}],\"additionalProperties\":false}}";

pub const JSON_POLY1305 =
    "{\"name\":\"poly1305\",\"description\":\"Calcula el MAC Poly1305 (16 bytes) de un mensaje con clave de 32 bytes (r||s). Parametros: clave (32 B hex, obligatoria), mensaje (texto UTF-8) o mensaje_hex (prioritario). Salida: tag hex, bytes y clave_hex.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"clave\":{\"type\":\"string\",\"description\":\"Clave de 32 bytes en hex (64 digitos)\"},\"mensaje\":{\"type\":\"string\",\"description\":\"Mensaje UTF-8\"},\"mensaje_hex\":{\"type\":\"string\",\"description\":\"Mensaje binario en hex (prioritario)\"}},\"required\":[\"clave\"],\"examples\":[{\"clave\":\"85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b\",\"mensaje\":\"Cryptographic Forum Research Group\"}],\"additionalProperties\":false}}";

pub const JSON_AYUDA =
    "{\"name\":\"crypto_help\",\"description\":\"Ayuda en Markdown. Parametro topic: all|derivar|generar|mnemonico|firmar|verificar|vanity|puzzle|entropia|cifrar|descifrar|poly1305|aead|puntos|punto_mul|punto_add|punto_neg|punto_sub|punto_div|hexagono|tipos|aviso.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"topic\":{\"type\":\"string\",\"enum\":[\"all\",\"derivar\",\"generar\",\"mnemonico\",\"firmar\",\"verificar\",\"vanity\",\"puzzle\",\"entropia\",\"cifrar\",\"descifrar\",\"poly1305\",\"aead\",\"puntos\",\"punto_mul\",\"punto_add\",\"punto_neg\",\"punto_sub\",\"punto_div\",\"hexagono\",\"tipos\",\"aviso\"]}},\"examples\":[{\"topic\":\"cifrar\"}],\"additionalProperties\":false}}";

pub const Herramienta = struct {
    nombre: []const u8,
    json: []const u8,
};

/// Orden canonico de `tools/list` y del manifiesto.
pub const HERRAMIENTAS = [_]Herramienta{
    .{ .nombre = DERIVAR, .json = JSON_DERIVAR },
    .{ .nombre = GENERAR, .json = JSON_GENERAR },
    .{ .nombre = MNEMONICO, .json = JSON_MNEMONICO },
    .{ .nombre = FIRMAR, .json = JSON_FIRMAR },
    .{ .nombre = VERIFICAR, .json = JSON_VERIFICAR },
    .{ .nombre = VANITY, .json = JSON_VANITY },
    .{ .nombre = PUZZLE, .json = JSON_PUZZLE },
    .{ .nombre = ENTROPIA, .json = JSON_ENTROPIA },
    .{ .nombre = CIFRAR, .json = JSON_CIFRAR },
    .{ .nombre = DESCIFRAR, .json = JSON_DESCIFRAR },
    .{ .nombre = POLY1305, .json = JSON_POLY1305 },
    .{ .nombre = PUNTO_MUL, .json = JSON_PUNTO_MUL },
    .{ .nombre = PUNTO_ADD, .json = JSON_PUNTO_ADD },
    .{ .nombre = PUNTO_NEG, .json = JSON_PUNTO_NEG },
    .{ .nombre = PUNTO_SUB, .json = JSON_PUNTO_SUB },
    .{ .nombre = PUNTO_DIV, .json = JSON_PUNTO_DIV },
    .{ .nombre = HEXAGONO, .json = JSON_HEXAGONO },
    .{ .nombre = AYUDA, .json = JSON_AYUDA },
};

/// Nombres de herramienta derivados (manifiesto). Sin duplicacion manual.
pub const COMANDOS = blk: {
    var out: [HERRAMIENTAS.len][]const u8 = undefined;
    for (HERRAMIENTAS, 0..) |h, i| out[i] = h.nombre;
    break :blk out;
};

/// Manifiesto de `--registro`, generado en comptime desde esta fuente unica.
pub const MANIFIESTO = blk: {
    var s: []const u8 = "{\"registro\":1,\"nombre\":\"" ++ NOMBRE ++
        "\",\"version\":\"" ++ VERSION ++ "\",\"descripcion\":\"" ++ DESCRIPCION ++
        "\",\"tipo\":\"mcp\",\"protocolo\":\"" ++ PROTOCOLO ++ "\",\"comandos\":[";
    for (COMANDOS, 0..) |c, i| {
        if (i > 0) s = s ++ ",";
        s = s ++ "\"" ++ c ++ "\"";
    }
    s = s ++ "],\"ayuda\":\"" ++ NOMBRE ++ " --help [tema]\",\"herramientas\":[";
    for (HERRAMIENTAS, 0..) |h, i| {
        if (i > 0) s = s ++ ",";
        s = s ++ h.json;
    }
    break :blk s ++ "]}";
};

test "manifiesto y comandos derivados" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"nombre\":\"mcp-crypto\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"crypto_help\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"punto_mul\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"hexagono\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"cifrar\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, MANIFIESTO, "\"xchacha20poly1305\"") != null);
    try std.testing.expectEqual(@as(usize, 18), HERRAMIENTAS.len);
    try std.testing.expectEqual(HERRAMIENTAS.len, COMANDOS.len);
}
