# Omnia para Hyprland + illogical-impulse (diseño elegido: híbrido)

Estado: probado en copia aislada de ii con omnia-core real (rotación, selección, sin fondo, paleta); **nada instalado en la sesión real**. El diseño visual está en `prototypes/hyprland/`.

## Qué hace
- Un solo panel con tres estados (`OmniaPanelState`): cerrado · **asomado** (borde derecho, sin foco, se cierra al salir) · **fijado** (botón, atajo o clic dentro del panel; foco, Esc, clic fuera).
- Botón en la barra junto al de ASUS (`OmniaButton`) y zona del borde derecho (`OmniaEdge`). Atajo opcional `SUPER+SHIFT+O` (`quickshell:omniaToggle`).
- Tres acciones distintas: seleccionar (clic en la fila), jugar (▶), abrir BigMode (`libraryCommand`).
- **El fondo del escritorio no se toca**: es el que tengas en Hyprland / illogical-impulse. Las imágenes de los juegos solo se usan en BigMode. (`OmniaWallpaper` solo deshace versiones anteriores que sí lo cambiaban.)

## Archivos
| Ruta (bajo `ii/`) | Función |
|---|---|
| `services/OmniaSettings.qml` | Ajustes en `~/.config/omnia/hyprland.json` (no toca el config de ii) |
| `services/OmniaApi.qml` | Cliente de omnia-core: `/library`, `/selection` (espera larga), `/selection/set`, `/launch` |
| `services/OmniaPanelState.qml` | Máquina de estados, exclusión con otros paneles de ii, atajo global |
| `services/OmniaWallpaper.qml` | Solo restaura el fondo original si una versión anterior lo había cambiado |
| `modules/ii/omnia/OmniaPanelContent.qml` | Contenido: seleccionado, recientes, vacío, error |
| `modules/ii/omnia/OmniaEdge.qml` | Zona de activación + panel pegado al borde, por monitor |
| `modules/ii/bar/OmniaButton.qml` | Botón y `PopupWindow` (patrón de `AsusControlButton`) |

Ajustes (`hyprland.json`, todos opcionales): `edgeEnabled`, `edgeMonitors` (`rightmost`|`all`), `revealDelayMs` 300, `zoneHeightPct` 35, `zoneWidthPx` 2, `closeGraceMs` 600, `libraryCommand`.

## Instalación reversible
En Arch, la integración se distribuye como el paquete opcional `omnia-hyprland` (depende de `omnia-app`). También se
puede usar directamente desde el repositorio o desde el archivo instalado en `/usr/share/omnia/hyprland/`:

```
integrations/hyprland/omnia-hyprland install   --dry-run [--keybind ~/.config/hypr/custom/keybinds.lua]
integrations/hyprland/omnia-hyprland install   [--keybind …] [--rules …]   # artwork público servido por omnia-backend; sin clave de proveedor
integrations/hyprland/omnia-hyprland uninstall [--keybind …]
```
Parchea solo `UtilButtons.qml` (un `Loader`) y `IllogicalImpulseFamily.qml` (import + `PanelLoader`), con marcas `omnia-hyprland:begin/end` y copia `*.omnia.bak`. `uninstall` quita parches y archivos, restaura `wallpaperPath` desde `~/.local/state/omnia/wallpaper-backup.json`. Comprobado en una copia de ii: instalar, reinstalar y desinstalar deja el árbol idéntico.

## Pruebas
- `integrations/hyprland/test-shell.sh`: segunda instancia de Quickshell sobre una copia aislada (barra falsa + borde). Abre ventanas en la sesión actual; no toca la config real.

## Pendiente / por verificar en vivo
- Nada de lo QML se ha ejecutado dentro de Quickshell todavía (solo comprobación de sintaxis con `qmlformat`).
- `omnia-core` no está activo y no hay biblioteca en este equipo: faltan datos reales de arte.
- **Transparencia:** `Appearance.qml` calcula la transparencia automática del shell desde el fondo (`appearance.transparency.automatic = true` en tu config). Los colores no cambian, pero el alfa de barra y paneles variará con cada fondo. Para fijarla: `automatic = false` (no se ha tocado).
- `omnia-ui --window` no está instalado; `libraryCommand` apunta a él.
- Pausa por pantalla completa/batería: implementada, sin probar.

## Control y diagnóstico por IPC
`qs -c ii ipc call omnia toggle | open | close | status | bigmode | settings | libraryCommand` — abre/cierra el panel, muestra el estado
(modo, monitor, paneles de ii abiertos, API) y abre BigMode sin hacer clic. El atajo global es
`SUPER + SHIFT + O` (la letra O, no el cero: `SUPER + SHIFT + 0` ya mueve ventanas al espacio 10 en ii).
Los clics del panel usan solo `MouseArea` (los `TapHandler` no se comportaban de forma fiable en `PopupWindow`).


## Rediseño del panel (dos columnas) y ficha de BigMode — 2026-11-21
**No instalado en la sesión activa.** Probado en copia aislada (ver «Cómo probar sin instalar»).

- **Panel:** lista de juegos a la izquierda (scroll con rueda, touchpad, arrastre de la barra y teclado/mando); a la derecha el
  juego seleccionado con «Jugar» y «⋯», hasta 3 recientes por actividad local de Omnia (sin repetir) y «Abrir BigMode».
  Paleta fija Omnia oscuro (`OmniaTheme.qml`), independiente del wallpaper.
- **Superficie:** `PanelWindow` = capa Wayland `Top` (wlr-layer-shell), namespace `quickshell:omniaPanel`, una por monitor,
  visible solo en el monitor donde se activó. Desde la barra se despliega desde el botón con esquinas cóncavas en la unión;
  desde el borde entra y sale por ese borde.
