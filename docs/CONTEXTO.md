# Omnia — documento de contexto

> Documento vivo. Se actualiza con **cada cambio** (ver «Registro de cambios» al final). Es el punto de entrada para
> retomar el proyecto sin haber visto las conversaciones anteriores. Detalles por tema: ver `docs/`.

## 1. Qué es
Omnia es un lanzador de juegos para **CachyOS + KDE Plasma 6.8** (rehacer y mejorar el prototipo «Estantería», que vivía en
Bazzite). Biblioteca unificada (Steam, Heroic, Lutris, juegos manuales: ports y emuladores), el **escritorio como lanzador**
(ventana layer-shell de fondo), un **Big Menu** de aplicaciones, control con **mando**, **modo juego**, **historial**,
**respaldo/restauración de partidas**, e instalación por paquetes Arch con configuración de KDE **automática y reversible**.

Repo: https://github.com/wasav1/omnia-launcher (privado por ahora). Se planea publicarlo para el AUR.
Principios: todo automático al instalar (no pasos manuales), cambios en KDE siempre reversibles, nada de piratería
(no hay ROMs ni detección de carpetas de Hydra), el disco de Bazzite se monta solo lectura y no se modifica.

## 2. Estructura del repo
| Ruta | Contenido |
|---|---|
| `core/omnia/` | Servicio `omnia-core` (Python, solo biblioteca estándar) |
| `ui/qml/` | Interfaz QML (`qml6 main.qml`), dos ventanas layer-shell (estantería + Big Menu) |
| `kwin/` | Scripts de KWin: `omnia-showdesktop`, `omnia-watch` |
| `packaging/arch/` | PKGBUILD (pkgbase `omnia-launcher`: `omnia-core`, `omnia-ui`, `omnia-kde`), `build-local.sh`, `out/` (ignorado) |
| `tests/` | Pruebas `unittest` (228). Ejecutar: `PYTHONPATH=core python -m unittest discover -s tests` |
| `docs/` | `MIGRACION`, `SPIKE-LAYER-SHELL`, `MODO-JUEGO`, `HISTORIAL`, `PARTIDAS`, y este documento |
| `legacy/`, `plasmoid/`, `tools/`, `install-arch.sh` | Material del prototipo y utilidades |

**Importante:** sin `PYTHONPATH=core` los tests importan el paquete instalado en el sistema (más antiguo).

## 3. Arquitectura
- **Servicio** `omnia.service` (systemd de usuario): API HTTP en `127.0.0.1:47831`. Token de sesión en
  `$XDG_RUNTIME_DIR/omnia/token` (0600), cabecera `Authorization: Bearer`, comprobación de `Host`, rutas que modifican solo
  por POST, sin CORS.
- **UI** `omnia-ui.service`: `qml6 main.qml -- --token …` con `QT_WAYLAND_SHELL_INTEGRATION=layer-shell` y
  `QML_XHR_ALLOW_FILE_READ=1`. Autostart de primera vez: `omnia-first-run.desktop`.
- **D-Bus** `org.omnia.Core` (Gio/PyGObject): los scripts de KWin informan `SetDesktop(active, covered)` y llaman `ToggleMenu`.
- **Rutas API** (resumen): `/health /library /library/refresh /game/{fav,hide,add,remove} /launch /apps /app/{launch,fav}
  /events /pad /emit /desktop /menu /menu/state /gamemode /fs/list /templates /saves /saves/{config,backup,restore,open,suggest}
  /import/{find,preview,apply}`.
- **Módulos del core:** `paths, store (state.json/library.json), security, launcher (systemd-run --user --scope), api, events,
  pad (evdev sin dependencias), dbus, service, setup (omnia-setup), firstrun, apps, art (SteamGridDB), gamemode, sessions,
  saves, fsbrowse, templates, manual, importer, games/{base,vdf,steam,heroic,lutris,refresh,registry}`.
- **Datos del usuario** (fuera del repo): `~/.config/omnia/{library.json,state.json,first-run.json,setup-backup.json,
  steamgriddb.key}`, `~/.local/share/omnia/art`.

## 4. Decisiones y hallazgos clave
- **Referencia visual (15/11):** material en `~/Juegos/PROTOTIPO OMNIA/` (9 capturas, PDF de 33 páginas y respaldos).
  Inventario, diferencias y etapas en `docs/REFERENCIA-PROTOTIPO.md`. Recuperar primero la UI de Omnia y después desarrollar
  el tema/layout instalable de Plasma en el mismo repo; panel/dock nativos, Anillos excluido. Los respaldos del 14/11
  contienen código más antiguo que el conservado en el repo; contrastar antes de portar.
