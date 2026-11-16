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
| `tests/` | Pruebas `unittest` (256). Ejecutar: `PYTHONPATH=core python -m unittest discover -s tests` |
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
  /art/{browse,pick,cycle} /audio /system /power /import/{find,preview,apply}`.
- **Módulos del core:** `paths, store (state.json/library.json), security, launcher (systemd-run --user --scope), api, events,
  pad (evdev sin dependencias), audio (parec → 32 bandas mel con Goertzel, sin guardar audio), system (CPU, disco de juegos, batería), power (bloquear/suspender/cerrar sesión/reiniciar/apagar), dbus, service, setup (omnia-setup), firstrun, apps, art (SteamGridDB), gamemode, sessions,
  saves, fsbrowse, templates, manual, importer, games/{base,vdf,steam,heroic,lutris,gfn,refresh,registry}`.
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
historial y ports sin exponer comandos de lanzamiento. La ventana se revisó a 1920×1080; el carrusel, las tarjetas y las
coordenadas del lienzo coinciden con la referencia. Usa los iconos de plataforma y ordena filtros Switch 2, PC, Switch,
N64. Se corrigieron el solapamiento del reloj y el texto largo de GPU. Las operaciones de partidas usan el port
seleccionado; la petición se difiere hasta que `ListView` estabiliza sus bindings y la ventana muestra el estado vacío real.
El `Loader` de cada tarjeta fija su tamaño según selección (290×435 activa, 190×285 lateral) para que las laterales
aparezcan compactas desde el primer render. La respuesta de `/saves` conserva `used` para que la UI distinga ranuras
ocupadas de vacías.

La fidelidad visual exacta sigue pendiente de revisión renderizada a 1920×1080. El ciclo de arte y el selector SteamGridDB
ya están conectados al core, incluido logo, paginación, cambio de edición, validación de host y selección persistente; falta
probarlos con la clave del usuario. Siguen pendientes el cambio de salida de audio y la navegación del PDF. Hechos el 16/11: energía (`/power`, con
confirmación en la UI), panel «Sistema» completo (`/system`: modelo/GHz de CPU, disco de juegos, batería; curva de temperatura
de 60 s en la UI) y el Big Menu v8 (ver registro). El espectro del monitor de salida se calcula en 32 bandas mel de 55 Hz a
9,5 kHz (Goertzel con ventana propia por banda, captura a 22,05 kHz en trozos de 20 ms; sin análisis en silencio: ~7 % de CPU,
la FFT anterior costaba ~27 %); las ondas están siempre activas (reposo = oleaje suave abajo) y solo se ocultan con un juego en
marcha, una ventana maximizada o el Big Menu. Requiere `pipewire-pulse`
(`parec`); las muestras solo se procesan en memoria. Falta validar con audio real en la sesión de KDE. No mostrar métricas
de ejemplo como reales.

El reproductor MPRIS interpola la posición según la velocidad; conserva su reloj local cuando un cliente devuelve cero o
un valor viejo y solo reajusta al recibir un salto significativo. Si no se conoce la duración, muestra `—`. Título,
artista y aplicación de origen admiten marquee. El fondo
conserva la proporción con `PreserveAspectCrop`, un overscan del 14 % y paneo horizontal reversible de 80 s por sentido.

**Prototipo visual:** `docs/prototipo-visual.html` muestra una propuesta navegable del escritorio Omnia a 16:9, con shelf,
panel superior/dock Plasma, filtros, ficha y ports, ranuras, tarjetas, panel MPRIS/sistema, Big Menu y energía. Sus datos son
ilustrativos; métricas no integradas se señalan con «—». Es una maqueta de diseño, no un tema instalable ni UI conectada.

**Pendiente:**
- Comparar detalles de arte/logo, ficha y telemetría a 1920×1080 contra el PNG de referencia.
- Probar selector/ciclo de arte con la clave local de SteamGridDB sin revelar su contenido.
- Completar y revisar el menú contextual, energía, audio, métricas, paridad Big Menu/mando y navegación
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

- 2026-11-16 (2) — Correcciones tras la primera revisión visual. Reproductor: la posición MPRIS se congelaba entre correcciones
  (el `Timer` re-anclaba justo antes de leerla, tiempo transcurrido ≈ 0) y solo saltaba cada ~2 s; ahora avanza con el reloj
  local cada 100 ms y el reproductor solo corrige saltos > 2 s; iconos `PlayerIcon.qml` (los del prototipo). Tarjetas: máscara
  de esquinas sobre toda la tarjeta (antes asomaban las esquinas del fondo). Cabecera: iconos Kirigami (search, shutdown,
  refresh, speakers), icono de mando e «application-menu» del prototipo. Buscador: oculta las pastillas, ocupa toda su zona y
  es opaco; «1 juego» en singular. Arte: `art.pick_edition` elige la edición de SteamGridDB por `art.year` y, si no, por
  plataforma (sw2/ps5 → la más reciente, n64/sw1/ps3/ps4 → la original); el importador conserva `year` (Ocarina de Switch 2
  = edición 2026, no la de 1998). Batería con color incremental (0 rojo → 100 verde, `HudRow.charge`). Plataformas ordenadas
  PC, PS5, Switch 2, PS4, Switch, PS3, N64. Fondo: 100 % del alto de la pantalla, sin zoom vertical, paneo horizontal de
  150 s por sentido. El arte ya descargado con la edición equivocada no se reemplaza solo: «Cambiar arte» / «Elegir arte».
  256 pruebas OK.

- 2026-11-16 — Paridad con el prototipo vivo (rama `paridad-prototipo`, sin push). Core: `audio.py` reescrito (32 bandas mel,
  Goertzel, 22,05 kHz: CPU de ~27 % a ~7 %); nuevos `system.py` (`/system`), `power.py` (`/power`, solo POST y lista cerrada de
  5 acciones) y `games/gfn.py` (juegos de GeForce NOW desde los accesos `.desktop` del escritorio; el importador ya no los
  descarta como «no soportado»); `art.fetch_game` ya no repite la consulta a SteamGridDB cada ciclo cuando un tipo de arte no
  existe (marca `.sin-arte`); las pruebas de modo juego usan nombres de proceso propios (antes congelaban el `aria2c` real del
  usuario y fallaban a ratos). UI: `Waves.qml` del prototipo (siempre activas, suaves, color del juego); corregido
  `formatTrackTime is not defined` (tiempos y barra del reproductor no funcionaban); panel Sistema con CPU/GHz, juegos,
  batería y curva; chip «Favoritos» sin la estrella duplicada; logo de la ficha alineado a la izquierda; insignia NUEVO en todo
  juego sin jugar; SVG de plataforma normalizados; capa «EN EJECUCIÓN» (bloquea la estantería mientras corre un juego; Esc la
  quita); `BigMenu.qml` rehecho (panel de cristal 56×43 u, píldoras en carrusel, favoritos arriba, fichas squircle de color,
  energía con confirmación, animación de entrada/salida, mando con zonas). Sin KWin Glass no hay desenfoque detrás del menú:
  se compensa con `panelDim` 0,88. No portado a propósito: detección de Hydra/ROMs; pendiente: teclado virtual del mando para
  buscar y selector de salida de audio. Probado con el core aislado + UI en ventana (capturas a 1920×1080); 251 pruebas OK.

- 2026-11-15 — Corregida la posición MPRIS que permanecía en `0:00`: el reloj local avanza con `rate`, persiste entre
  consultas y descarta respuestas viejas/cero; reajusta al detectar saltos del reproductor. Consulta posición cada 1 s,
  muestra `—` si Firefox no publica duración. Carga QML revisada en modo offscreen; paquetes `0.1.0-6` reconstruidos.
  Pendiente validar con el reproductor real.

- 2026-11-15 — Rehecho el reproductor: controles centrados ópticamente, posición MPRIS muestreada e interpolada usando
  `rate`, duración desconocida indicada con `—`, y marquee independiente para título, artista y origen (identidad de la
  aplicación). El fondo aplica overscan 14 % y movimiento horizontal delicado de 80 s por sentido, manteniendo
  `PreserveAspectCrop`. Carga QML revisada en modo offscreen; paquetes `0.1.0-5` reconstruidos en `/tmp/omnia-pkg/`.

- 2026-11-15 — Afinada la respuesta al audio: ventana FFT de 42,7 ms, consulta QML cada 42 ms, ataque más rápido, caída más
  sostenida y mayor amplitud/gamma para que los golpes y agudos de música rápida se perciban con fuerza. Mantiene la misma
  forma y el color por juego. QML carga en modo offscreen; paquetes `0.1.0-3` reconstruidos. Falta validar con música real.

- 2026-11-15 — Corregido un paréntesis desbalanceado en `Waves.qml` que impedía cargar `OmniaShell` y dejaba Plasma en su
  escritorio normal. La ventana QML completa ya carga en modo offscreen; paquetes reconstruidos. No se cambió configuración
  de Plasma ni se instalaron los paquetes. `pkgrel` subió a 2 para reemplazar la compilación `0.1.0-1` fallida.

- 2026-11-15 — Conectada la visualización a `parec`/PipeWire-Pulse para analizar el monitor de salida en memoria y producir
  16 bandas logarítmicas (20 Hz–24 kHz, muestreo a 48 kHz). Rediseñadas las ondas en cuatro capas del prototipo, asociadas a cuatro grupos
  del espectro y tintadas con el acento del juego seleccionado; ocupan el área inferior de 360 px como en el plasmoide.
  Añadida ruta local autenticada `/audio` y consulta QML cada 42 ms; `pipewire-pulse` figura como dependencia opcional.
  Paquetes reconstruidos en `/tmp/omnia-pkg/`. Pendiente revisar con audio real; sin instalar, commit ni push.

- 2026-11-15 — Añadida navegación del carrusel con la rueda vertical del mouse y touchpad: cada paso selecciona el
  juego anterior/siguiente, mantiene la animación de las tarjetas y se pausa mientras hay un menú o panel abierto.
  Sin alterar el estilo visual.

- 2026-11-15 — Reemplazada la composición aproximada por un port basado en el lienzo y los componentes QML del prototipo;
  añadidos metadatos seguros de presentación/ports en `/library`, navegación de ports en partidas y dependencia `qt6-5compat`
  para tintar iconos. Revisada ventana 1280×720; pendiente corregir la consulta QML de partidas y validar a 1920×1080.
  Sin instalación, commit ni push.

- 2026-11-15 — Diferida la consulta de partidas después de cambios en la selección; verificada en la ventana mostrando el
  estado vacío real. Conectadas las acciones contextuales de ciclo de arte y selector a rutas autenticadas de SteamGridDB;
  añadidos logo, galerías por edición/página, descargas limitadas a hosts permitidos, selección persistente y panel QML
  basado en el selector del plasmoide. Captura a 1920×1080 confirma las posiciones y tamaños del carrusel; queda comparar
  detalle de ficha y arte. Pendiente validar con la clave local; sin instalación, commit ni push.

- 2026-11-15 — Corregido el tamaño inicial de las cards: el `Loader` ocupa el alto seleccionado (435 px) o lateral (285 px)
  y el contenido llena el loader, evitando que herede los 435 px del slot. `qmllint`, carga QML en modo offscreen y
  `git diff --check` pasan. Sin instalar, empaquetar, commit ni push.

- 2026-11-15 — `/saves` ahora incluye el campo `used` de cada ranura; la UI ya mostraba todas como vacías porque el endpoint
  lo descartaba al construir su respuesta. No se cambió el estilo visual. Falta instalar/actualizar el core para verlo en la
  sesión real; sin empaquetar, commit ni push.

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