- **Desenfoque:** regla de Hyprland por namespace
  `hl.layer_rule({ match = { namespace = "quickshell:omniaPanel" }, blur = true, ignore_alpha = 0.25 })`
  (Hyprland 0.57.2 con configuración Lua). La añade `omnia-hyprland install --rules ~/.config/hypr/custom/rules.lua`.
  Sin la regla (o con `blur: false`) el panel es casi opaco (alfa .97) y sigue legible.
- **Ajustes → Activación:** Barra superior / Borde de pantalla / Ambos; borde Izquierdo / Derecho / Superior / Inferior;
  posición Inicio / Centro / Fin; retraso; desenfoque. Se guardan en `~/.config/omnia/hyprland.json` y se aplican al instante.
- **Menú «⋯»** (junto al botón; foco en la primera opción; ↑↓/Enter/Esc; no inicia el juego): Ver detalles en Big Mode ·
  Añadir/Quitar de favoritos · Usar su fondo en el escritorio / Quitar fondo fijado · Abrir carpeta del juego (solo si Omnia
  conoce una ruta válida).
- **Fondo del escritorio:** Omnia **no** lo cambia por su cuenta (acuerdo posterior a la primera especificación: sin rotación
  ni cambios automáticos). Solo cambia o restaura el wallpaper con las dos opciones explícitas del menú; guarda el original en
  `~/.local/state/omnia/wallpaper-backup.json`. Seleccionar, hacer scroll, abrir el menú o animar no tocan el wallpaper.
- **BigMode → ficha del juego:** `omnia-ui --window --game ID --details [--tab 0|1|2]`. Banner con degradado, título,
  plataforma · origen, «Jugar» y «⋯»; pestañas Descripción (descripción, tiempo jugado, última sesión, partidas), Partidas
  (guardados y respaldos reales de `/saves`) y Actividad (sesiones de `/game/activity`), con estados vacíos. «Detalles»
  del carrusel abre la misma ficha; la biblioteca conserva selección y scroll al volver.
- **Núcleo:** `/library` añade `folder`; nueva ruta `GET /game/activity`. Al importar un port antiguo, Omnia copia
  `last_played` y `played_secs` una sola vez al historial local; el panel y Big Mode después leen solo datos de Omnia.

### Cómo probar sin instalar (reversible)
```
integrations/hyprland/test-core.sh 30 3 47900          # núcleo aislado: 30 juegos falsos, 3 jugados (puerto y token propios)
OMNIA_TEST_PORT=47900 OMNIA_TEST_TOKEN=<token impreso> integrations/hyprland/test-shell.sh --keep
qs -p <dir>/ii/omnia-test-shell.qml ipc call omnia open | bar 1760 | menu | settings | key down | setting edgeSide '"top"' | status
```
`test-shell.sh` copia ii y su config a un directorio temporal (el fondo se escribe solo en la copia) y abre una segunda
instancia de Quickshell con una barra falsa. Para el desenfoque en la prueba: `hyprctl eval 'hl.layer_rule(...)'`
(temporal; `hyprctl reload` lo quita).
Instalar de verdad: `omnia-hyprland install --keybind ~/.config/hypr/custom/keybinds.lua --rules ~/.config/hypr/custom/rules.lua`
(`--dry-run` primero). Revertir: `uninstall` con los mismos archivos.

### Verificado en la sesión real (copia aislada) y pendiente
Verificado: lista de 31 juegos con scroll y selección siempre visible (↓ 18, 58 y ↑ 30 veces); 0, 1, 2 y 3 recientes; los 12
combinaciones borde × posición (el panel y la zona caben en la pantalla y respetan la barra); apertura desde la barra con
esquinas cóncavas; menú con 3–4 opciones, foco inicial, navegación y Esc solo cierra el menú; fijar y quitar el fondo (se
restaura el original y se borra la copia); ficha de BigMode con las tres pestañas y estados vacíos; ventana activa antes y
después de abrir/cerrar; regla de desenfoque aplicada; instalador/desinstalador de regla y atajo.
Pendiente: clic con ratón y rueda/touchpad reales; teclado físico y mando en la ficha y en el panel (se probó la lógica con
una orden de diagnóstico, no con pulsaciones); varios monitores (solo hay uno); clic fuera con el grab de foco real; ver el
desenfoque en un fondo con mucho contraste; instalar en la sesión activa.

**Instalación real (2026-11-21):** módulo, atajo `SUPER+SHIFT+O` y regla de desenfoque instalados. Tras copiar, ii hay que
reiniciarlo (CTRL+SUPER+R o `qs kill -c ii; qs -c ii`): una recarga en caliente no registra los singletons nuevos
(`OmniaTheme`) y el panel salía blanco con texto negro hasta reiniciar.

### Pulido (2026-11-21, tarde)
Superficie con margen: la capa mide más que el panel (rebote y esquinas cóncavas) y `mask` limita la entrada del ratón al
cuerpo. Regla de desenfoque actual: `ignore_alpha = 0.88` (el instalador sustituye la anterior). Colores: `OmniaTheme.qml`
los toma de `Appearance` de ii (en esta instalación = Omnia oscuro, sin generación desde el wallpaper).
Verificado: panel desde el borde derecho y desde la barra en la sesión real (no cortado), esquinas cóncavas (prueba offscreen
de los 4 bordes), BigMode (ficha y ajustes). Sin probar: rebote a ojo (solo muestreo por capturas), clic/teclado reales.
