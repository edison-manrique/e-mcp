// Errores compartidos del dominio "tiempo". Un solo conjunto para que la capa
// de herramientas (MCP/CLI) traduzca cada codigo a un mensaje corto y accionable
// (ver `tmtool.msgDe`).

pub const Error = error{
    FechaInvalida,
    DuracionInvalida,
    Rango,
    ZonaDesconocida,
    FeriadoInvalido,
    PatronInvalido,
    FormatoInvalido,
};