- **Layer-shell:** la superficie de fondo queda sobre el escritorio de Plasma y bajo las ventanas. El «Mostrar escritorio»
  nativo oculta toda superficie layer externa → script KWin `omnia-showdesktop` (atajo `OmniaShowDesktop`, minimiza y
  restaura); Meta+D se reasigna vía KGlobalAccel (`setForeignShortcut`, firma busctl `asai`).
- **Tecla Windows:** en Plasma 6.8 es una acción global de plasmashell («activate application launcher»), no
  `ModifierOnlyShortcuts`. `omnia-setup` le quita Meta y se lo da a la acción `OmniaMenu` de `omnia-watch`. KDE rechaza
  teclas duplicadas: al deshacer, primero se libera la de Omnia.
- **Mando:** la estantería lo controla solo si tiene el foco o no hay ventanas normales visibles; el Big Menu abierto lo
  posee (caduca si no hay sondeo `/events` en 30 s); con un juego en marcha el mando se silencia. Mapeo Xbox BT medido
  (0x133=X, 0x134=Y; ABS_Z/RZ = stick derecho).
- **Modo juego:** SIGSTOP a clientes de descarga + `HoldProfile` de power-profiles-daemon (mantener `self.conn`);
  recuperación en `~/.cache/omnia/gamemode.json`.
- **Historial:** `Sessions` (inicia con 2 sondeos, termina con 3 ausentes, ignora <10 s, persiste cada 30 s).
- **Partidas:** specs `glob`/`files`/`dirs`; respaldos `.tar.gz` con manifiesto `omnia-backup.json`; restauración segura
  (valida todo antes de escribir, solo dentro de las carpetas del juego, sin enlaces ni `..`, respaldo previo). Explorador
  `fsbrowse` limitado al home y discos externos. Configuración por juego en `state.json › saves`.
- **Plantillas:** Gopher64 (por SHA-256 de la ROM, incluidos órdenes v64/n64), Longshot, Hookshot, NX2navi, TOTK Recomp;
  Savage Wind sin ubicación conocida (no se afirma nada).
- **Gopher64 nativo** (`paru -S gopher64`, v1.2.1): datos en `~/.local/share/gopher64/{saves,states}`, config en
  `~/.config/gopher64/config.json`; opciones `-f/--fullscreen`. Las partidas se llaman `<ROM>-<SHA256>.eep|.mpk`.
- **Importador** de la biblioteca anterior: vista previa → aplicar; reglas de omisión (auto/Steam/Heroic/Hydra, GeForce NOW,
  ports sin lanzador o archivo ausente); adapta los comandos de Gopher64 Flatpak al nativo.
- **Lecciones QML:** usar `shell.backend` (no `api: api`); `!!()` para undefined→bool; `ListView` reinicia `currentIndex` al
  cambiar el modelo; no destruir un `Loader` dentro de un callback XHR (cerrar con `Qt.callLater`).

## 5. Estado actual
**Hecho y probado:** arquitectura, Win+D, tecla Windows, mando, modo juego, historial, partidas (respaldo/restauración),
juegos manuales, plantillas, importador, rescate de partidas de Bazzite (Gopher64: 4 archivos, Longshot: 14 → ya colocadas).

**Adaptación visual en curso (código de desarrollo; sin empaquetar ni aplicar al escritorio):** `OmniaShell.qml` y
`GameCard.qml` se reescribieron sobre el lienzo 1920×1080, tomando proporciones, tonos, jerarquía tipográfica, insignias
y escalas de tarjetas del prototipo. Se copiaron al UI los componentes auxiliares preservados del plasmoide original
(escena, broche, iconos de plataforma y mando, ondas, MPRIS y sensores). El core entrega campos seguros de presentación,
historial y ports sin exponer comandos de lanzamiento. La ventana normal se revisó a 1280×720; escala el carrusel y las
tarjetas según referencia, usa los iconos de plataforma y ordena filtros Switch 2, PC, Switch, N64. Se corrigieron el
solapamiento del reloj y el texto largo de GPU. Las operaciones de partidas ahora usan el port seleccionado, aunque el
panel central aún queda en «Consultando partidas…» pese a que el endpoint responde 200 desde la API; queda por corregir.

La fidelidad visual exacta y la paridad funcional siguen pendientes de revisión renderizada a 1920×1080. Falta completar selector y
ciclo de arte SteamGridDB, energía, cambio de salida de audio, métricas reales de almacenamiento/batería y curva de
temperatura, además de ajustar Big Menu y navegación contra las páginas del PDF. No mostrar métricas de ejemplo como reales.

