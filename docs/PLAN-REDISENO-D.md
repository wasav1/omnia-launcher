# Plan — rediseño «D · Aurora + Estudio»

Creado: 2026-11-28. Estado: **aprobado el diseño, pendiente de implementar**. Ninguna fase ha empezado.

Prototipos navegables (lienzo de diseño, privado del dueño del proyecto):
<https://claude.ai/artifact/YNhRvAo7xdX8NK55TC4XqC> — fila **D** (Desktop y panel rápido) y fila **D · Big Mode**.

## 1. Qué se decidió en el diseño

- **Un solo lenguaje visual** para Desktop, Big Mode y el panel de Dux: superficies de **cristal** (translúcidas con desenfoque, borde claro y brillo en el canto superior) sobre un fondo que toma los colores del juego o de la novedad seleccionada. Acento azul Omnia `#4DA3FF`.
- **Desktop con navegación arriba**: logo, «Omnia», Inicio, Biblioteca, Descargas, Estadísticas y Ajustes; paleta de comandos **Ctrl K**.
- **Tamaños fijos**: los componentes no se escalan con la ventana; solo se reorganizan cuando falta espacio.
- **Biblioteca + Catálogo en tres paneles** (Desktop): Instalados (lista), Catálogo (antes «Explorar») y ficha.
  - Buscadores **independientes** en Instalados y en Catálogo.
  - **Ver todos**: cuadrícula de los instalados agrupada por Origen, Consola o Estado.
  - La **ficha está oculta** hasta elegir un juego; con ella oculta el Catálogo se ensancha (6 columnas a 1440 px; 4 con la ficha abierta).
- **Inicio = novedades de las tiendas**: ofertas, gratis por tiempo limitado, lanzamientos y actualizaciones de tus juegos, con filtro por tienda (Steam, Epic, GOG, Amazon, Ubisoft, EA, Omnia).
- **Ajustes** como menú propio, con categorías (General, Biblioteca y carpetas, Tiendas y cuentas, Juegos y rendimiento, Novedades, Apariencia, Big Mode, Panel rápido de Dux, Acerca de).
- **Big Mode**: misma barra de cristal; Inicio con novedades; Catálogo; Descargas; ficha con pestañas (Resumen, Partidas, Actividad); **Menú rápido** con el botón Guía (perfil de energía, límite de FPS, HUD, volumen, brillo, suspender, apagar). **La estantería de Biblioteca se conserva tal cual.**
- **Panel rápido de Dux**: juego seleccionado arriba, pestañas Recientes / Favoritos / Novedades, descarga activa, Big Mode y Abrir Omnia.

## 2. Punto de partida en el código (revisado el 2026-11-28)

- No hay tema central: los colores están en cada archivo (59 hex solo en `OmniaManager`, `ManagerLibrary` y `OmniaLibrary`).
- Desktop escala todo con `manager.cs * …` (proporcional), lo contrario a «tamaños fijos».
- `FrostedSurface.qml` ya hace cristal real (muestra y desenfoca el fondo): base del componente nuevo.
- `core/omnia/store_news.py` solo trae noticias/blogs de Steam, GOG, Epic y Amazon Studios; no hay ofertas, gratis, Ubisoft ni EA.
- Big Mode: LB/RB filtran la estantería y LT/RT cambian de página (`OmniaLibrary.qml`, ~líneas 594–597).
- Tamaños actuales: `OmniaShell` 1687 líneas, `OmniaLibrary` 1132, `OmniaManager` 702, `OmniaBigStore` 685, `ManagerLibrary` 471, `OmniaPanel` (Dux) 459.

## 3. Fases

Cada fase: rama propia, pruebas (`PYTHONPATH=core python3 -m unittest discover -s tests` + `qmllint` en los QML tocados), `CONTEXTO.md` y `HANDOFF.md` al día, `.run` con revisión superior y tabla de pruebas (superficie · flujo · resultado). El dueño aprueba cada fase antes de la siguiente.

