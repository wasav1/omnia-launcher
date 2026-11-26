# Omnia × Hyprland × illogical-impulse — diseño previo

Prototipos visuales: abre `index.html` en un navegador. No se instala nada ni se toca `~/.config`.
Estado: **esperando elección**. Nada de esto está activo en la sesión.

## Diagnóstico (revisado el 2026-11-21)

### Reutilizable tal cual
| Pieza | Por qué sirve |
|---|---|
| `core/omnia/` (API HTTP en `127.0.0.1:47831`, `/library`, `/selection`, `/launch`, `/events`) | Solo biblioteca estándar y XDG; no depende de KDE. `omnia.service` es una unidad de usuario normal. |
| `GET /selection?since=N&wait=25` | Espera larga que avisa de cambios de selección y de arte: es lo que necesita el fondo, sin sondeo. Devuelve `fondo` como `file://…`. |
| Arte en `~/.local/share/omnia/art` (`art.py`, SteamGridDB) | Ya hay una ruta local por juego. Lo que no existe en disco no se descarga desde el panel. |
| `ui/qml/` (`Backdrop`, `GameCard`, `Api.qml`, `LucideIcon`…) | QML puro de Qt; no importa `org.kde.*` salvo el contenedor. Aprovechable dentro de un `PopupWindow` de Quickshell. |
| Lanzamiento (`launcher.py`, `systemd-run --user --scope`) | Independiente del escritorio. |

### Necesita adaptación
| Pieza | Problema |
|---|---|
| `plasma/wallpapers/org.omnia.launcher`, `plasma/applets/*` | API de Plasma (`WallpaperItem`, `PlasmoidItem`). No existe en Hyprland. Se reemplaza por un módulo Quickshell. |
| `kwin/omnia-watch`, `omnia-showdesktop` y `SetDesktop(active, covered)` por D-Bus | Dependen de KWin. En Hyprland la señal «pantalla completa / cubierto» sale de `Hyprland.workspaces` (como ya hace `Background.qml`) o de `hyprctl -j`. |
| `omnia-setup` / instalador (rutas KDE, KGlobalAccel, reinicio de Plasma) | No aplica. Hace falta un instalador de módulo ii **reversible** (ver abajo). |
| Token | El token vive en `$XDG_RUNTIME_DIR/omnia/token`; hoy lo lee un plugin C++ de Plasma (`tokenprovider`). Quickshell puede leerlo con `FileView`. `/selection` no necesita escritura. |
| `omnia-core` está **inactivo** ahora y no hay `~/.local/share/omnia` ni `~/.config/omnia` en este equipo | Habrá que arrancarlo y comprobar el arte antes de probar rotación con datos reales. |

### Sistema de wallpapers de illogical-impulse
- ii **dibuja él mismo** el fondo: `modules/ii/background/Background.qml` crea una `PanelWindow` en `WlrLayer.Bottom` por monitor con un `StyledImage` cuyo origen es `Config.options.background.wallpaperPath`. No hay `swww`/`hyprpaper`/`awww` instalados ni en marcha.
- `Wallpapers.apply()` llama a `scripts/colors/switchwall.sh --image …`. **Ese script regenera colores**: aunque `wallpaperTheming.enableAppsAndShell` esté en `false`, `enableTerminal` y `enableQtApps` están en `true`, así que cambiaría terminal y aplicaciones Qt con cada fondo. Eso rompe tu requisito de conservar la paleta. **No hay que usarlo para rotar.**
- Mecanismo propuesto: escribir `Config.options.background.wallpaperPath` directamente desde un componente QML de Omnia (sin pasar por `switchwall.sh`). La paleta de la barra la carga `MaterialThemeLoader` desde `colors.json`, que solo cambia cuando corre `switchwall.sh`/`applycolor.sh`. Por verificar en la prueba: que ningún observador de ii regenere colores al cambiar esa propiedad.
- Un solo gestor: ii sigue siendo el único que dibuja. Omnia no lanza `swww`, `mpvpaper` ni capas propias. Al desactivar Omnia se restaura el valor guardado en `~/.local/state/omnia/wallpaper-backup.json` (`wallpaperPath` y `thumbnailPath` originales).
- Vídeo/animación: ii ya soporta vídeo con `mpvpaper` (no instalado), pero lo hace con otro gestor y con una miniatura para los colores. **Se deja fuera de la v1.**
- Ahorro: pausar la rotación con ventana a pantalla completa (`hideWhenFullscreen` ya oculta el fondo), con la batería (`UPower.onBattery`: intervalo ×3 o rotación en pausa) y con el modo juego de Omnia activo. Fondo estático, sin vídeo.