**Prototipo visual:** `docs/prototipo-visual.html` muestra una propuesta navegable del escritorio Omnia a 16:9, con shelf,
panel superior/dock Plasma, filtros, ficha y ports, ranuras, tarjetas, panel MPRIS/sistema, Big Menu y energía. Sus datos son
ilustrativos; métricas no integradas se señalan con «—». Es una maqueta de diseño, no un tema instalable ni UI conectada.

**Pendiente:**
- Resolver por qué la consulta QML de partidas queda pendiente aunque el endpoint responda correctamente.
- Revisar la captura a 1920×1080 contra el PNG de referencia.
- Implementar y revisar menú contextual, selector de arte, energía, audio, métricas, paridad Big Menu/mando y navegación
  del PDF; luego desarrollar el tema/layout instalable opcional de Plasma.
- Instalar los últimos paquetes y aplicar el importador en la sesión real (solo probado contra un core temporal).
- Abrir Longshot (¿carga las 6 ranuras?) y un juego N64; comprobar que Gopher64 use la **NVIDIA GTX 1650 Ti** (Vulkan lista
  primero la Intel UHD); si no, lanzar con `prime-run`.
- Heroic y Lutris con juegos reales; prueba de cerrar/abrir sesión (autostart).
- Antes de publicar: licencia (propuesta GPL-3.0-or-later), comprobar disponibilidad del nombre «Omnia Launcher», quitar el
  usuario `wsaenz` del código/metadatos (ids D-Bus `org.wsaenz.*` → `org.omnia.*`, rutas heredadas), repo público para el AUR.

## 6. Operación
- Compilar paquetes: `packaging/arch/build-local.sh` (deja los `.pkg.tar.zst` en `/tmp/omnia-pkg/`; copiarlos a `out/`).
- Instalar: `sudo pacman -U packaging/arch/out/omnia-*.pkg.tar.zst` y
  `systemctl --user restart omnia.service omnia-ui.service`.
- Configuración de KDE: `omnia-setup --status | --dry-run | --yes | --undo` (copia en `~/.config/omnia/setup-backup.json`).
- Pruebas manuales: usar `XDG_*` temporales, `OMNIA_DBUS_NAME` único y otro puerto; teclas del mando con `POST /emit?k=…`;
  capturas con `spectacle -b -n -a`. No usar `pkill -f`.
- El usuario ejecuta los `sudo`; nunca imprimir la clave de SteamGridDB; confirmar antes de commit/push.

## 7. Registro de cambios
Más reciente primero. Cada cambio añade una línea aquí (y actualiza las secciones 4–5 si procede).

- 2026-11-15 — Reemplazada la composición aproximada por un port basado en el lienzo y los componentes QML del prototipo;
  añadidos metadatos seguros de presentación/ports en `/library`, navegación de ports en partidas y dependencia `qt6-5compat`
  para tintar iconos. Revisada ventana 1280×720; pendiente corregir la consulta QML de partidas y validar a 1920×1080.
  Sin instalación, commit ni push.

- 2026-11-15 — Creada maqueta visual interactiva `docs/prototipo-visual.html` con vistas de estantería, Big Menu y energía;
  documentadas en la sección 5 sus limitaciones y que el panel/dock representan componentes nativos de Plasma. Sin cambios
  en el launcher, servicios ni escritorio instalado.

- 2026-11-15 — Primer corte de adaptación visual en `OmniaShell.qml` y `GameCard.qml`: composición con ficha, reloj,
  ranuras reales, estado, filtros, búsqueda y tarjetas seleccionadas ampliadas. Se conserva el control de mando actual; no
  se añaden todavía MPRIS, telemetría, selector de arte ni acciones de energía. Vista previa abierta con biblioteca real;
  `qmllint` y `git diff --check` limpios. Se ajustaron las etiquetas sw1/sw2 y la fecha al español. Paquetes instalados y
  escritorio siguen sin cambios. La escala de la tarjeta seleccionada se adapta a ventanas de menor altura.

- 2026-11-15 — Revisadas las capturas y documentación de `PROTOTIPO OMNIA`; inventario con hashes y plan de adaptación en
  `REFERENCIA-PROTOTIPO.md`. Detectada divergencia entre respaldos antiguos y código del repo; registrada la futura separación
  launcher/tema/layout. Revisión documental, sin cambios en servicios o configuración del escritorio.

- 2026-11-15 — Se crea este documento. Importador adapta Gopher64 Flatpak → nativo (commit `fff2f54`); partidas N64 restauradas
  en `~/.local/share/gopher64/saves`; paquetes reconstruidos.