| Fase | Contenido | Archivos principales | Tamaño |
|---|---|---|---|
| **0 · Base** | `Theme.qml` (singleton): colores, radios, espaciados y **tamaños fijos** (paneles 300 / 688 / 380 px, carátulas 152 × 203 px, puntos de reorganización 1360 y 900 px). `GlassPanel.qml` sobre `FrostedSurface`, con opción para desactivar el cristal. Sin cambios visibles. | nuevos `ui/qml/Theme.qml`, `ui/qml/GlassPanel.qml` | Pequeña |
| **1 · Barra superior de Desktop** | Quitar la barra lateral; barra de cristal arriba; Ctrl K; eliminar el escalado `cs`; reorganización por anchos fijos. | `OmniaManager.qml` | Media |
| **2 · Biblioteca + Catálogo** | Vista de tres paneles con buscadores independientes, Ver todos agrupado, ficha oculta hasta elegir y flotante bajo 1360 px. «Explorar» sale del menú. Partir en 2–3 entregas. | `ManagerLibrary` + `ManagerExplore` → `ManagerLibraryView` (+ `InstalledPanel`, `CatalogPanel`, `DetailPanel`); reutilizar `OmniaAllGames` | Grande |
| **3 · Ajustes** | Pantalla con categorías; al principio solo los ajustes que ya existen. | `ManagerSettings.qml` | Media |
| **4 · Novedades por tienda** | Tipos oferta / gratis / lanzamiento / actualización; filtros por tienda; Ajustes → Novedades; Inicio de Desktop nuevo. | `store_news.py`, `api.py`, `ManagerHome`, `ManagerStoreNews`; probablemente `omnia-backend` | Grande |
| **5 · Big Mode** | Barra de cristal con Catálogo y Descargas; Inicio con novedades; Catálogo (refactor de `OmniaBigStore`); ficha con pestañas; Menú rápido (Guía). Estantería sin cambios. Partir en 2–3 entregas. | `OmniaLibrary`, `OmniaBigHeader`, `OmniaHome`, `OmniaBigStore`, `OmniaGameDetails` | Grande |
| **6 · Panel rápido de Dux** | Rediseño con pestañas Recientes / Favoritos / Novedades y descarga activa. | `integrations/dux/omnia-panel/OmniaPanel.qml` | Pequeña |
| **7 · Integración con el sistema** (opcional) | Perfil de energía vía `powerprofilesctl` (sin sudo); límite de FPS y HUD en la config de MangoHud; número de producto de Ubisoft al importar desde Lutris. El tope de CPU sigue en los scripts del usuario; Omnia solo muestra su estado. | `core/omnia` (perfiles, `mangohud.py`, detector de Lutris) | Media |

Orden recomendado: **0 → 1 → 2**, luego **3 → 5 → 6 → 4 → 7** (la 4 depende de fuentes externas).

## 4. Decisiones

**Tomadas**

1. **Botones del mando en la Biblioteca de Big Mode** (2026-11-28): se mantiene lo actual. LB/RB = filtro, LT/RT = página de la estantería; las secciones (Inicio, Biblioteca, Catálogo, Descargas) se cambian con el botón **Vista**. Los prototipos que muestran LB/RB en el menú y LT/RT en el filtro quedan superados en este punto.

**Pendientes del dueño**

2. **Fuente de ofertas y gratis.** Recomendado: agregarlas en `omnia-backend` (Cloudflare) con caché, empezando por Steam, Epic, GOG y Omnia; Prime Gaming, Ubisoft y EA quedan pendientes hasta tener una fuente fiable. El núcleo sigue sin dependencias externas.
3. **Coste del cristal.** Propuesta: Ajustes → Apariencia permite desactivarlo, y se apaga solo mientras haya un juego abierto.

## 5. Riesgos

- Orden del foco con mando en los tres paneles de Desktop (Instalados → Catálogo → Ficha).
- Las fuentes de ofertas pueden cambiar sin aviso (de ahí la caché en el backend).
- Los precios y juegos gratis se muestran solo con datos reales; los prototipos usan marcadores (`[PRECIO]`, `−[XX] %`).
- Fases 2 y 5 grandes: entregarlas en partes para poder validar cada una.
