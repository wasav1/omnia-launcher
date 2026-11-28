.pragma library
// Tema central de Omnia (rediseño D · Aurora + Estudio, docs/PLAN-REDISENO-D.md).
//
// Uso en QML:   import "Theme.js" as Theme
//               color: Theme.color.ink;  width: Theme.size.panelDetail
//
// Reglas:
// - Las superficies nuevas toman color, radio, espaciado y tamaño de aquí.
// - Los tamaños son FIJOS en píxeles lógicos: la interfaz no se escala con la
//   ventana; cuando falta ancho se reorganiza según `breakpoint`.
// - Los colores con transparencia usan #AARRGGBB, el formato de QML.

var color = {
    // Fondo y texto
    background: "#070B12",
    backgroundAlt: "#0A0F17",
    ink: "#EEF4FB",          // texto principal
    inkStrong: "#FFFFFF",
    muted: "#A9BDD3",        // texto secundario (contraste ≥ 4.5:1 sobre background)
    soft: "#C9D6E4",         // texto terciario sobre cristal

    // Acento de Omnia
    accent: "#4DA3FF",
    accentInk: "#06121F",    // texto sobre el acento
    accentLight: "#9CD0FF",
    accentSoft: "#384DA3FF", // relleno de selección (22 %)
    accentRing: "#404DA3FF", // halo de foco (25 %)

    // Cristal
    glassFill: "#12FFFFFF",       // 7 %
    glassFillStrong: "#14FFFFFF", // 8 %, paneles principales
    glassFillSoft: "#0DFFFFFF",   // 5 %, paneles secundarios
    glassBorder: "#24FFFFFF",     // 14 %
    glassBorderStrong: "#29FFFFFF", // 16 %
    glassHighlight: "#1AFFFFFF",  // brillo del canto superior (10 %)
    glassTint: "#B30E1622",       // tinte sobre el fondo desenfocado (70 %)
    glassFallback: "#E60E1622",   // cristal desactivado: panel casi opaco
    inset: "#40000000",           // campos de texto y bloques hundidos (25 %)

    // Estados
    ok: "#7EE0A1",
    warning: "#E9C46A",
    danger: "#E55B5B",
    favorite: "#FFD34D",

    // Tiendas (punto de color junto al nombre)
    store: {
        steam: "#66C0F4",
        epic: "#E6E6E6",
        gog: "#B565F2",
        amazon: "#FF9900",
        ubisoft: "#2C8CFF",
        ea: "#FF4747",
        omnia: "#4DA3FF"
    }
};

var radius = {
    sm: 10,
    md: 14,
    lg: 18,
    xl: 22,
    xxl: 26,
    pill: 999
};

var space = {
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
    xxl: 28
};

var font = {
    family: "Hanken Grotesk",
    display: "Hanken Grotesk",
    numeric: "Rajdhani",
    size: { caption: 11, small: 12, body: 14, bodyLarge: 15, title: 17, heading: 24, display: 34, hero: 42 }
};

// Tamaños fijos de Desktop (px lógicos). No se multiplican por ningún factor.
var size = {
    topBarHeight: 60,
    topBarMarginTop: 16,
    pageMargin: 20,
    panelGap: 16,

    panelInstalled: 300,
    panelCatalog: 688,     // con la ficha abierta (4 columnas de carátulas)
    panelDetail: 380,

    posterWidth: 152,
    posterHeight: 203,
    posterGap: 14,
    posterMaxWidth: 240,   // las carátulas crecen hasta aquí para llenar el ancho…
    posterMaxColumns: 6,   // …sin pasar de 6 columnas; si sobra espacio, la cuadrícula se centra

    listRow: 56,
    listThumb: 40,

    control: 38,           // botones y campos de la barra superior
    controlLarge: 46,      // acción principal de la ficha
    chip: 28,

    detailArtHeight: 190,
    minWindowWidth: 800,
    minWindowHeight: 560
};

// Por debajo de estos anchos de ventana la interfaz se reorganiza.
var breakpoint = {
    threePanels: 1360,     // menos: la ficha pasa a panel flotante
    commandField: 1280,    // menos: el campo Ctrl K de la barra superior se vuelve un botón
    navIcons: 1040,        // menos: los menús de la barra superior muestran solo el ícono
    compact: 900           // menos: Instalados se esconde tras un botón
};

// Columnas de carátulas que caben en un ancho dado, sin estirarlas.
function posterColumns(width) {
    var w = size.posterWidth + size.posterGap;
    return Math.max(1, Math.floor((width + size.posterGap) / w));
}

// Distribución de la cuadrícula del Catálogo: tantas columnas como quepan con la carátula
// mínima (máx. 6) y carátulas estiradas para llenar el ancho, hasta posterMaxWidth.
// La proporción se conserva (152 × 203).
function posterLayout(width) {
    var columns = Math.min(size.posterMaxColumns, posterColumns(width));
    var w = Math.floor((width - (columns - 1) * size.posterGap) / columns);
    w = Math.max(size.posterWidth, Math.min(size.posterMaxWidth, w));
    return { columns: columns, width: w, height: Math.round(w * size.posterHeight / size.posterWidth) };
}

// Ancho del Catálogo según la ventana y si la ficha está abierta.
function catalogWidth(windowWidth, detailOpen) {
    var used = 2 * size.pageMargin + size.panelInstalled + size.panelGap;
    var free = windowWidth - used;
    if (detailOpen && windowWidth >= breakpoint.threePanels)
        return Math.min(free - size.panelGap - size.panelDetail, free);
    return free;
}