## Recomendación para la v1
Prototipo **1 (botón en la barra)** + atajo global opcional + fondo dinámico por `wallpaperPath`.
Motivos: es idéntico al panel ASUS que ya funciona (ancla, foco, cierre), el menos invasivo y el que menos compite con la sidebar derecha de ii. El borde derecho (2) queda como interruptor para una v2 con el mismo componente de panel; el híbrido (3) solo si usas el borde a diario.

## Archivos a crear o modificar (cuando elijas)
Crear en `~/.config/quickshell/ii/` (todo con prefijo `Omnia` para poder quitarlo):
- `services/OmniaApi.qml` — cliente de `/library`, `/selection`, `/launch`, token con `FileView`.
- `services/OmniaWallpaper.qml` — máquina de estados (rotación, selección, respaldo, pausa), escribe `wallpaperPath`, guarda y restaura el original.
- `modules/ii/bar/OmniaButton.qml` — botón + `PopupWindow` (modelo: `AsusControlButton.qml`).
- `modules/ii/bar/OmniaPanel.qml` — contenido (seleccionado, recientes, estados vacío/error).
- Opcional v2: `modules/ii/omniaEdge/OmniaEdge.qml` — zona del borde.

Modificar (una línea cada una, con copia `.bak` como ya haces):
- `modules/ii/bar/UtilButtons.qml` — `Loader` para `OmniaButton` junto a `AsusControlButton`.
- `~/.config/hypr/custom/keybinds.lua` — `hl.bind("SUPER + O", hl.dsp.global("quickshell:omniaToggle"))` (comprobar que `SUPER+SHIFT+O` está libre).
- `defaults/config.json` / `modules/common/Config.qml` — opciones `omnia.*` (`rotateMinutes`, `fallbackWallpaper`, `pauseOnBattery`, `edge.*`). Sin escribirlas en tu `config.json` activo hasta aprobar.

En el repositorio de Omnia:
- `integrations/hyprland/` — los QML anteriores, `install.sh` / `uninstall.sh` reversibles y pruebas.
- `core/omnia/api.py` — opcional: `GET /wallpapers` (lista de fondos locales), para no recorrer el disco desde QML.
- `docs/CONTEXTO.md` y `docs/HYPRLAND.md`.

## Estrategia reversible
1. **Panel aislado:** `qs -p <repo>/integrations/hyprland/test-shell.qml` abre una segunda instancia con una barra falsa; no toca la shell activa (`qs -c ii`).
2. **Fondo en seco:** modo `--dry-run` que solo registra qué fondo elegiría, sin escribir.
3. **Prueba real:** `install.sh` copia los archivos nuevos, aplica los parches de una línea con respaldo `*.omnia.bak` y registra todo en un manifiesto. `uninstall.sh` revierte parches, borra los `Omnia*.qml` y restaura `wallpaperPath`.
4. **Sin sustituir ii:** ii se recarga con `qs -c ii` (recarga en caliente); si algo falla, `uninstall.sh` y recarga.
5. Un solo propietario del fondo: si Omnia está desactivado, `OmniaWallpaper` no hace nada.

## Criterios de verificación
| Área | Criterio |
|---|---|
| Anclaje | El panel queda bajo el botón de Omnia, no se sale del monitor (`SlideX/SlideY`), mismo borde y radio que el panel ASUS, con barra arriba y abajo (`bar.bottom`). |
| Foco | Esc cierra con el panel enfocado; clic fuera cierra; segundo clic en el icono cierra y no reabre; abrir ASUS cierra Omnia y viceversa; el teclado vuelve a la ventana anterior. |
| Cierre tras acción | Jugar y abrir biblioteca cierran el panel; seleccionar no. |
| Monitores | Un solo panel abierto a la vez; en 2 monitores aparece en el del botón pulsado; el borde interno no revela (v2). |
| Rotación | Con N≥2 fondos nunca repite el anterior; respeta el intervalo; se pausa con pantalla completa y batería; sin fondos locales, usa el respaldo. |
| Selección | Seleccionar detiene la rotación y fija solo ese fondo; cambiar carga el nuevo; quitar reanuda. |
| Sin fondo | Con selección sin fondo no aparece nunca el fondo de otro juego. |
| Paleta | Antes y después de 20 cambios: `colors.json`, `material_colors.scss`, `config.json › appearance` y los colores de terminal/Qt idénticos (`sha256sum`). |
| Un solo gestor | `pgrep` no muestra `swww`, `mpvpaper` ni `hyprpaper`; solo `quickshell:background` en `hyprctl layers`. |
| Reversión | Tras `uninstall.sh`: `diff` de `UtilButtons.qml` y `keybinds.lua` contra su `.bak`, `wallpaperPath` original restaurado. |
