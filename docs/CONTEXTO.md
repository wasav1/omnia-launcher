# Omnia — documento de contexto

> Documento vivo. Se actualiza con **cada cambio** (ver «Registro de cambios» al final). Es el punto de entrada para
> retomar el proyecto sin haber visto las conversaciones anteriores. Detalles por tema: ver `docs/`.

## 1. Qué es
Omnia es una aplicación instalable e independiente de biblioteca y gestión de juegos para Linux. Incluye un gestor de
escritorio, biblioteca unificada (Steam, Heroic, Lutris, ports, ejecutables y ROMs locales), un **panel rápido** y **Big
Mode**. Big Mode incorpora Inicio para catálogo, novedades y juegos recientes. Todas las superficies comparten el estado
mediante `omnia-core`; la integración con KDE Plasma 6 o Hyprland/illogical-impulse es opcional. También incluye control
con **mando**, **modo juego**, **historial**, **respaldo/restauración de partidas** y selector de español/inglés.

Repo: https://github.com/wasav1/omnia-launcher (privado por ahora). Se planea publicarlo para el AUR.
Principios: cambios en KDE siempre reversibles, Omnia no incluye ni descarga ROMs y solo analiza archivos locales que
el usuario elige; no detecta carpetas de Hydra. El disco de Bazzite se monta solo lectura y no se modifica.

## 2. Estructura del repo
| Ruta | Contenido |
|---|---|
| `core/omnia/` | Servicio `omnia-core` (Python, solo biblioteca estándar) |
| `ui/qml/` | Componentes QML compartidos por la app de escritorio, panel, Big Mode y los módulos opcionales de Plasma |
| `plasma/` | Wallpaper pasivo, widget interactivo y proveedor QML del token de sesión |
| `kwin/` | Scripts de KWin: `omnia-showdesktop`, `omnia-watch` |
| `packaging/arch/` | PKGBUILD (`omnia-core`, `omnia-app`, `omnia-hyprland`, `omnia-kde`), `build-local.sh` |
| `tests/` | Pruebas `unittest` (342). Ejecutar: `PYTHONPATH=core python -m unittest discover -s tests` |
| `docs/` | `MIGRACION`, `SPIKE-LAYER-SHELL`, `MODO-JUEGO`, `HISTORIAL`, `PARTIDAS`, y este documento |
| `legacy/`, `plasmoid/`, `tools/` | Material del prototipo y utilidades |

**Importante:** sin `PYTHONPATH=core` los tests importan el paquete instalado en el sistema (más antiguo).

## 3. Arquitectura
- **Servicio** `omnia.service` (systemd de usuario): API HTTP en `127.0.0.1:47831`. Token de sesión en
  `$XDG_RUNTIME_DIR/omnia/token` (0600), cabecera `Authorization: Bearer`, comprobación de `Host`, rutas que modifican solo
  por POST, sin CORS.
- **Aplicación principal**: `omnia-ui --manager` abre el gestor de biblioteca, catálogo, instalaciones y ajustes. Desde él
  se abre Big Mode, que comparte el mismo servicio local. El panel rápido es una integración opcional de Hyprland/ii o
  Plasma; ninguna integración de escritorio es necesaria para usar la aplicación.
- **D-Bus** `org.omnia.Core` (Gio/PyGObject): los scripts de KWin informan `SetDesktop(active, covered)` y llaman `ToggleMenu`.
- **Rutas API** (resumen): `/health /library /library/refresh /library/roots /rom/{scan,add} /game/{fav,hide,add,remove}
  /launch /apps /app/{launch,fav} /events /pad /emit /desktop /menu /menu/state /gamemode /fs/list /templates
  /saves/{config,backup,restore,open,suggest} /art/{browse,pick,cycle} /catalog/{games,game,platforms,install-packages}
  /installations{,/start,/cancel,/pause,/resume,/remove} /audio /system /power /import/{find,preview,apply}`.
- **Módulos del core:** `paths, store (state.json/library.json), security, launcher (systemd-run --user --scope), api, events,
  pad (evdev sin dependencias), audio, system, audio_out, power, dbus, service, apps, art (caché local compatible),
  online_catalog (Omnia Backend público), package_installs (instalación verificada), roms, gamemode, sessions,
  saves, fsbrowse, templates, manual, importer, roms (escaneo N64 local), online_catalog, games/{base,vdf,steam,heroic,lutris,gfn,refresh,registry}`.
- **Datos del usuario** (fuera del repo): `~/.config/omnia/{library.json,state.json,first-run.json,setup-backup.json,
  steamgriddb.key}`, `~/.local/share/omnia/art`.

## 4. Decisiones y hallazgos clave
- **Auditoría técnica (18/11/2026):** se redujeron los sondeos en reposo, se comparte un snapshot de procesos, `/library` usa revisión y caché de arte, el servidor HTTP está acotado y el token QML se importa de forma relativa junto a Omnia. Debian/openSUSE ahora comprueban dependencias; el `.PKGINFO` separa `pkgver` y `pkgrel`. El detalle y las limitaciones siguen en el PDF entregado por el usuario.
- **Tipografías empaquetadas:** Hanken Grotesk variable y Rajdhani 400/500/600/700 se incluyen en `assets/fonts/` con sus licencias SIL OFL y SHA-256; Omnia los carga desde su árbol QML para no depender de fuentes instaladas por el usuario.
- **Referencia visual (15/11):** material en `~/Juegos/PROTOTIPO OMNIA/` (9 capturas, PDF de 33 páginas y respaldos).
  Inventario, diferencias y etapas en `docs/REFERENCIA-PROTOTIPO.md`. Se priorizó la UI de Omnia; el tema/layout de Plasma
  queda fuera del código hasta capturar la configuración visual que el usuario termine de aplicar en su PC. Los respaldos del 14/11
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
**Correcciones de auditoría:** suite `unittest` en verde antes del trabajo Q-05 (342 pruebas, 3 omitidas); las cinco pruebas nuevas del diario pasan de forma enfocada. El workflow CI cubre Python 3.11–3.14, Bash y QML. Los scripts locales `qmllint`, `shellcheck` y `ruff` no estaban instalados, por lo que esos trabajos se ejecutan en CI. La ruta QML ahora es canónica, las fuentes de diseño se incluyen con licencia y el instalador pide confirmación antes de reiniciar Plasma. El AppImage revisión 38 empaqueta el diario de rollback Q-05 y quedó instalado. La protección cubre errores ordinarios, no corte eléctrico/SIGKILL/reinicio, y no revierte capas rpm-ostree. Sigue pendiente validar la matriz de distros/paquetes y todas las pantallas del instalador en Bazzite.
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
probarlos con la clave del usuario. Sigue pendiente la navegación del PDF. Hechos el 16/11: energía (`/power`, con
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

**Instalador local:** revisión 11 del asistente Arch y `.run` de fuentes preparados con dependencias completas para CachyOS.
El asistente ya compiló e instaló Omnia en este PC. Tras publicar QML_IMPORT_PATH y reiniciar Plasma,
se verificó el plugin cargado en el proceso real y ambos servicios activos; 19 pruebas de instalador OK.

**Pendiente:**
- Comparar detalles de arte/logo, ficha y telemetría a 1920×1080 contra el PNG de referencia.
- Probar selector/ciclo de arte con la clave local de SteamGridDB sin revelar su contenido.
- Completar y revisar el menú contextual, energía, audio, métricas, paridad Big Menu/mando y navegación del PDF.
- Cuando el usuario termine de configurar Plasma, tomar esa configuración como referencia para crear un preset nativo.
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
- **2026-11-23 — MangoHud con el estilo de Omnia (una línea, centrada):** nuevo `core/omnia/mangohud.py`: genera `~/.config/omnia/MangoHud.conf` (el archivo que Omnia ya pasaba con `MANGOHUD_CONFIGFILE` pero nadie creaba) con una píldora horizontal centrada arriba (`horizontal`, `horizontal_stretch=0`, `position=top-center`, esquinas redondeadas), fondo `#0B0F14` al 82 %, tipografía Rajdhani SemiBold (la de Omnia, se busca en `/usr/share/omnia/ui/qml/fonts` o `assets/fonts`), texto crema `#F3EFE3`, etiquetas de GPU/CPU en azul `#5B9BE0`, VRAM/RAM en dorado `#E8B86D`, separadores `#336599` y colores de estado verde/ámbar/rojo para FPS (30/60) y carga (60/90 %); solo la GPU dedicada (`gpu_list=1`). Lleva una marca en la primera línea: se regenera mientras esté y se respeta si el usuario la borra; nunca pisa un enlace simbólico ni el `~/.config/MangoHud` del usuario. Nuevo ajuste `/settings/mangohud` (y `mangohud`, `mangohud_installed` en `/settings`) con interruptor en Ajustes del escritorio y de Big Mode. Verificado a ojo con `vkcube` bajo `mangohud`. Tests: `test_mangohud.py` y `MangoHudSettingTests`.
- **2026-11-23 — Tanda 4 de ports (6 paquetes) preparada:** Race Into Space, Freeserf.net (The Settlers), gengine (Gabriel Knight 3), Underworld Revisited (Ultima Underworld), OpenChaos (Urban Chaos) y OpenGOAL Launcher (Jak and Daxter). Mismo método que la tanda 3 (`build_packages.py --deep`, estructura del archivo comprobada: ejecutable, `stripRoot`, nombres con `./` y con espacios admitidos por el esquema). Los seeds quedan en borrador; los publica el usuario con `--send-only --publish`. Se descartaron los archivos de «actualización» (Aquaria), los de 32 bits y los recomps de origen dudoso. La tanda 3 se publicó y verificó en la API pública (12 de 12).
- **2026-11-23 — Tanda 3 de ports (12 paquetes) preparada en el backend:** de `discovery.json` se eligieron motores libres con release estable, 64 bits y licencia clara: Ambermoon.net, Brogue CE, C-Dogs SDL, Augustus (Caesar III), dhewm3 (Doom 3), OpenHV, OpenJazz, SDLPal, Ironwail (Quake), SuperTux, PsyDoom (Doom PSX) y OpenSC2K. Se descartaron los de pre-release/`continuous`, los de 32 bits, los multi-mod (OpenRA) y los recomps de juegos filtrados o sin lanzar. Cada uno pasó `build_packages.py --deep` (datos de juego, estándares; sin VirusTotal por falta de clave) y se comprobó su estructura (ejecutable, `stripRoot`, enlaces simples). Backend: 344 pruebas OK; los seeds están en borrador y se publican con `--send-only --publish` (lo hace el usuario con su ADMIN_API_KEY).
- **2026-11-23 — La extracción TAR admite enlaces simbólicos simples (arregla OpenMW):** la prueba real de OpenMW falló con «El paquete TAR incluye enlaces o archivos especiales» porque su tarball trae 44 enlaces de bibliotecas (`libosgDB.so → libosgDB.so.162 → …so.3.6.5`). `_extract_tar` ahora acepta solo enlaces simbólicos cuyo destino es un nombre simple (sin `/`, `\\`, `.` ni `..`), los crea al final (ningún archivo se escribe a través de un enlace) y exige que cada uno resuelva a un archivo normal dentro de la carpeta (rechaza colgantes, circulares o que salen); enlaces duros, dispositivos y enlaces con ruta siguen rechazados. `_overlay_tree` (actualizaciones) admite esos mismos enlaces y los reemplaza. Tests: 563 OK.
- **2026-11-23 — Catálogo ampliado con 22 ports más y `setup.stripRoot`:** `discover.py` recorrió los 1.935 repos del catálogo (con un token de GitHub de solo lectura): 1.735 con release, 899 con build de Linux x86_64; `--enrich` añadió estrellas, licencia, archivado y último push. De ahí se eligieron, con criterio conservador (proyectos conocidos y mantenidos, licencia identificada, sin datos del juego en el paquete, ≤ 400 MB), 22 ports nuevos en `ports.json` (OpenRCT2, VCMI, Julius, OpenLoco, LEGO Island, OpenOMF, Lighthouse, Dusklight, Daggerfall Unity, TRX, OpenTyrian, Ghostship, PaperBoat, Goemon 64, Star Fox 64 Recomp, Conker, Nocturne, SMB Remastered, OpenMW, OpenTESArena, Dethrace, OpenCiv3); quedan como borrador hasta publicarlos. Se descartaron los repos con stars altas pero sin licencia o de dudosa procedencia (recomps de títulos recientes sin comunidad verificable), los de arquitectura 32 bits, y los que solo traen mods o varios AppImage por release. Nuevo `setup.stripRoot` (backend: esquema; cliente: `_strip_single_root`): si el paquete es una sola carpeta con la versión en el nombre, Omnia sube su contenido un nivel al instalar, así el ejecutable no cambia de ruta entre versiones y una actualización no deja carpetas viejas. `build_packages.py` usa `GITHUB_TOKEN` si existe. Pendiente de probar: instalar uno de los nuevos.
- **2026-11-23 — El editor de arte ofrece las imágenes de SteamGridDB (vía el backend):** el backend (`GET /games/:slug/artwork/options?type=grid|hero|logo&page=N`, proveedor `listAssets`) devuelve hasta 50 opciones por página de SteamGridDB para el juego enlazado (sin adultos, humor ni epilepsia; solo hosts permitidos; caché 10 min; la clave sigue solo en el Worker). Cliente: `online_catalog.fetch_art_options` / `download_option_image` (solo HTTPS del CDN de SteamGridDB, sin redirecciones a otro origen, ≤ 25 MiB, PNG/JPEG/WebP); `art_browse` da la imagen actual (página 0) más la página pedida (`more`, `linked`, `warning`; si el backend falla, queda al menos la actual); `POST /art/choose {id, kind, url}` la descarga, la verifica y la guarda como arte propio del juego (comparte `_save_user_art` con `/art/local`). Editor: «Ver más» pagina al llegar con el cursor, y avisa si el juego aún no está enlazado a SteamGridDB. Hasta desplegar el backend, el editor solo muestra la imagen actual. Arreglo: `nvidia-smi` da decimales («55.31»), ahora se aceptan y sale la temperatura de la GPU. Tests: `test_art_options.py`, `test_user_art.py` y los del backend.
- **2026-11-23 — Panel Sistema A2 con temperaturas y editor de arte de Big Mode (C1 con encuadre):** `system.live` añade `cpu_temp` (hwmon: `coretemp` «Package id 0», `k10temp`/`zenpower` «Tctl») y `gpu_temp` (nvidia-smi en la misma consulta de uso, o hwmon `amdgpu`); `gpu_stats` devuelve (uso, temperatura). Big Mode: el desplegable «Sistema» pasa a tres anillos (`SystemGauge.qml`: CPU, GPU, RAM) con la temperatura coloreada (verde ≤ 70 °C, ámbar ≤ 85, rojo), batería/perfil/disco en etiquetas y modelo del procesador, con el ancho de los botones Sistema y reloj. Menú contextual → «Cambiar arte» abre `OmniaArtEditor.qml`: a la izquierda tu biblioteca en miniatura (fondo, logo, portada) y a la derecha Portada/Fondo/Logo con las imágenes del catálogo; moverte por una miniatura la aplica solo a la vista previa y nada se guarda hasta «Guardar» (A); «Mi archivo…» (Y) abre el explorador, con encuadre Rellenar/Ajustar (X) cuyo resultado se dibuja fuera de pantalla y se guarda ya encuadrado; «Original» restaura. Backend: `GET /art/tmp`, `POST /art/local` (valida: archivo normal dentro de las carpetas permitidas, PNG/JPEG/WebP, ≤ 25 MiB, dimensiones razonables; copia a `~/.cache/omnia/user-art`) y `POST /art/reset`; `_art` da prioridad al arte propio (`art_custom`) y `art_pick` lo anula. Tests: `test_user_art.py` y las de temperatura en `test_system.py`. El tipo «Icono» del prototipo no se incluyó (la interfaz no lo usa).
- **2026-11-23 — Descargas e instalaciones independientes (escritorio y Big Mode), panel que abre solo el escritorio y nombre «Omnia Desktop Suite»:** Backend: los trabajos completados se retiran solos a los 10 s (`snapshot`) y no se restauran al reiniciar; `POST /installations/dismiss` (`{jobId}` o `{all:true}` para los que no salieron bien) y `POST /installations/retry` (repite una instalación o actualización); nuevos campos `completedAt` y `updateOf`. Escritorio: nueva pantalla `ManagerDownloads.qml` (pestaña «Descargas») con «En curso» (activas, pausadas y fallidas con Reintentar/Descartar/«Descartar N fallidas»; aviso «Instalado: X» una sola vez) e «Instalados» (Actualizar, Abrir ficha, Quitar); la app entiende `--game ID`, `--install-port`, `--update-port` y `--downloads`. Big Mode: pastilla «Descargas N %» en la barra (⚠ si hay fallidas) y pantalla `OmniaDownloads.qml` manejable con mando (↑↓, A pausar/reintentar/abrir ficha, X cancelar/descartar, Y descartar fallidas, B/START volver; START la abre desde cualquier pantalla). Panel (ii): `OmniaApi.openDesktop(id, action)` (ajuste `desktopCommand`, por defecto `omnia-ui --manager`): instalar, actualizar y «Jugar» de un juego sin port abren **solo la app de escritorio**; Big Mode queda para jugar. Nombre: «Omnia Desktop Suite» en la barra, el título de la ventana y `org.omnia.app.desktop` (Big Mode sigue como «Omnia Big Mode»). Tests: `test_installation_api.py` y `JobHousekeepingTests`.
- **2026-11-23 — Arreglo: un juego recién instalado no recibía arte durante mucho tiempo:** `art_worker` reconstruía la lista de juegos cada 60 s y, con muchos juegos, nunca llegaba al final (los últimos de la biblioteca, justo los recién instalados, se quedaban sin revisar; visto con Banjo-Tooie: `catalog_art_checked` seguía en 0 más de 10 min después de instalar). Nuevo `service.art_priority`: primero los juegos enlazados a una ficha aún no consultada. Prueba de instalación de Banjo-Tooie (primer port nuevo del catálogo ampliado): descargó, verificó y extrajo bien (`installSubdir` con subcarpeta), se registró y abrió; sin arte hasta este arreglo.
- **2026-11-23 — Más ports instalables (13 nuevos) y varios ports por ficha:** `pick_update` solo considera actualización una versión nueva del MISMO port (mismo `sourceName`/repositorio; el registro de instalación lo guarda) porque ahora una ficha puede tener varios ports (Majora's Mask: Zelda64Recomp y 2Ship2Harkinian; Mario Kart 64: SpaghettiKart y Mario Kart 64: Recompiled). Backend: `tools/release-packages/discover.py` (busca en los ~1.935 repos del catálogo los que publican build de Linux x86_64; reanudable; `GITHUB_TOKEN` sin permisos sube la cuota de 60 a 5.000 por hora; resultado en `seeds/release-discovery/discovery.json`) y `installSubdir` en `ports.json`. Paquetes preparados (borrador): 2Ship2Harkinian, Banjo-Kazooie, Banjo-Tooie, Diddy Kong Racing (DKR-R), Dinosaur Planet, Donkey Kong 64, Mega Man 64, SpaghettiKart y Mario Kart 64 Recompiled (N64), Mario Kart Super Circuit, Fallout 1/2 CE y DevilutionX; licencias declaradas tal cual (GPL/MIT/CC0, «Sin licencia declarada», PolyForm Noncommercial, Sustainable Use License). No se probó ningún binario descargado (no se ejecutan sin revisar). Descartados por ahora: ports con carpeta raíz versionada (F-Zero X, Mario Party: cada versión cambiaría de carpeta), dhewm3 (el release trae los mods), OpenRA (varios AppImage por release) y los que no tienen release.
- **2026-11-23 — Big Mode muestra los avisos del descriptor:** la pestaña Descripción de la ficha de Big Mode (`OmniaGameDetails.qml`) enseña, bajo la descripción, el aviso de cierre del port (`lastExit`), los requisitos que este PC no cumple (`requirements`) y si la copia del jugador es de otra versión (`romCopy.compat.state === mismatch`). El respaldo de partidas por descriptor ya se refleja en la fila «Respaldo» (usa `saves_info`). Los botones de carpeta siguen solo en la app de escritorio (en Big Mode requerirían foco de mando).
- **2026-11-23 — Fase 3 probada con un port real (mkw-recomp v0.1.17 → v0.1.18):** el aviso salió, la actualización superpuso el AppImage nuevo (nombre distinto), retiró el viejo, dejó intacto `~/.local/share/mkw-recomp` y conservó tiempo jugado y registro. Al abrirlo, mkw-recomp 0.1.18 rehízo su preparación («Preparado por 0.1.17»: generar/compilar código y shaders; exefs y romfs «ya hecho»): comportamiento del propio port. Los diálogos de actualizar ahora lo avisan.
- **2026-11-23 — Descriptor `recomplauncher.json` y revisiones de seguridad (ideas del SDK de RecompLauncher y de RecompStore):** nuevo `core/omnia/descriptor.py` (solo datos; marcadores cerrados `{install} {data} {local} {config} {home} {documents}`, rutas base y `..` rechazadas). `Api._descriptor_info` (caché 20 s, filtrada a carpetas permitidas) alimenta: partidas automáticas (`saves` → spec de `omnia.saves`, solo si el usuario no eligió otras ni el port las trae), compatibilidad de la copia por build ID (`inputs[].check.nup_build_id` contra el `buildId` de una carpeta exefs+romfs → `romCopy.compat` ok/mismatch/unknown; un `.nup` queda «unknown»: su formato aún no se lee), botones de carpeta (`folderActions`, `POST /folders/open`), requisitos (`requirements`: glibc comprobado, Vulkan solo informado) y avisos de `exit_codes` (`lastExit`, vigilando el proceso lanzado). Ficha de escritorio: compatibilidad, requisitos, aviso de cierre y botones de carpeta. Backend: `build_packages.py` revisa datos del juego (nombre y, con `--deep`, contenido de zip/tar), VirusTotal por hash (`VT_API_KEY`) y avisos de estándares; tests en `tools/release-packages/test_build_packages.py`. Docs: `docs/ESTANDARES-PORTS.md`. Tests en `tests/test_descriptor.py`.
- **2026-11-23 — Limpieza antes de promocionar el repo:** se quita `install-arch.sh` (un instalador de otra aplicación, el cliente de ChatGPT para Arch, que se coló en el repo el 2026-11-21; ningún archivo lo usaba). El registro de cuentas del AUR estaba cerrado temporalmente (HTTP 503, oleada de cuentas automáticas), así que se preparó una release de GitHub con los paquetes compilados desde la etiqueta v0.3.0 (`~/Proyectos/release-omnia-0.3.0`, con `SHA256SUMS`).
- **2026-11-23 — Versión 0.3.0 y auditoría previa al AUR:** `pkgver`/`pyproject.toml`/`omnia.__version__` suben a 0.3.0 (la etiqueta `v0.3.0` la crea el usuario al hacer público el repo). Escaneo del historial: sin secretos; quedan rutas con el usuario del sistema en `docs/` y `legacy/` (ver `docs/PUBLICAR-AUR.md`).
- **2026-11-23 — Preparación del AUR:** `packaging/arch/prepare-aur.sh` (comprueba la etiqueta en origin, `updpkgsums`, `.SRCINFO`, `namcap`, copia a la carpeta del AUR; no sube nada). Backend: 34 fichas con plataforma (`platform-assignments.json` + `assign_platforms.py`, plataformas nuevas `mobile`/`psvita`/`pce`) y 11 overrides de arte seguros, pendientes de que el usuario sincronice/aplique con su clave.
- **2026-11-23 — Guía de publicación en el AUR y propuesta de plataformas:** `docs/PUBLICAR-AUR.md` (nombres `omnia-*` libres en el AUR, repo público, nueva etiqueta v0.3.0, `updpkgsums`, `namcap`, `.SRCINFO`, push SSH; PKGBUILD con licencia GPL-3.0-or-later ya sin nota abierta). En el backend, `seeds/recomp-launcher/PLAN-fichas-sin-plataforma.md` agrupa las 70 fichas `draft` sin plataforma (8 fusionadas, 24 con consola clara, 38 que necesitan plataformas nuevas `mobile`/`ps2`/`psvita`/`pce`/`wii` o `pc`); decisión pendiente.
- **2026-11-23 — Detección de volcados exefs+romfs y build ID (`.nup`, paso 2):** `roms.inspect_dump_folder` reconoce una carpeta con `exefs/main` (NSO0) + `exefs/main.npdm` + `romfs/` (sin seguir enlaces, solo lee dos cabeceras): Title ID del NPDM (ACI0 +0x10; solo juegos base, `…000`) y build ID del NSO (+0x40, 20 bytes). `roms.scan` la lista como un juego y no la recorre por dentro; `rom_folders` solo la publica si es de Switch 2 (nombre = carpeta o, si es genérica como «Juego», su carpeta padre) y guarda `rom.buildId`; `Api._rom_copies` la une al port del mismo juego igual que un `.nup` y `romCopy` lleva `buildId`. La ficha de escritorio muestra «Tu copia del juego: ruta · build». Validado con los exefs reales de TotK (Title ID `0100F2C0115B6000`, build `277178b7…`) y Longshot (`0400486024DEC000`). Falta una tabla build ID → versión (1.0.0/1.8.0) para emparejar con el port. Tests en `test_roms_dump_folder.py` y `test_rom_copy_merge.py`.
- **2026-11-23 — TotK Recomp se inicia directo; Racing 8 DX confirmado:** el `AppRun` de TotK Recomp abre su asistente (`installer.gui`); `launcher._totk_play` lo sustituye, en cada lanzamiento, por `<dest>/totk` (cwd `dest`, de `$XDG_STATE_HOME/totk-recomp/setup.json`) cuando existen `totk-install.json` y el ejecutable es del usuario; si no, deja el asistente. Probado a mano: la ventana «TotK Recomp» abre por X11. Racing 8 DX (kartrecomp) sin juego construido: su `AppRun` (launcher Qt con ajustes/setup/build) es el punto de entrada correcto y su ventana abre bajo el sandbox; con el juego construido existe `AppRun play`, pero no se sabe dónde guarda el build, así que no se automatiza aún. Tests en `test_launcher_totk.py`.
- **2026-11-23 — Detección de releases nuevas (backend) y paquete más reciente primero:** `build_packages.py --check` compara la última release estable de GitHub con las versiones publicadas y con lo ya preparado en `seeds/release-packages` (informe; con `--send` prepara y envía solo los puertos con release nueva, como borrador o publicado con `--publish`); `hold` en `ports.json` deja en espera un puerto (Shipwright y sm64coopdx: licencia pendiente). El catálogo ordenaba los paquetes por versión como texto (`v0.1.9` > `v0.1.17`): ahora `created_at DESC` (backend) y el cliente elige el más reciente por `createdAt`.
- **2026-11-23 — Fase 3: actualizaciones de ports instalados:** `package_installs.pick_update` (compara `createdAt`, mismo formato, sin bajar de versión), `PackageInstallManager.start_update` (`POST /installations/update`; rechaza si el juego corre) y `_overlay_tree`: superpone el paquete sobre la carpeta instalada, solo reemplaza lo que trae, mueve lo sustituido y el ejecutable anterior a `.omnia-previo` y lo deshace todo si falla (rechaza enlaces simbólicos). `_finish_update` reapunta `launch/check/proc` y el registro. `/library` añade `updateAvailable` (desde `catalog_packages`, que se refresca cada 6 h y ahora guarda `createdAt`); ajuste `update_check` (`POST /settings/update-check`, activo por defecto). Interfaz: `OmniaPortInstall` en modo actualizar (BM: etiqueta «Actualización», acción del menú, `--update-port`), app de escritorio (aviso en la ficha, ⟳ en la lista, diálogo, interruptor en Ajustes → General), panel (acción «Actualizar en Big Mode»). Plan en `docs/PLAN-ACTUALIZACIONES-PORTS.md`. Tests nuevos en `test_package_installs.py` y `test_rom_copy_merge.py`.
- **2026-11-23 — Arreglo: juegos X11/XWayland abrían sin ventana desde Omnia (mkw-recomp):** `PrivateTmp=true` de `omnia.service` (heredado por los juegos) ocultaba `/tmp/.X11-unix`; el proceso quedaba vivo sin ventana. Bisectado por propiedad con `systemd-run` (solo `PrivateTmp` lo reproduce). Se añade `BindReadOnlyPaths=-/tmp/.X11-unix` (la ventana aparece con PrivateTmp activo).
- **2026-11-23 — Arreglo: la instalación de paquetes fallaba con `_check_hostname`:** en Python 3.12+ `urllib.request.HTTPSHandler` ya no guarda `_check_hostname`, y `_PublicHTTPSHandler.https_open` lo leía (todo paquete, p. ej. mkw-recomp, acababa en `failed`). Ahora solo pasa el contexto (que ya verifica certificado y hostname). Probado contra https real y con test nuevo.
- **2026-11-23 — Arreglo: el aviso del mando no escuchaba:** `OmniaApi.pollPad()` salía en silencio si el token del núcleo aún no había cargado cuando se activaba `padWatching` (arranque de ii), y nunca reintentaba, así que `padConnected` no se emitía (solo funcionaba `ipc call omnia padprompt`). Ahora reintenta cada 2 s mientras falte el token y se reinicia al cambiar el token (p. ej. al reiniciar `omnia-core`).
- **2026-11-23 — Los ports de RecompLauncher vuelven a arrancar el juego:** la migración `legacy_recomp` guardaba `launch: [AppRun]` e ignoraba `start.args` del `recomplauncher.json`; el `AppRun` de Longshot (constructor) salía sin hacer nada y el de Savage Wind sin `--game` tampoco arrancaba, así que solo Minecraft abría. Nuevo `start_args(root)` (solo `{install}`; ignora descriptores con `{game}` u otros marcadores) y `repair_launch_args(store)`, que corrige en cada arranque las entradas con `AppRun` suelto y se llama también tras instalar un paquete. TOTK y Racing 8 DX no tienen descriptor: su `AppRun` abre su asistente/launcher y se dejan igual. Probado a mano: `AppRun --play …/Longshot` mantiene el juego en ejecución. Tests en `test_legacy_ports.py`.
- **2026-11-23 — Aviso «Mando conectado · ¿Abrir Omnia?» (prototipo A) y Big Mode que se aparta mientras juegas:** Panel (Quickshell): `OmniaApi` mantiene una escucha permanente de `/events` (`padWatching`) y emite
  `padConnected` solo en conexiones posteriores al arranque; el singleton `OmniaPadPrompt` decide si mostrar el aviso (ajuste `padPrompt` en `hyprland.json`, panel cerrado, sin Big Mode abierto —clase
  `org.omnia.bigmode.qml6`— y sin juegos en marcha) y `OmniaPadPromptWindow` lo dibuja en el centro del monitor con el foco (capa Overlay): A/clic abre Big Mode, B/clic lo descarta, 12 s sin respuesta lo cierra.
  Interruptor «Preguntar al conectar un mando» en los ajustes del panel; prueba manual: `qs -c ii ipc call omnia padprompt`. Big Mode (`OmniaLibrary`): con un juego en marcha la ventana se oculta
  (`hideForGame`) y, cuando el juego se cierra (confirmado 1,5 s), vuelve a pantalla completa y con el foco; el núcleo no entrega botones del mando a la interfaz mientras hay un juego abierto.
  Hay que ejecutar `omnia-hyprland install` y recargar ii (`CTRL+SUPER+R`) para que el panel use los archivos nuevos.
- **2026-11-23 — «Instalar port» en todas partes donde antes decía «Jugar»:** un juego con `portAvailable` (volcado sin port instalado) muestra «Instalar port» (y el icono de descarga) en BigMode (botón del héroe, pie de
  ayuda, ficha del juego, tarjeta «Seguir jugando» del Inicio, tarjeta expandida de «Ver todos», menú), app de escritorio (página del juego, lista de «Juegos en este equipo»), panel de acceso rápido y `GameCard`; `manager.launch`,
  `OmniaApi.play` (panel) y `lib.play` ofrecen instalar en vez de lanzar, y `/launch` responde 409 con un mensaje claro si se intenta lanzar un juego así. Corregido el texto que se montaba sobre el logo ancho de consola
  (p. ej. Switch 2) en el héroe de BigMode: `leftPadding` sigue el ancho del icono.
- **2026-11-23 — Flujo «Instalar port» validado en las tres superficies (datos reales):** app de escritorio (⬇ en la lista, botón «Instalar port» y aviso en la página, ficha del catálogo sin el botón «Sin paquete
  publicado» cuando hay paquete), BigMode (insignia, botón, menú de X y diálogo con mando) y **panel de acceso rápido** (botón «Instalar port» y entrada «Instalar port en Big Mode» en el menú ⋯; abre BigMode
  con `--game <id> --install-port`, que selecciona el juego y abre el diálogo). `OmniaApi.openBigMode(id, details, installPort)`; icono `download.svg` añadido al panel.
- **2026-11-23 — «Port disponible» (fase 2 del plan de instalación de ports):** 
  Núcleo: `package_installs` admite el formato `appimage` (un solo archivo que pasa a ser el punto de entrada) y desempaqueta un `.tar.gz`/`.tar.xz` único dentro de un zip
  (Zelda64Recomp). **Corrección:** el flujo hacía `shutil.rmtree(archive)` sobre un archivo (`NotADirectoryError`), así que ninguna instalación real terminaba; ahora `archive.unlink`.
  El juego instalado se llama como su ficha y cuelga de su consola original (`online_catalog.local_platform_for`; p. ej. Mario Kart World → Switch 2) y lleva `variant` con el repo del port.
  `service.refresh_packages` guarda en `state["catalog_packages"]` los paquetes publicados de cada ficha enlazada (cada 6 h; al arrancar se reconsultan las fichas sin paquetes) y `/library`
  añade `portAvailable` a los volcados/ROMs enlazados a una ficha con paquete cuyo port aún no está instalado. Interfaz: BigMode (`OmniaPortInstall.qml`: paquete, versión, tamaño, fuente, aceptar licencia,
  destino = carpeta de instalación predeterminada; mando/ratón/teclado; insignia «Port disponible» en la tarjeta, botón «Instalar port» y entrada en el menú contextual) y app de escritorio
  (botón «Instalar port» en la página del juego → ficha del catálogo con su paquete; `localMatch` ya no toma por instalado un juego con `portAvailable`). Pruebas: `tests/test_package_installs.py`
  (AppImage, zip con tar interno, zip normal, SHA-256 incorrecto), `test_rom_copy_merge.py` y `test_catalog_search_link.py`. Requiere tener fijada la carpeta de instalación (Ajustes → General).
- **2026-11-23 — Un solo Zelda: el volcado `.nup` se une al port del mismo juego:** `Api._rom_copies` oculta de `/library` un volcado `.nup` (que ningún emulador puede ejecutar) cuando
  su ficha del catálogo coincide con la de otro juego cuyo port se ve en la biblioteca; ese juego principal lleva `romCopy` ({id, name, path}: «tu copia»). Sin port, el volcado
  sigue visible; una ROM que un emulador sí puede ejecutar (p. ej. N64) se mantiene como entrada propia. Pruebas: `tests/test_rom_copy_merge.py`.
- **2026-11-23 — Arte que tardaba en aparecer (Minecraft Bedrock):** una ficha revisada cuando el catálogo aún no tenía imágenes se reconsultaba solo cada hora (o cada 24 h).
  Ahora, al arrancar `art_worker` se descartan las revisiones de fichas sin arte (se vuelven a consultar enseguida) y los reintentos sin arte son cada 15 min.
- **2026-11-23 — Enlace por nombre con títulos que llevan dos puntos:** el catálogo busca la frase tal cual, así que «The Legend of Zelda Ocarina of Time» (nombre de un
  `.nup`, sin los dos puntos del título oficial) no encontraba su ficha. `service._search_queries` prueba también con las últimas 4 y 3 palabras («Ocarina of Time»);
  la coincidencia final sigue siendo exacta (`match_local_game`). Probado contra el catálogo real: el NUP de Ocarina of Time enlaza con
  `the-legend-of-zelda-ocarina-of-time-switch-2` y Mario Kart World con `mario-kart-world`. El arte de un juego recién enlazado tarda uno o dos minutos en bajar.
- **2026-11-23 — Detección de volcados `.nup` de Switch 2 (paso 1):** `roms.py` reconoce `.nup` como Nintendo Switch: si el nombre lleva un Title ID entre corchetes se usa
  (04… = Switch 2, 01… = Switch 1; las actualizaciones y DLC no se importan) y, sin ID, se toma por Switch 2 con confianza «extension». No se lee el contenido
  del paquete (solo los primeros 1 KB). `rom_folders` los publica como juegos de Switch 2 en las carpetas de la biblioteca. Probado con los `.nup` reales de
  `/mnt/JUEGOS/Nintendo/Switch-2` (solo lectura) y con archivos sintéticos (`tests/test_roms_nup.py`). Pendiente: carpetas de volcado `exefs/`+`romfs/` y leer el build ID del
  `exefs/main` (paso 2), que permitirá emparejar la versión (1.0.0/1.8.0) con su port.
- **2026-11-23 — Asistente «Añadir juego» de escritorio en tres pasos:** nuevo `ManagerAddGame.qml` (Origen · Detección · Confirmación) para la app de
  escritorio: carpeta de juegos (se añade como carpeta de la biblioteca y se cuentan los juegos nuevos), ROM de consola (abre el escaneo de ROMs),
  ejecutable/AppImage, port o emulador compatible (lista de plantillas) e importar biblioteca anterior. Pide el nombre y confirma con
  `api.addGame`. BigMode conserva `AddGame.qml` (pensado para el mando). `manager` y `api` se asignan desde el `Loader` (`onLoaded`): en el binding el nombre de la
  propiedad ocultaba al id del anfitrión.
- **2026-11-23 — Arte de Steam para juegos de Steam sin ficha:** `online_catalog.steam_art_urls` arma las URLs públicas del CDN de Steam
  (`cdn.cloudflare.steamstatic.com/steam/apps/<appid>/library_600x900.jpg`, `library_hero.jpg`, `logo.png`; sin claves ni cuentas) para los juegos
  detectados en Steam (id `steam-<appid>`). `download_artwork` las acepta solo con ese host y esa ruta exactos (sin redirecciones a otros
  orígenes), `service.sync_steam_art` las baja a la caché desde el `art_worker` (los fallos, p. ej. 404, se reintentan a las 24 h) y `Api._art` las
  usa solo cuando el juego no tiene arte del catálogo ni local. Privacidad: el CDN de Steam ve qué appids tienes, igual que el cliente de Steam.
  Pruebas: `tests/test_steam_art.py`. Minecraft Bedrock y demás juegos que no son de Steam ni del catálogo siguen sin arte.
- **2026-11-23 — Arte de juegos locales (enlace con el catálogo):** `art_worker` solo bajaba 150 fichas del catálogo (5 páginas de 30) para enlazar
  los juegos locales, así que con más de 1.600 fichas muchos nunca se enlazaban. Nuevo `service.search_candidates`: por cada juego sin ficha válida
  se busca por nombre (`q`) y se suman los resultados a los candidatos. Además, un juego enlazado cuya ficha aún no tenía arte (p. ej. Banjo-Kazooie,
  Donkey Kong 64 y Paper Mario, revisados cuando el catálogo no tenía imágenes) se reintenta cada hora en vez de cada 24 h.
  Pruebas: `tests/test_catalog_search_link.py`. Pendiente: los juegos que no están en el catálogo (Steam/PC como BioShock Infinite o Green Hell,
  Minecraft Bedrock) no tienen arte por diseño desde que se retiró la clave de SteamGridDB del cliente.
- **2026-11-22 — App de escritorio: esquinas, menús más pequeños y nombre:** todas las tarjetas con imagen (seguir jugando, catálogo, miniaturas
  de instalaciones, ficha del catálogo) usan `FadedImage` con `cornerRadius` y sus degradados con `radius`, así que las cuatro esquinas
  quedan redondeadas. Las barras usan `manager.cs = min(s, 1)` (no crecen con la ventana): barra superior de 46, menú de 14, Big Mode de 30
  y barra inferior de 26 sin «Añadir juego» (se hace desde la Biblioteca; solo muestra descargas y el estado). Ajustes gana «Acerca de»
  con el nombre completo «Omnia Desktop Suite»; en la interfaz el nombre sigue siendo «Omnia».
- **2026-11-22 — Paginador de «Explorar» corregido:** el botón siguiente salía vacío porque faltaba `images/lucide/chevron-right.svg`; se
  añaden `chevron-right`, `chevrons-left` y `chevrons-right` (Lucide). El paginador ahora tiene primera/anterior, números de página con
  puntos suspensivos (1 … n), siguiente/última y el total de juegos, con efectos de hover (relleno, borde, ligera ampliación y pulsación).
- **2026-11-22 — Rediseño de la app de escritorio (prototipo A, estilo Steam) e icono nuevo:** `OmniaManager.qml` sustituye la barra lateral por
  un menú superior (Inicio, Biblioteca, Explorar, Instalaciones; Big Mode y Ajustes a la derecha) y una barra inferior (Añadir juego,
  descarga en curso, estado). Inicio: banner con la novedad del catálogo (se carga al abrir) + estadísticas + «Seguir jugando».
  Biblioteca: nuevo `ManagerLibrary.qml` (colecciones Todos/Favoritos/Recientes, juegos agrupados por consola con logo, acciones
  Añadir/Escanear ROMs/Actualizar/Ocultos, y página del juego con banner, barra de acción Jugar/última sesión/tiempo, favorito y
  pestañas Resumen/Partidas/Administrar). Ajustes con secciones (General, Biblioteca, Big Mode con fondo animado). Explorar,
  Instalaciones y los asistentes (Añadir juego, ROMs, ficha del catálogo) conservan su funcionamiento con la nueva posición.
  Icono (prototipo 2: anillo sobre degradado oscuro con brillo): `assets/branding/omnia-icon.svg` (org.omnia) y
  `omnia-bigmode-icon.svg` (org.omnia.bigmode, con insignia de mando). La barra de tareas no mostraba icono porque Qt publica el app_id
  `org.qt-project.qml6`: las ventanas fijan `Qt.application.domain` (`app.omnia.org` / `bigmode.omnia.org`) para obtener
  `org.omnia.app.qml6` / `org.omnia.bigmode.qml6`, y los .desktop llevan `StartupWMClass` con ese valor.
- **2026-11-22 — Selector de plataforma sin estilo de botón y más compacto:** la pill de `PlatformPicker` pierde el relleno azul (solo un
  velo al pasar el ratón en modo ratón), su ancho se ajusta al contenido (sin mínimo de 190), iconos LB/RB de 30 y separación de 4.
- **2026-11-22 — Selector de plataforma (prototipo A) y sin búsqueda en el Inicio:** las pills de plataformas de la barra de la Biblioteca
  se sustituyen por `PlatformPicker.qml`. Con mando: una sola pill con la plataforma activa entre los iconos LB y RB (el contenido se
  desliza y se funde al cambiar; puntos de posición debajo; LB/RB siguen cambiando de filtro con `stepFilter`). Con teclado/ratón: la
  misma pill con una flecha que abre un desplegable (logo, nombre y cantidad de juegos; Tab sigue cambiando). El botón/caja de búsqueda
  ya no se muestra en el Inicio.
- **2026-11-22 — Menú contextual, teclado virtual, orden por favoritos/recurrentes:** `OmniaContextMenu.qml` (X en el mando, clic
  derecho, tecla M/Menú): Jugar, Detalles, Añadir/Quitar favoritos, Abrir carpeta de partidas, Ocultar de la biblioteca (`/game/hide`);
  Detalles pasa a ser una de sus opciones (I y Espacio siguen abriéndolos directo). Con mando, ↑ desde la estantería (o desde la primera
  fila de «Ver todos») enfoca la lupa y A abre `OmniaVirtualKeyboard.qml` (D-pad, A escribir, X borrar, Y espacio, START/Buscar, B
  cerrar; filtra en vivo). Orden de la estantería: favoritos > recurrentes (última sesión más reciente) > resto; «Ver todos» lo ofrece
  como orden por defecto («Favoritos y recientes») además de Nombre A–Z/Z–A/Consola. La tarjeta «Seguir jugando» del Inicio es
  translúcida y su portada tiene esquinas redondeadas (`FadedImage`).
- **2026-11-22 — Tarjetas sin arte translúcidas y cuadrícula pequeña por defecto:** las tarjetas sin portada (estantería, cuadrícula de
  «Ver todos», reflejo y mosaico del Inicio) usan un velo blanco translúcido (`#16ffffff`) en lugar del degradado/color sólido, como las
  filas de la lista. «Ver todos» en cuadrícula arranca en tamaño S.
- **2026-11-22 — «Ver todos», modo lista con arte (prototipo A):** cada fila (84 de alto) lleva el hero del juego (`fondo`, o la
  portada si no hay) en el 70 % derecho, fundido hacia la izquierda con `FadedImage`, y el logo del juego a la izquierda
  (`logo`; sin logo se muestra el nombre) junto al icono de consola. En modo lista se oculta el fondo de la selección
  (`gameBackdrop`) para que no compita con los heros de las filas.
- **2026-11-22 — Estantería más pequeña, rebote sin recorte, «Ver todos» sin panel:** las tarjetas de la estantería pasan a 210×310
  (seleccionada) / 298 (resto), hueco 18 y reflejo 68; la lista reserva 30 de margen superior (`headroom`) para que el rebote no se
  recorte. Se elimina el panel lateral de «Ver todos»: pulsar la tarjeta seleccionada abre Detalles (`detailsRequested`), y al cerrar
  Detalles (`detailsFromAll`) se vuelve a «Ver todos» en el mismo juego.
- **2026-11-22 — Estantería plana con reflejo y rebote; «Ver todos» con panel lateral:** a petición, se descarta el escalonado
  (`StackShelf.qml` eliminado): la Biblioteca vuelve a la fila plana (`ListView` con el desvanecido de los extremos y la seleccionada
  fuera de la franja, la anterior asoma desvanecida; la segunda tarjeta no queda comida por el desvanecido) y conserva el reflejo
  (`ReflectionImage.qml`, Canvas) y un rebote `OutBack` al cambiar de selección. En «Ver todos» se quita el card «Resumen»; al pulsar la
  tarjeta seleccionada se abre un panel lateral (~58 % del ancho, grid atenuado detrás) con portada, título, consola con logo,
  Jugar/Detalles, descripción y tiempo/última sesión/fuente. Dentro del panel: Esc/B cierra, Enter/A juega, I/X abre la ficha completa.
- **2026-11-22 — Estantería «escalera» con reflejo y «Ver todos»:** la Biblioteca usa ahora `StackShelf.qml` (tarjetas alineadas por abajo,
  la seleccionada delante y más grande, el resto escalonado detrás: más pequeño y oscuro cuanto más lejos; reflejo corto de espejo
  con `ReflectionImage.qml`, Canvas sin shaders). La selección empieza a la izquierda, avanza hasta la mitad, se queda en el centro
  mientras la lista se desplaza y cerca del final vuelve a avanzar hacia la derecha hasta la última (sin saltar al inicio).
  Nueva página `all` («Ver todos», tecla V / botón Y del mando): `OmniaAllGames.qml` con carril de consolas solo con logos,
  barra (Cuadrícula/Lista, tamaño S/M/L, orden, agrupar por consola), cuadrícula con cabeceras por consola donde la seleccionada se
  expande en su fila, y panel «Resumen». Teclas: flechas, Enter, I, Esc, Tab (consola), +/- (tamaño), O (orden), G (agrupar), L (vista);
  mando: LB/RB consola, LT/RT tamaño, SELECT orden, START agrupar, Y vista. Los logos de consola (`PlatIcon`) se usan también en el
  subtítulo del héroe de la Biblioteca, cabeceras y filas de «Ver todos». Probado con el arnés offscreen; los SVG no se pintan allí.
- **2026-11-22 — Estantería: la seleccionada fuera del desvanecido:** la tarjeta seleccionada de la Biblioteca se colocaba pegada al
  borde izquierdo y el desvanecido le comía su parte izquierda (al volver atrás desde tarjetas lejanas). Ahora
  `preferredHighlightBegin = fadeWidth + 6u` (la seleccionada queda después de la franja y la anterior asoma desvanecida) y el
  desvanecido izquierdo (`leftAmount`, animado 220 ms) se aplica siempre que la seleccionada no sea la primera, incluso con la
  lista en su inicio; al volver a la primera se apaga y se ve normal. Máscara de GPU: no verificable con capturas fuera de pantalla.
- **2026-11-22 — Halo B, carrusel de 400 y mando en el panel de acceso rápido:** (1) La carátula del carrusel lleva una sombra negra suave
  y continua (`SoftShadow.qml`, Canvas con `shadowBlur`, borrando el propio rectángulo) en lugar de las 5 capas apiladas que dejaban
  escalones; el carrusel pasa a 400 de alto (la fila de abajo a 310) y se quita la pastilla del mando del carrusel (`PadBattery` solo
  queda en las cabeceras de BigMode). (2) Hallazgo: un `Canvas` con ancho/alto fraccionario se dibuja en blanco; `FadedImage` fija
  `canvasSize` redondeado y `SoftShadow` usa tamaños enteros. (3) Panel de acceso rápido (Quickshell/ii): `OmniaApi.qml` guarda
  `padOn/padName/padFamily/padBattery` de `/events` y el nuevo `OmniaPadChip.qml` (nombre, pila y %, ámbar ≤30 %, rojo ≤10 %,
  «Sin mando» apagado) va en la cabecera de `OmniaPanelContent.qml`. Hay que volver a ejecutar `omnia-hyprland install` (copia los
  QML al ii del usuario) y reiniciar ii (CTRL+SUPER+R). Comprobado con módulos de ii simulados; no con el Quickshell real.
- **2026-11-22 — Ondas más naturales, desvanecido de la estantería, Inicio sin imagen del juego:** `WaveField.qml` ahora tiene
  seis olas independientes (altura, amplitud, tres componentes con frecuencias no múltiplos, velocidades y sentidos distintos,
  respiración lenta de la amplitud y vaivén de la base). La estantería de la Biblioteca desvanece las tarjetas cortadas en cada
  extremo solo del lado donde hay más contenido (`OpacityMask` sobre el `ListView`; se omite con el renderizador por software,
  `GraphicsInfo.api`, donde no hay shaders: no verificable con capturas fuera de pantalla). La imagen de fondo del juego
  seleccionado (`gameBackdrop`) se funde y desaparece en el Inicio para no chocar con el banner. El panel de novedades muestra
  «Sin mando» cuando no hay mando (`PadBattery.showWhenAbsent`) además del nombre, pila y % cuando lo hay. Suite: 406 OK.
- **2026-11-22 — Carrusel con fundido total, ondas en la Biblioteca y transición entre fondos:** (1) El panel de novedades
  de `OmniaHome.qml` ya no tiene marco: el banner se desvanece por los cuatro lados con el nuevo `FadedImage.qml` (Canvas +
  composición `destination-in`, sin shaders; también redondea esquinas), la carátula lleva esquinas redondeadas y un halo del color
  de la consola, el foco se ve en el botón principal con flechas ‹ › discretas, y dentro del panel va la pastilla del mando
  (`PadBattery`). (2) Nuevo `WaveField.qml` (5 capas de olas, tinte con fundido de 1,2 s) solo en la Biblioteca; Inicio y ficha
  conservan la constelación; Ajustes sigue opaco. (3) `OmniaLibrary` mantiene los dos fondos y los funde en 0,7 s al cambiar de
  sección (`wavesPage`); cada uno se detiene del todo cuando es invisible o hay un juego abierto. Un solo interruptor «Fondo
  animado» lo apaga todo. Verificado con capturas fuera de pantalla (OpacityMask/ShaderEffect no se renderizan sin GPU, por eso
  el desvanecido usa Canvas). Suite: 406 OK.
- **2026-11-22 — Fondo animado «Constelación» en BigMode:** nuevo `ui/qml/Constellation.qml` (Canvas a media resolución,
  30 fps, 64 puntos que flotan y se enlazan, brillo arriba a la derecha) detrás de todo el contenido de `OmniaLibrary`
  (Inicio, Biblioteca y ficha; Ajustes tiene fondo opaco). Se tiñe con el color de la consola de la novedad que muestra el
  carrusel (`OmniaHome.platformTints`, azul de Omnia por defecto) o con el acento del juego en la biblioteca, con fundido de
  1,2 s; intensidad 0,5 cuando el juego tiene imagen de fondo. Se detiene con un juego abierto (`gameRunning`), con BigMode
  cubierto o con la ventana oculta. Ajuste «Fondo animado» en Ajustes de BigMode (`animated_background` en
  `/settings`, `POST /settings/animated-background`, activado por defecto). Tests: `test_settings_background.py`. Suite: 406 OK.
- **2026-11-22 — Inicio de BigMode con carrusel automático y batería del mando en todas las pantallas:** (1) `OmniaHome.qml`
  rehecho (prototipo 2 elegido): carrusel de novedades del catálogo (avanza solo cada 8 s, se detiene con el foco encima o
  con una ficha abierta; sin catálogo usa los recientes con arte), tarjeta «seguir jugando» (Jugar/Detalles) y mosaico 2×2
  de accesos (Biblioteca, Favoritos, Sistema, Ajustes; la señal `openSection` la atiende `OmniaLibrary`). Navegación en
  2D con mando y teclado. Se retiran las filas «Seguir jugando» y «Novedades» anteriores y la tarjeta de «Instalaciones»
  del prototipo (BigMode no tiene pantalla de instalaciones). (2) Batería: `pad.read_battery()` lee
  `/sys/class/power_supply` (baterías `Device`, por MAC del mando o la única de periférico; nunca la del portátil);
  `PadReader` la publica con el mando y `/events` la envía como `padBattery`. Nuevo `PadBattery.qml` (nombre corto, pila y %,
  ámbar ≤30 %, rojo ≤10 %, verde al cargar; sin dato solo el nombre) en la cabecera de Inicio/Biblioteca, ficha del juego y
  Ajustes; en Biblioteca va compacto y los filtros se recortan al espacio libre. Sin mando real conectado: probado con
  ficheros de ejemplo y capturas fuera de pantalla. Suite: 402 OK.
  Comprobado con un Xbox Wireless real por BLE: no aparece en sysfs, pero sí en UPower
  (`gaming_input_dev_<MAC>`) y BlueZ (`org.bluez.Battery1`); `pad.read_battery_dbus()` los consulta con `busctl` (cada 20 s) cuando
  sysfs no tiene la batería. UPower no informa de carga en ese mando (State 0), así que no se muestra «Cargando».
- **2026-11-22 — Inicio de BigMode rediseñado, iconos reales de mando y sin rueda:** (1) `core/omnia/pad.py`: la familia
  de iconos (`xbox|ps|switch|deck`) se decide por fabricante USB/BT (`VENDOR_FAMILY`: 054c, 057e, 28de, 045e) con el
  nombre como respaldo; `EventBus` la publica como `padFamily` en `/events`. (2) Nuevo `ui/qml/PadGlyph.qml`: iconos de
  Kenney «Input Prompts» (CC0, ya en `ui/qml/images/pad/`) por familia y tecla lógica (A = cruz en PlayStation, botón A en
  Switch); `OmniaControlHint` acepta `padKeys`; pies de BigMode y de la ficha muestran los botones reales del mando
  conectado y su nombre (teclas si no hay mando). (3) `OmniaHome.qml`: navegación en 2D (destacado → seguir jugando →
  novedades) con foco visible, «Jugar» lanza el juego (`playLocalGame`), el destacado ya no se repite en la fila, marcador
  con iniciales/plataforma cuando falta portada, aviso de catálogo sin conexión con «Reintentar». (4) Sin rueda del ratón
  para cambiar de tarjeta (biblioteca y novedades: `interactive: false`); el Inicio solo se desplaza (Flickable) si no
  cabe; las filas avanzan solo con la navegación. Probado con capturas fuera de pantalla (`QT_QPA_PLATFORM=offscreen`)
  para cada familia de mando; sin mando real conectado. Suite: 396 OK.
- **2026-11-22 — Bedrock desde Omnia sale en negro (resuelto):** MangoHud descartado (con `MANGOHUD=1` el juego se ve
  lanzado desde consola). `APPIMAGE_EXTRACT_AND_RUN=1` y el scope de `systemd-run` también descartados. Reproducido el
  cuelgue lanzando el AppImage con el sandbox de `omnia.service` (PrivateTmp, NoNewPrivileges, ProtectSystem=full,
  ProtectKernel*, RestrictSUIDSGID, LockPersonality, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`) y corregido
  añadiendo `AF_NETLINK` (necesario para Wine/Proton): con él funciona. Cambio en `packaging/systemd/omnia.service`;
  hay que reiniciar el servicio tras instalar para que lo aplique.

- **2026-11-22 — Detección automática de Minecraft Bedrock (BedrockOnLinux):** nuevo `core/omnia/games/bedrock.py`
  (`BedrockDetector`, `auto: "bedrock"`, registrado en `games/registry.py`). Busca `BedrockOnLinux-<versión>-<arq>.AppImage`
  ejecutable a 2 niveles en: `external_roots`, las bibliotecas de Steam (carpetas con `steamapps`, p. ej. `/mnt/JUEGOS/PC`)
  y carpetas habituales (`~/Juegos/PC`, `~/Descargas`, `~/.local/bin`…). Elige la versión más nueva, lanza
  `<AppImage> play`, `proc = Minecraft.Windows.exe`, plataforma `pc`; no duplica una entrada manual con el mismo AppImage.
  Probado con `/mnt/JUEGOS/PC/BedrockOnLinux-2.3.1-x86_64.AppImage`. `tests/test_bedrock_detector.py` (7). Suite: 393 OK.
  Hace falta reinstalar los paquetes (`packaging/arch/build-local.sh`) para verlo en la app.
- **2026-11-22 — Caída por cuota de D1 y caché de lecturas públicas (backend, sin desplegar):** D1 (plan gratuito) superó
  su límite diario de filas leídas (error 7500) tras los jobs de artwork y las importaciones masivas: la API dio 500
  hasta medianoche UTC (19:00 locales). Tanda 3 (658 fichas de las demás consolas) sin aplicar. Nuevo
  `src/middleware/public-cache.middleware.ts`: caché de borde (Cache API) para GET públicos de `/games`, `/platforms`,
  `/artwork` con `PUBLIC_CACHE_TTL_SECONDS` (600 en wrangler.toml, 0 en pruebas). Test `tests/public-cache.test.ts`.
  Hay que desplegar con `npm run deploy` cuando D1 vuelva. Consejo: repartir jobs de artwork en varios días o pasar a
  Workers de pago.
- **2026-11-22 — Tanda 2 publicada (ps1, ps2, wii, gba, nds):** 322 fichas publicadas (total 990). Job de artwork
  `completed`: 394 resueltas, 119 en revisión (mayoría arrastradas de la tanda 1). 23 overrides nuevos en
  `seeds/recomp-launcher/artwork-overrides.json` (69 en total). Nuevo duplicado `spider-man-2000` → `spider-man`
  (`DUPLICATES`; `merge-duplicates.sql` con 14 pares). Pendiente: aplicar SQL + manifiesto y repetir el job.
- **2026-11-22 — Revisión de duplicados del catálogo:** comparados nombres de las fichas publicadas y de las `draft`.
  Ocho duplicados reales más (`DUPLICATES`/`ROM_DUPLICATES` en `build_manifest.py`: 1080° Snowboarding, The World Is Not
  Enough, Laser Lords, Ridge Racer Type 4, Castlevania SOTN, Chrono Trigger, Gundam Wing Endless Duel).
  `seeds/recomp-launcher/merge-duplicates.sql` (13 pares) mueve módulos y códigos de ROM a la canónica. `NAME_FIXES`
  corrige dos nombres que un manifiesto anterior estropeó (Pokémon Pokopia, Serious Sam: The Next Encounter).
  Pendiente: aplicar SQL + manifiestos. Detectado: fichas «combinadas» (un port que cubre varios juegos) que habría que
  repartir en una ficha por juego.
- **2026-11-22 — Tanda 1 publicada (switch, switch2, n64, pc, gamecube):** 675 fichas publicadas; artwork: 593 con alguna
  imagen, 82 sin ninguna (59 + 14 de N64 sin entrada fiable en SteamGridDB, resto por revisar). Overrides de arte en
  `seeds/recomp-launcher/artwork-overrides.json` (46) y `seeds/n64/artwork-overrides.json` (32). Detectadas 6 fichas
  duplicadas (recomp vs ROM): `build_manifest.py` las fusiona con `DUPLICATES` (módulos a la canónica, duplicada a
  `draft`). Pendiente aplicar ese manifiesto (dryRun/--apply) y repetir el job de artwork.
- **2026-11-22 — Publicación por consolas (backend):** aplicados en producción los manifiestos con plataforma (18
  plataformas nuevas → 32; 1424 fichas de recomps siguen `draft`) y el artwork de las 287 fichas de N64 (278 con imagen;
  14 sin ninguna, listadas en la conversación). `tools/recomp-launcher-import/publish_platforms.py <consolas…>` publica
  las `draft` de esas consolas (`--send` dryRun, `--apply` real); primera tanda: switch, switch2, n64, pc, gamecube = 383.
- **2026-11-22 — Alcance del catálogo y plataformas de los recomps:** decidido: el catálogo son los juegos con port/recomp
  (como RecompLauncher), de todas las consolas; las 287 fichas de N64 salidas de ROMs se mantienen (sirven para enlazar
  ROMs por cabecera). `omnia-backend/seeds/recomp-launcher/origins.json` guarda solo la consola de origen de cada
  recomp (dato tomado de la caché local de la app RecompLauncher, no de su web pública). `build_manifest.py` lo usa
  para dar `platforms` a las fichas nuevas y declara 18 plataformas nuevas (x360, ps3–ps5, psp, genesis, 3ds, wiiu…).
  Sin desplegar. El job de artwork solo procesa fichas publicadas: hay que publicar antes de pedir artwork.
- **2026-11-22 — Fichas de N64 desde ROMs (backend, sin desplegar):** `omnia-backend/tools/n64-catalog/build_n64.py`
  lee las cabeceras de `/mnt/JUEGOS/Nintendo/N64` y genera `seeds/n64/batch-01.json` (287 juegos `published`, plataforma
  `n64`, sin la ficha de Ocarina que ya existe) + `rom-identifiers.json` (código por ficha; versiones/regiones agrupadas,
  alias y `BY_CODE` para nombres distintos con el mismo código). `sync_n64.py` hace dryRun o `--apply` (importa y guarda
  códigos). Test `tests/n64-manifests.test.ts`. Falta: aplicar y curar artwork (ver mensaje de la conversación).
- **2026-11-22 — Ocarina de los manifiestos de recomps:** `build_manifest.py` asigna a mano los 8 ports ambiguos
  (`shipwright` → ficha N64; `heylisten`, `greenkid-mv`, `nx2navi`, `nx2navi-zelda-oot-port`, `oot2026-pc-recomp`,
  `toot-r`, `ocarina-recomp` → Switch 2) y añade `longshot` (no está en RecompLauncher; repo
  `git.magicbean.dev/MagicBeanDev/Longshot`) a la ficha de Switch 2. Ya no quedan ambiguos. Sin desplegar.
- **2026-11-22 — Catálogo de recomps (backend, sin desplegar):** `omnia-backend/tools/recomp-launcher-import/
  build_manifest.py` genera `seeds/recomp-launcher/manifests/batch-01…08.json` desde `https://recomplauncher.com/all`
  (el dominio del importador anterior tenía un typo: «recompauncher»). 1952 recomps → 1512 fichas de juego original
  (1509 nuevas en `draft`, 3 existentes) y 1944 módulos `planned`; 8 ports de Ocarina (N64 vs Switch 2) quedan fuera por
  ambigüedad (ver `summary.json`). Prueba `tests/recomp-manifests.test.ts` (ensayo sin escritura, importación e
  idempotencia). Sustituye al `import.sql`/`import_install_packages.sql` de Codex, que no se aplican.
- **2026-11-22 — Title ID de Switch y emparejamiento por nombre:** `roms.switch_title_id` lee el ticket (.tik) del
  contenedor PFS0 de un NSP (solo el índice) o el ID entre corchetes del nombre (XCI y NSP sin ticket). Los Title ID
  que empiezan por `04` son Switch 2 (criterio tomado de RecompLauncher; `platform_for` → `sw2`); las actualizaciones
  (`…800`) y el DLC (`…001`+) no se importan como juegos. Sin ID, `online_catalog.match_local_game(fuzzy=True)` empareja las
  ROMs con la ficha por palabras (sin etiquetas ni palabras vacías, tolerancia de prefijo, todas las palabras de la
  ficha y al menos la mitad de las del archivo), con plataforma compatible y sin adivinar si hay varias candidatas.
  Solo se aplica a ROMs; el resto de juegos sigue exigiendo nombre idéntico.
- **2026-11-22 — ROMs: detección por carpeta y sin emulador:** nuevo detector `games/rom_folders.py`
  (`auto: "roms"`): recorre las carpetas de la biblioteca (`external_roots`, las mismas de Ajustes → «Carpetas de la
  biblioteca») y publica cada ROM reconocida por cabecera, sin pedir emulador; se vuelve a leer solo si cambia el
  árbol (mtime de carpetas). Al pulsar Jugar, `manual.resolve_rom_launch` elige/rehace el emulador (409 con aviso
  «Instala X» si no hay ninguno) y guarda el resultado. El port lleva `rom: {path, system, emulator, internalId,
  internalIdType}`; `port_installed` basta con que exista la ROM. `/rom/add` acepta emulador vacío. El servicio enlaza las
  ROMs con su ficha por ID de cabecera (`service.link_roms_by_id`). Nombres limpios: «Legend of Zelda, The - X
  (U) [!]» → «The Legend of Zelda - X». Idea tomada de RecompLauncher (`roms.rs`: solo cabeceras, carpetas fijas).
- **2026-11-22 — ROMs de N64 no se detectaban + Inicio de BigMode:** `roms.scan`/`inspect_file` descartaban las
  carpetas permitidas porque `fsbrowse.allowed_roots()` devuelve `Path` y solo aceptaban `str`; ahora aceptan
  `os.PathLike` (prueba `test_roms_roots.py`). Verificado contra `/mnt/JUEGOS/Nintendo/N64`: 296 ROMs. Inicio
  rediseñado: destacado a todo el ancho con portada entera a la derecha (sin repetir el fondo), «Seguir jugando» en
  tres tarjetas del ancho de la fila y «Novedades» con portadas verticales y nombre/plataforma debajo.
- **2026-11-22 — Caché local del artwork y reloj de BigMode:** las imágenes del catálogo (el hero BotW pesa 6,5 MB)
  se descargaban en cada apertura. Ahora `online_catalog.store_artwork`/`prefetch_artwork` las guardan en
  `~/.cache/omnia/catalog-art` (se acepta la redirección del backend solo hacia `*.steamgriddb.com` por https) y la
  biblioteca y `/catalog/*` devuelven `file://` (`localUrl`) cuando ya están. Inicio decodifica a `sourceSize` reducido.
  El óvalo vacío junto a «Sistema» era el reloj: leía `lib.backend.language` (nulo en la ventana independiente);
  ahora usa `api`. Igual en `OmniaBigSettings` y `OmniaGameDetails` (`host.backend` → `host.api`).
- **2026-11-22 — Enlace automático con el catálogo:** `art_worker` descarga el catálogo cada hora (y cuando conoce la
  plataforma de una ficha) y enlaza (`service.auto_link_catalog`, `online_catalog.match_local_game`) los juegos sin
  ficha, o con una de otra plataforma, con la ficha de nombre idéntico y plataforma compatible; si hay varias
  candidatas no elige. Nunca pisa una ficha válida (posible elección manual). Backend: fichas de Switch/Switch 2
  publicadas con portada y fondo (Ocarina Switch 2, BotW, TotK, Mario Kart 8 Deluxe).
- **2026-11-22 — Fichas de Switch en el backend (preparadas):** migración 0005, plataformas `switch`/`switch2` y
  Title IDs ya aplicados en producción. Se añadió `omnia-backend/seeds/switch-fichas.manifest.json` (Ocarina de
  Switch 2, BotW, TotK, Mario Kart 8 Deluxe) con prueba que lo valida contra el esquema real (backend: 329 pruebas en
  verde). Falta importarlo con `ADMIN_API_KEY` y elegir portadas. Clave de administración: ya existe en producción pero
  no la conserva nadie; hay que renovarla con `wrangler secret put ADMIN_API_KEY`.
- **2026-11-22 — Inicio de BigMode destaca la biblioteca:** el destacado es el último juego jugado; el catálogo solo
  lo ocupa si no hay actividad local, y «Novedades» muestra todo el catálogo restante. Corrección: en delegados
  (`ListView`/`Repeater`) los arreglos anidados llegan como listas QML y `Array.isArray` falla; `artwork()`,
  `platforms()` y `OmniaManager.imageFor` usan `Array.from`.
- **2026-11-22 — Fichas del catálogo por plataforma:** una ficha solo se asocia a un juego local de su misma
  plataforma y solo entonces aporta su arte (`online_catalog.platform_compatible`, `fetch_entry`; el servicio guarda
  `catalog_platforms`; `game_catalog_link` responde 409 si no coinciden; `OmniaHome.localMatch` aplica lo mismo).
  Motivo: Longshot es el remake de Ocarina para Switch 2 y estaba enlazado a la ficha N64. Backend: migración 0005
  (identificadores `switch`/`switch2` por Title ID de 16 hex) y plataformas Switch/Switch 2 en el seed; sin desplegar.
  El servicio vuelve a consultar fichas ya revisadas que aún no tienen `catalog_platforms`.
  Pendiente: leer el Title ID de NSP/XCI en `roms.py` y publicar las fichas de Switch/Switch 2 con su arte.
- **2026-11-22 — Inicio de BigMode: catálogo e imágenes:** (1) `OmniaHome` nunca pedía el catálogo si nacía visible
  (solo reaccionaba a `onVisibleChanged`): ahora también arranca en `Component.onCompleted`. (2) En `OmniaLibrary`,
  `api: api` se resolvía a la propiedad nula del propio `OmniaHome`; ahora usa `lib.api` y `lib.api.games` (arreglaba
  también «Seguir jugando» vacío). (3) Barra superior: los chips de filtro seguían pintándose en Inicio y se solapaban
  con la búsqueda (`visible` solo en Biblioteca). (4) Estado vacío del destacado sin solaparse; la portada vertical se
  muestra entera a la derecha cuando no hay «hero»; «Novedades» se oculta si no hay más juegos. Verificado: el backend
  responde bien y Qt sigue el 302 hacia el CDN. Los 4 juegos sin `catalogSlug` no tienen imagen porque el catálogo
  desplegado solo publica Ocarina of Time.
- **2026-11-22 — Suite de pruebas alineada con la arquitectura independiente:** se eliminaron las pruebas del cliente
  SteamGridDB y de la clave (`test_art_key_api.py`, `test_installer_retry.py`, partes de `test_art.py` y
  `test_installer.py`) porque la clave vive solo en omnia-backend. Se corrigió `omnia-hyprland` (`ensure_library_command`
  llamaba a `_backend()`, ya inexistente; ahora usa `config_dir()`). `uninstall.SYSTEM_UNIT` permite aislar las pruebas
  del paquete instalado en el sistema. Suite: 357 pruebas en verde. Pendiente (diagnóstico 2026-11-22): `/library` solo entrega arte para juegos con `catalogSlug`; el catálogo
  desplegado tiene 1 juego (Ocarina of Time, 1 portada) y 4 de los 5 juegos locales no tienen `catalogSlug`, así que
  no muestran imagen. El backend responde 302 a `cdn2.steamgriddb.com` para `/artwork/<id>/image`; QML carga esa URL
  directamente (`download_artwork`, que rechaza redirecciones, no se usa en ningún sitio).
- **2026-11-21 — Continuación de la aplicación independiente:** el análisis local de ROMs cubre ahora N64, NES, SNES,
  Game Boy/Color/Advance, Nintendo DS, GameCube/Wii, 3DS, Switch, PlayStation, PlayStation 2 y PSP. Los formatos
  compartidos de disco (ISO, CHD, PBP, CSO y BIN/CUE) ofrecen selector de consola para evitar clasificaciones falsas;
  el usuario elige entre emuladores compatibles instalados. Se valida de nuevo la consola al importar y al lanzar, sin
  subir archivos ni hashes. La interfaz del gestor y Biblioteca/Big Mode muestran las nuevas plataformas; el catálogo
  inglés actualizado a 435 cadenas QML añade cobertura para biblioteca, partidas, arte y errores de red.
  Validación estática: `py_compile`, `bash -n`, `git diff --check`, `lrelease6` (435/435); el paquete `.deb` de revisión
  contiene el lanzador del gestor, Manager, Home y el catálogo compilado. No se ejecutaron pruebas automatizadas.
  No hay `qmllint` instalado.
- 2026-11-21 — El gestor de escritorio permite añadir y retirar carpetas externas con selector nativo; retirar solo oculta
  los juegos de esa ubicación y conserva los archivos. Biblioteca añade escaneo N64 de solo lectura en carpeta elegida,
  verificación de cabecera z64/n64/v64, título propuesto y confirmación individual para importación a Gopher64. La ruta y
  firma se revalidan al añadir, se evita duplicar ROMs y no se envía el contenido ni su hash. El gestor también expone el
  asistente de juegos locales y muestra las entradas instaladas/importadas para lanzarlas desde Instalaciones.
- 2026-11-21 — Clics del panel (reinstalado y comprobado EN VIVO con clic real por ydotool, núcleo real): causas encontradas con pruebas de dispositivo en copia aislada (con `hyprctl` el cursor «teletransportado» daba falsos positivos): (1) `HyprlandFocusGrab` — con el grab activo Hyprland trataba CUALQUIER clic dentro del panel como «fuera» y lo cerraba (panel de la barra); eliminado; (2) `mask: Region { item: body }` no se actualizaba y el panel dejaba de recibir clics (paneles de borde y también de la barra en ciertas posiciones: «no captura el puntero»); ahora `Region { x; y; width; height }` con números. Política de cierre: solo con «Jugar» o cuando el cursor no está sobre el panel (≥ 600 ms; posición real por `hyprctl cursorpos`, ya vale para barra, borde y atajo); si el cursor nunca entró, 8 s de margen renovados por la actividad de teclado; no se cierra con el menú ⋯ o los ajustes abiertos. Se mantienen Esc y ✕ como cierres explícitos. El atajo abre con teclado exclusivo (sin clic previo). La barra de scroll de la lista solo aparece si no cabe. Verificado: barra y 4 bordes × (hover → clic ×2 → cursor fuera) y «Jugar» cierra; en vivo: clic en juego mantiene el panel abierto y sale al quitar el cursor.
- 2026-11-21 — Correcciones del panel (reinstaladas): (1) silueta ÚNICA en un solo trazo SVG (cuerpo + esquinas cóncavas + esquinas redondeadas) en vez de piezas superpuestas: desaparece la separación entre las esquinas cóncavas y el panel, tanto desde la barra como desde el borde. (2) Cierre en modo lateral: manda la posición REAL del cursor (`hyprctl cursorpos` cada 250 ms mientras el panel está abierto por hover) y no los eventos de hover, que no llegan si el puntero está quieto al aparecer el panel; solo se cierra con el puntero fuera ≥ 600 ms; no se cierra con el menú ⋯ o los ajustes abiertos; aunque se fije con un clic sigue cerrándose al salir el puntero (si se abrió por hover). Probado moviendo el puntero real: se mantiene abierto dentro, también tras fijar, y se cierra fuera. (3) Se muestra el nombre del JUEGO (p. ej. «The Legend of Zelda: Ocarina of Time») y el port como subtítulo («Switch 2 · Longshot»): campo `variant` en `/library`, detector de RecompLauncher y BigMode. (4) La tarjeta del juego en el panel muestra su logo (o el nombre si no hay). Pendiente: el cierre al hacer clic entre juegos solo se probó indirectamente (causa probable: la misma de hover); IPC `omnia pin` y `status` ahora informan autoClose/pointerInside.
- 2026-11-21 — Pulido del panel y de BigMode (instalado en la sesión activa): el panel ya no sale cortado (columna de recientes flexible, 840 px), colores de la paleta de ii vía `OmniaTheme` (Appearance) con casi sin transparencia (alfa .95/.90), esquinas cóncavas en los cuatro bordes y desde la barra (componente `OmniaConcaveCorner`, verificado en una prueba offscreen de 4 bordes × 2 extremos), rebote al abrir (OutBack, superficie con margen para el rebote y `mask` para no tapar clics) y esquinas redondeadas limpias (sin borde en el cuerpo; regla de desenfoque `ignore_alpha = 0.88` para que el halo del antialiasing no se desenfoque). BigMode: botón «Volver» en la ficha, fondo de la ficha idéntico y animado como el de la biblioteca (zona arriba a la derecha, deslizándose), botón de ajustes (⚙) con página de ajustes (clave de SteamGridDB, actualizar biblioteca, estado del mando). Núcleo: Longshot (id de RecompLauncher) usa el catálogo de Omnia: Zelda: Ocarina of Time, Switch 2, descripción, búsqueda de arte por ese título y carpeta de partidas; la fusión de `refresh` actualiza plataforma/descripción/búsqueda de arte de los juegos del detector. 2 pruebas nuevas.
- 2026-11-21 — Instalado en la sesión activa el rediseño (módulo + atajo + regla de desenfoque en `custom/rules.lua`, con copias `.omnia.bak`). Hallazgo: tras instalar archivos singleton nuevos hay que reiniciar Quickshell; la recarga en caliente dejaba `OmniaTheme` sin registrar (panel blanco). Reiniciado ii con `qs kill -c ii; qs -c ii`; panel verificado con la paleta correcta y cerrado por IPC. El mensaje del instalador lo advierte.
- 2026-11-21 — Rediseño del panel rápido en dos columnas (lista con scroll, juego seleccionado, «Jugar», menú ⋯, hasta 3 recientes) y de la ficha de BigMode (`OmniaGameDetails.qml`, pestañas Descripción/Partidas/Actividad), según las dos referencias. Superficie única `quickshell:omniaPanel` (capa Top) por monitor: se despliega desde el botón (esquinas cóncavas) o entra por el borde (4 bordes × 3 posiciones, ajustes de activación Barra/Borde/Ambos), con desenfoque por regla de Hyprland (`--rules`). Paleta fija `OmniaTheme`. Menú ⋯: detalles, favoritos, fijar/quitar fondo del escritorio (solo a petición; sin rotación automática), abrir carpeta. Núcleo: `folder` en `/library`, `GET /game/activity`, historial de RecompLauncher como jugado/reciente; 18 pruebas nuevas (410 en total). Herramientas: `test-core.sh` (núcleo aislado con N juegos) y `test-shell.sh`; IPC `omnia key/bar/menu/settings/setting/status`. No instalado en la sesión activa. Incidente: una prueba pulsó «Jugar» y lanzó Longshot unos segundos (sesión de 19 s en el historial); se cerró y el modo juego se desactivó.
- 2026-11-21 — BigMode (antes «biblioteca completa»): oscurecido fuerte a la izquierda y abajo como en el diseño; la guía de botones solo aparece con mando conectado (`api.padOn`; sin mando hay botón ✕ para cerrar y la estantería baja); fondo en la zona superior derecha (88 % × 80 %), imagen de mayor resolución, nítida, deslizándose despacio de derecha a izquierda (recorrido 0,15–0,60, ida y vuelta de 18 s por tramo) y fundida con el color base por la izquierda y abajo; la ficha entra con fundido y desplazamiento. **Omnia ya no cambia el fondo del escritorio**: se eliminó la rotación/selección de `wallpaperPath` (y sus ajustes y pruebas); `OmniaWallpaper` solo restaura una vez el fondo original si una versión anterior lo había cambiado (restaurado en esta sesión: `wallhaven-og7xg7.png`). Núcleo: `art.upgrade_fondo` añade desde SteamGridDB (con clave) un fondo de mayor resolución cuando el mejor local es pequeño (una consulta por juego), 4 pruebas nuevas. El panel dice «Abrir BigMode». Instalador: elimina archivos obsoletos.
- 2026-11-21 — Nueva biblioteca completa (`ui/qml/OmniaLibrary.qml`, usada por `omnia-ui --window` / `main-window.qml`) con el diseño pedido: barra superior (logo, filtros Todos/PC/Switch/… por plataforma, búsqueda, estado del sistema CPU/GPU/RAM), ficha con logo, descripción, «Jugar» y «Detalles», estantería de portadas con anillo de selección y guía de botones; panel de detalles (versiones, tiempo de juego, favorito). Fondo `OmniaBackdrop.qml`: 100 % del alto (100vh) con la proporción original, sin desenfoque ni desaturado ni ampliación, a resolución nativa; si es más ancho que la pantalla se desplaza despacio (animado), si es más estrecho se pega a la derecha; fundido cruzado. Teclado y mando (←/→, Enter/A, Espacio/X, Tab/LB/RB, /, F, Esc/B) y selección sincronizada con el panel y el fondo del escritorio. Núcleo: `/system` añade `live` (CPU % por delta de /proc/stat, RAM, GPU % por sysfs AMD o nvidia-smi con caché 2 s); 5 pruebas nuevas. `OmniaShell` (Plasma/layer-shell) no se tocó. Verificado con capturas reales (selección por API: Savage Wind, BioShock). No probados: mando físico, búsqueda y Detalles con clic.
- 2026-11-21 — Ajustes dentro del panel de Omnia (icono de engranaje; Esc o flecha vuelven): estructura tomada de los ajustes de RecompLauncher (grupos con título y tarjeta, filas etiqueta + descripción + control, interruptores, selectores segmentados, campo con «Guardar»). Incluye la clave de SteamGridDB (campo oculto con ojo, estado «Guardada/Sin clave», «Obtener clave», «Quitar», «Guardar igualmente» si no hay red), fondo dinámico (activar, intervalo 5 min–1 h, pausa con batería) y acceso por el borde (activar, retraso). Núcleo: nuevas rutas `GET /art/key` (solo dice si existe), `POST /art/key/save` (formato, validación contra SteamGridDB, 0600 atómico; 422 si la rechaza; `force` si no hay red) y `POST /art/key/clear`; 9 pruebas nuevas (383 en total, OK). QML: `OmniaSettingsView/Switch/Segmented`, `OmniaSettings.set()` escribe `~/.config/omnia/hyprland.json`; IPC `qs -c ii ipc call omnia settings|setting <nombre> <json>`. Verificado en vivo: la vista abre y la clave falsa se rechaza (422) sin guardarse. No verificado: escribir/pegar la clave con el teclado real en el campo del panel.
- 2026-11-21 — Panel de Omnia rediseñado (tarjeta principal con el fondo del juego o del escritorio y «Siguiente fondo»; estantería de portadas con selección/▶; estados de error y vacío; botón de biblioteca) y clics migrados de `TapHandler` a `MouseArea`. Los componentes viven en archivos propios (`OmniaPill`, `OmniaIconAction`, `OmniaRoundedImage`): los componentes en línea con ciertos nombres hacían fallar la carga de ii (`is not a type`). Nuevo IPC `qs -c ii ipc call omnia …` (toggle/open/close/status/library). Comprobado: el atajo global y el IPC abren y cierran el panel; `omnia-ui --window` se abre por IPC. El clic real sobre «Abrir biblioteca completa» pendiente de confirmar por el usuario. Aviso: `SUPER+SHIFT+0` es de ii (mover a espacio 10); el atajo de Omnia es la letra O.
- 2026-11-21 — Corregido «Abrir biblioteca completa» en Hyprland: `omnia-ui` no estaba en el PATH (instalación desde el repositorio). `omnia-hyprland install` ahora guarda `libraryCommand` con la ruta de `ui/omnia-ui` en `~/.config/omnia/hyprland.json` (sin pisar un valor propio); aplicado también a la instalación actual. Verificado que `omnia-ui --window` abre la ventana (1920×1080, sin errores). El clic en el botón no se probó en la sesión real.
- 2026-11-21 — El instalador de Hyprland (`integrations/hyprland/omnia-hyprland install`) solicita la clave API de SteamGridDB: entrada oculta (`getpass`) o `--key-file`/`OMNIA_STEAMGRIDDB_KEY_FILE`, nunca por argumento; valida con `installer_backend.validate_key`, guarda en `~/.config/omnia/steamgriddb.key` (0600), conserva una clave existente con Enter, ofrece guardar si no hay red y se rinde tras 3 intentos; `--skip-key` la omite y sin terminal no espera. Se pregunta antes de escribir nada. 8 pruebas nuevas (`tests/test_hyprland_installer.py`). El instalador gráfico general ya tenía su `KeyPanel`.
- 2026-11-21 — Detector de RecompLauncher (`core/omnia/games/recomp.py`, registrado en `registry.py`): lee su `library.json` (solo lectura, nativo o Flatpak), toma metadatos del catálogo en caché, lanza con `recomplauncher --play <id>` y detecta «en ejecución» por la carpeta de instalación. `fetch_art` + `recomp_art_worker` descargan portada/fondo/logo desde recompstore.com (solo ese host, HTTPS, límites; desactivable con `"recomp_art": false` en config.json), así el fondo del escritorio funciona sin SteamGridDB. 9 pruebas nuevas (356 en total, OK). Verificado con omnia-core aislado y la copia de ii: detecta 4 ports, descarga 3 fondos, rotación sin repetir, selección fija, juego sin fondo usa el original, quitar selección reanuda; `appearance` y colores intactos. Corregida la ruta de la copia del fondo (`$XDG_STATE_HOME/omnia`). Pendiente: instalar en la sesión real y probar el lanzamiento real con `--play`.
- 2026-11-21 — Elegido el diseño híbrido para Hyprland. Nuevo `integrations/hyprland/`: módulo QML para illogical-impulse (estado único del panel con asomado/fijado, botón en la barra, zona del borde derecho, cliente de la API, fondo dinámico por `wallpaperPath` sin `switchwall.sh`), instalador reversible `omnia-hyprland` (verificado en una copia de ii: instalar/desinstalar deja el árbol idéntico) y `test-shell.sh` para pruebas aisladas. Lógica de fondos probada con `qmltestrunner` (15 casos). Nada instalado en `~/.config`; el QML aún no se ejecutó en Quickshell. Hallazgo: ii deriva la transparencia automática del fondo.
- 2026-11-21 — Diseño previo de la integración con Hyprland + illogical-impulse (CachyOS): `prototypes/hyprland/` con `index.html` (3 prototipos interactivos y simulador de fondos) y `README.md` (diagnóstico, recomendación, archivos, estrategia reversible, criterios). Hallazgo: ii dibuja el wallpaper con `Background.qml` (`wallpaperPath`); `switchwall.sh` regenera colores de terminal/Qt, así que no se usa para rotar. Solo prototipos: no se instaló ni se modificó la configuración activa. Pendiente: elección del usuario.
- 2026-11-18 — Validada la instalación de la revisión 38: binario del asistente y backend actualizados a las 11:03, core (38 fuentes), QML (337 archivos), wallpaper, applet, scripts KWin y fuentes (8 archivos) coinciden con el repositorio. `omnia.service` está activo y habilitado, Plasma activo, `/health` y `/library` responden 200; biblioteca con 36 elementos. No quedó un diario de transacción residual, consistente con la ruta de commit exitoso. No se provocó un fallo para probar rollback en el sistema real.
- 2026-11-18 — Q-05 de la auditoría: el instalador universal crea un diario privado de respaldo antes de modificar rutas propias de Omnia, archivos de configuración de instalación, enlaces systemd y preferencias de Plasma que toca el flujo. Si falla una operación, restaura archivos/directorios/enlaces, elimina destinos creados por esa ejecución, recarga systemd y recupera el estado previo de servicios. Solo descarta el diario al completar instalación o actualización; si falla la restauración, conserva el respaldo para recuperación manual. Las cinco pruebas unitarias enfocadas pasan en directorios temporales. Se construyó `Omnia-Installer-0.1.0-38-x86_64.AppImage`, se verificó su extracción y la inclusión del instalador y helper. SHA-256: `6d6cab2e127292d88d7b80554501d068061d499942d8f5492d8e751681f171f2`. Alcance limitado a errores capturados por el proceso: no cubre corte eléctrico, SIGKILL ni revierte paquetes añadidos a rpm-ostree.
- 2026-11-18 — Validada en Bazzite la actualización a revisión 37: `OmniaShell.qml` coincide con el fuente, Hanken Grotesk y los cuatro pesos de Rajdhani están instalados con hashes coincidentes; `omnia.service` y Plasma están activos, `/health` 200 y biblioteca con 36 juegos. El wallpaper cargó y no aparecen errores QML de Omnia en el journal posterior al reinicio. Pendiente revisión visual comparativa de métricas tipográficas.
- 2026-11-18 — V-02: se empaquetan Hanken Grotesk variable y Rajdhani 400/500/600/700 bajo SIL OFL 1.1, con licencias y hashes en `assets/fonts/README.md`; `OmniaShell.qml` registra las fuentes al cargar y el instalador las incluye en el árbol QML versionado. Confirmadas las familias con `QFontDatabase`; `qmllint` limpio y se retiró el import Effects no usado. Generado AppImage Bazzite revisión 37 y comprobado su contenido; fuentes instaladas y sin errores de carga, pendiente comparación visual de métricas.
- 2026-11-18 — Correcciones de la auditoría Omnia: API HTTP/1.1 con keep-alive, máximo 32 solicitudes activas, timeout/headers/cuerpo acotados y política de JSON; polling de audio reducido en silencio. `/library` evita reconstruirse cuando no cambia la revisión; se cachean archivos/resolución de arte y se comparte una foto de `/proc` durante 1 s. La navegación agrupa escrituras efímeras sin `fsync`; el fondo pausa bajo cobertura y limita la decodificación, y las ondas actualizan a 30 Hz. Se endureció el token y la unidad systemd, se limitó la descarga por redirecciones, el backend valida el JSON del asistente, Debian/openSUSE verifican paquetes, Arch genera `.PKGINFO` válido y la instalación QML usa una sola ruta y confirma el reinicio. Añadidos CI, pruebas de límites/rendimiento, salida de build en caché, `tools/release.sh`, guards de KWin, escalado centrado y retiro del subpaquete layer-shell. Suite: `PYTHONPATH=core python -m unittest discover -s tests` — 342 pruebas OK, 3 omitidas; la herramienta local no reportó `qmllint`, `shellcheck` ni `ruff`. Pendiente validar CI, Plasma real, distros/paquetes, fuentes exactas y el diseño de token por D-Bus.
- 2026-11-18 — Generado en Bazzite 45 Kinoite x86-64 el `Omnia-Installer-0.1.0-35-x86_64.AppImage` con las correcciones de auditoría y los ajustes previos requeridos para Bazzite/OSTree. AppImage extraído correctamente, dependencias ELF resueltas con Qt incluido; checksum en el `.sha256` y manifiesto con hashes de appimagetool/runtime. La instalación completa y el arranque de la GUI en una sesión Plasma quedan pendientes de prueba interactiva.
- 2026-11-18 — Validada la actualización real en Bazzite 45 Kinoite: deployment activo con capas Qt/CMake, `omnia.service` enabled/active, API `/health` 200 y biblioteca con 36 juegos; Plasma 6.8.3 activo y wallpaper Omnia reporta viewport. Los árboles instalados de core, QML, wallpaper, applet y KWin coinciden con el proyecto; el instalador `--check` no reporta dependencias faltantes. Sin errores de importación del plugin; queda una advertencia QML no fatal por valor `undefined` en `OmniaShell.qml:1316` (botón de aceptar arte sin cambios pendientes).
- 2026-11-18 — Corregido el binding `MouseArea.enabled` del botón “Aceptar cambios” en el editor de arte: `!!(...)` convierte la combinación de `artPending` a booleano aunque sus claves estén ausentes. Regenerado el AppImage Bazzite como revisión 36; falta instalarlo para confirmar que desaparece la advertencia en el journal de Plasma.
- 2026-11-18 — Validada la actualización de la revisión 36 en Bazzite: QML instalado idéntico al fuente, el servicio quedó activo desde 10:27, API `/health` 200, `/library` 36 juegos, Plasma 6.8.3 activo y wallpaper Omnia cargado. Desde el reinicio ya no se registra la advertencia `undefined` de `OmniaShell.qml`; permanece solo el aviso ajeno a Omnia del plugin opcional `org.kde.plasma.panelcolorizer`.

- 2026-11-17 — Conflicto de puerto con Estantería resuelto y blindado: `estanteria-helper.service` ocupaba 47831,
  por lo que `omnia-core` no arrancaba y la UI seguía hablando con el helper antiguo. Ese helper responde 200 a rutas
  desconocidas (incluida `/selection`), lo que hacía que `followSelection()` recibiera una selección sin `id` y
  devolviera el carrusel al índice 0 en un bucle; el wallpaper tampoco recibía `fondo`. El instalador deshabilita
  `estanteria-helper.service` y verifica `/health` tras reiniciar Omnia, con aviso explícito si el puerto sigue
  ocupado. La UI y el wallpaper validan `id`/`revision` antes de aceptar una respuesta y reintentan con espera si no
  la traen. Verificado en Bazzite: navegación, selección y fondo funcionan. Se publica
  `Omnia-Installer-0.1.0-34-x86_64.AppImage` con el instalador y los QML corregidos.
- 2026-11-17 — Ajuste del flujo OSTree tras la primera prueba real en Bazzite: `dependencies.sh` ahora prepara el deployment con `rpm-ostree install --idempotent` y solo ejecuta `apply-live` cuando el cambio son adiciones; si `rpm-ostree db diff` muestra reemplazos o retiradas (`!`/`-`, típico al superponer `-devel` sobre un Qt base algo más antiguo), se pide reiniciar en lugar de dejar que `apply-live` falle con «packages would be removed». `check-dependencies.sh` acepta que un paquete esté cubierto por otro nombre mediante `rpm -q --whatprovides` (Bazzite provee `mangohud` como `terra-mangohud`), evitando que el chequeo lo siga marcando como faltante tras el reinicio. 9 tests de detección/verificación OK. Se publica `Omnia-Installer-0.1.0-32-x86_64.AppImage` con esas correcciones y la GUI recompilada (cierre de sesión con `qdbus6`/`qdbus-qt6`/`qdbus`). Corregida además la desinstalación en homes con enlace (Bazzite/OSTree monta `/home` -> `/var/home`): `validate_paths` permite los enlaces que forman parte de la ruta del home y mantiene el bloqueo de enlaces internos; la `Revisión 33` del AppImage incluye el arreglo.

- 2026-11-17 — Compatibilidad inicial con **Bazzite / Fedora OSTree**: nuevo `packaging/universal/distro.sh` detecta `ID=bazzite`, `ID_LIKE=fedora` y `/run/ostree-booted` (incluso desde un sandbox Flatpak vía `/run/host/os-release`, y admite `OMNIA_OS_RELEASE` para pruebas); `install.sh`, `launch-gui.sh`, `dependencies.sh` y `check-dependencies.sh` ya no rechazan OSTree y usan `rpm-ostree install` (con `--apply-live` si está disponible) para las dependencias del perfil Fedora. Se añade `qt6-qttools` a dicho perfil: en Fedora ese paquete instala `qdbus-qt6` (no `qdbus6`), así que el instalador, el desinstalador y la GUI aceptan `qdbus6`, `qdbus-qt6` o `qdbus`. Omnia sigue instalándose solo en `~/.local`. Corregido un fallo de `--check` en Fedora: se consulta cada paquete con `rpm -q` en lugar de parsear el texto de rpm (Bazzite devolvía «no se pudieron comprobar las dependencias»). 8 tests de detección/verificación OK; suite completa sin regresiones nuevas (fallos preexistentes en pad/candidatos/sesiones). Falta validar la instalación real en Bazzite 45 Kinoite (OSTree `45.20261112`, NVIDIA open).

- 2026-11-17 — La fila GPU vuelve a mostrar el nombre del modelo de tarjeta, junto al porcentaje de uso y la memoria usada/total; se elimina la etiqueta redundante «VRAM» del valor secundario.

- 2026-11-17 — La fila combinada del monitor mantiene VRAM en el valor secundario y en el porcentaje de alerta, pero el título queda simplemente como «GPU».

- 2026-11-17 — AppImage revisión 15 incluye el selector manual de juegos, posición configurable de notificaciones, cierre de sesión opcional y el rediseño de selección de arte/monitor GPU-VRAM.

- 2026-11-17 — El menú contextual deja de rotar arte automáticamente. El selector se hace más compacto, conserva selecciones de portada/fondo/logo sin aplicarlas, mantiene una previsualización fija de las tres y solo las aplica al pulsar Aceptar. Los acentos estáticos adoptan el azul grisáceo Omnia (`#91a9c2`) y se conserva el acento dinámico por juego. El HUD une GPU/VRAM y colorea las métricas de uso de verde a rojo conforme aumenta la carga; la batería mantiene el gradiente inverso.

- 2026-11-17 — Ajustes generales incorpora la pestaña Notificaciones para ubicar los avisos temporales de Omnia en cualquiera de las cuatro esquinas. La preferencia se guarda en `config.json`, la API la expone a la UI y el toast se coloca en la esquina seleccionada.

- 2026-11-17 — Omnia añade acceso directo `+` en la cabecera para elegir un ejecutable con el selector de archivos de Qt/Plasma. Un endpoint de sugerencias aplica el catálogo de ports conocidos (nombre, plantilla y plataforma) o propone el nombre del archivo; el usuario confirma/edita antes de añadir. Se conserva el asistente manual existente para ROMs y plantillas.

- 2026-11-17 — El instalador informa al finalizar que se debe cerrar sesión y volver a entrar para cargar correctamente las integraciones. Incluye una casilla opcional y desmarcada para cerrar sesión automáticamente tras una instalación exitosa, con aviso para guardar el trabajo. AppImage reconstruido como revisión 14.

- 2026-11-17 — El resumen de instalación ahora indica que conviene cerrar sesión y volver a entrar para completar la carga del wallpaper e integraciones. Se añade una casilla opcional, desmarcada inicialmente, para cerrar la sesión de Plasma automáticamente tras instalar; muestra aviso previo para guardar el trabajo.

- 2026-11-17 — Icono propio para el desinstalador: aro circular Omnia azul grisáceo con insignia de papelera. Integrado en la entrada del menú y en los paquetes Arch, AppImage y universal; revisión 13.

- 2026-11-17 — Revisión 12 del asistente: AppImage x86-64 regenerado con el icono circular azul grisáceo, catálogo de ports, revisión visual de candidatos, detección de complementos, desinstalador y paneo del fondo a doble velocidad. Cambio local listo para publicar.

- 2026-11-16 — Se duplica la velocidad del paneo del fondo animado en `Backdrop.qml`: cada recorrido pasa de 150 a 75 segundos (ciclo completo de 5 a 2,5 minutos), manteniendo la curva suave `InOutSine`.
Más reciente primero. Cada cambio añade una línea aquí (y actualiza las secciones 4–5 si procede).

- 2026-11-21 — Omnia avanza hacia una aplicación independiente: primera ventana de gestión con Inicio, Biblioteca,
  Explorar, Instalaciones y Ajustes; Big Mode se abre desde el gestor y añade Inicio conectado al catálogo público.
  Ajustes ya permite registrar y retirar carpetas de biblioteca con un selector nativo, sin borrar archivos. La entrada
  de escritorio usa `omnia-ui --manager`; el paquete Arch ahora separa `omnia-app` del complemento `omnia-kde`.
  Pendiente: catálogo de instalaciones manifiestas, escaneo de ROM con vista previa, idiomas español/inglés y validación
  del instalador fuera de Plasma.

- 2026-11-16 — Revisión 11: instalador AppImage x86-64 para este CachyOS, con Qt Widgets y plugins Wayland/XCB
  incluidos para abrir el asistente sin compilarlo antes. Builder reproducible mediante herramientas externas
  versionadas; registra hashes de appimagetool/runtime, bibliotecas incluidas y glibc del host. La instalación
  compila los componentes con Qt del destino. Los procesos hijos recuperan el entorno del host para no mezclar
  bibliotecas del AppImage con Python/CMake/Polkit. Icono circular Omnia en azul grisáceo, transparente,
  conservando el logo original en el repositorio; se usa en AppImage, cabecera e iconos del asistente.


- 2026-11-16 — Revisión 10: corregido el acceso local del desinstalador. Plasma no siempre incluye ~/.local/bin
  en PATH; el instalador genera Exec con ruta absoluta y escape desktop, como ya hacía con Ajustes generales.


- 2026-11-16 — Revisión 9: desinstalador gráfico con confirmación, disponible en Ajustes y menú de aplicaciones.
  Retira componentes/datos de la instalación por usuario mediante lista explícita, restaura atajos y wallpaper/carpeta
  anterior cuando existe el respaldo (o fondo nativo), detiene servicios y recupera procesos congelados. Conserva juegos,
  partidas, respaldos, emuladores y dependencias; rechaza rutas redirigidas o que contengan partidas registradas.
  Puede retirar solo el paquete del asistente Arch mediante Polkit, sin autoremove. Instalaciones antiguas con
  omnia-core a nivel de sistema se remiten al gestor de paquetes antes de borrar datos de usuario.
  Verificación: 9 pruebas de limpieza en directorios temporales/flujos simulados, 20 de instalador y 3 de
  empaquetado OK; pantalla gráfica revisada sin ejecutar la desinstalación real.


- 2026-11-16 — Revisión 8: casilla redondeada azul centrada en la columna Agregar, sin rectángulo de selección
  vacío. Delegate conserva el estado del modelo, clic y barra espaciadora; foco dibujado alrededor de la casilla.
  Las entradas vinculadas muestran una insignia verde.


- 2026-11-16 — Instalador revisión 7: catálogo local de Longshot, Hookshot, NX2navi, Savage Wind y TOTK Recomp,
  con nombre canónico de juego, plataforma de origen y propuesta de ejecutable. Agrupa versiones por port,
  ignora launchers/builders/xlate y agrupa ports reconocidos del mismo juego conservando IDs existentes.
  Nuevas versiones siguen disponibles aunque otra esté vinculada; solo se agregan al confirmar la selección.
  Contadores por carpeta y totales distinguen juegos de ports/archivos y evitan contar dos veces rutas superpuestas.
  Comprobación previa de Gopher64 (nativo/Flatpak), UMU y emuladores personalizados con aviso de instalación,
  sin perder la selección; Gopher64 no se permite para ROMs ajenas a N64. No se modifica la biblioteca al actualizar.
  Pruebas de catálogo/importación y Qt real para contador y aviso de complemento; probadas las rutas reales de NX2navi,
  TOTK y Savage Wind sin ejecutar juegos. Verificación: 36 pruebas de instalador, catálogo, empaquetado y GUI OK.
  La detección por nombre/contexto no certifica versión ni compatibilidad.


- 2026-11-16 — Instalador revisión 6: rediseño Qt Widgets inspirado en el launcher de Longshot, con paleta oscura,
  acento azul, cabecera de cinco pasos, tarjetas, resumen de configuración, capacidad real del volumen y detalles
  desplegables. Progreso indeterminado durante trabajo y detalles abiertos automáticamente en fallo; se conserva
  la clave al reintentar. Apariencia compartida con ajustes y revisión de candidatos. Capturas revisadas sin instalar
  ni modificar la biblioteca. Verificación: 20 pruebas de instalador y 3 de empaquetado OK; smoke visual
  de las cinco páginas, ajustes (4 pestañas) y candidatos OK.


- 2026-11-16 — Clave SteamGridDB perdida al reintentar: la GUI limpiaba el campo incluso si --install fallaba
  antes de configure() (por ejemplo, por UMU ausente). Reintentar enviaba clave vacía y completaba sin arte.
  Se limpia solo tras instalación exitosa; en fallo se conserva únicamente en memoria. Regresión con GUI Qt
  y backend ficticio: fallo reproducido antes del cambio y validación del reintento con la misma clave.
  La clave real no existe en la configuración activa y no puede recuperarse del instalador cerrado.


- 2026-11-16 — Revisión 5: la superficie interactiva de Omnia se ancla al contentItem de la ventana de escritorio
  del monitor correspondiente, independiente de desplazamientos de la celda y del área reservada por los paneles.
  Sigue los cambios de tamaño y escalado lógico de Qt sin temporizador de posicionamiento. Se oculta en modo edición.
  El layout reutiliza la instancia y retira duplicados al reaplicarse. Verificado en la sesión real:
  DP-1, origen 0,0, superficie 1920×1080; Plasma y núcleo activos. Prueba Qt offscreen con 1920×1080,
  2560×1440, traslado a segunda ventana 1280×720 y cambio a 1536×864.


- 2026-11-16 — Instalador revisión 4: corregido `org.omnia.session is not installed` tras primera instalación.
  El plugin existía en ~/.local/lib/qt6/qml pero faltaba QML_IMPORT_PATH en systemd de usuario. Se añade
  environment.d persistente y publicación inmediata en el gestor tras daemon-reload, antes de reiniciar Plasma.
  Se preservan las rutas QML existentes.


- 2026-11-16 — Instalador Arch revisión 3: añadido `umu-launcher` al perfil compartido para evitar que
  la importación de juegos Windows falle en instalaciones limpias. Los ports Linux siguen sin usar UMU.


- 2026-11-16 — Instalador Arch/CachyOS revisión 2: lista compartida entre metadatos y preflight universal,
  incluyendo Make, Qt Tools (`qdbus6`), GLib, libpulse, KWin y agente Polkit KDE. Se verifica antes de la GUI
  y del despliegue y se bloquean `--check`/`--no-deps` si faltan paquetes. El payload incluye el perfil.
  Pruebas de contrato de dependencias en archivo y cancelación antes de instalar. En este PC falta CMake;
  Pacman no puede instalarlo hasta sincronizar la base de datos ausente de `openai-chatgpt` mediante actualización completa.
  Verificación: 18 pruebas de instalador OK; suite completa con D-Bus aislado: 292/294 OK, con fallos en
  tecla MENU e historial de reinicio breve (código del núcleo sin modificar). Formato Arch y payload comprobados;
  no se ejecutó el asistente ni se modificó el escritorio del usuario.


- 2026-11-16 — Retirado del código el tema Omnia Night y su flujo de instalación/aplicación/restauración: applet de barra,
  paleta, Plasma Style, Aurorae, LookAndFeel, comando `omnia-theme`, pestañas/opciones de tema y guía. Se conservaron
  el wallpaper, el widget de biblioteca y el layout que los coloca en los escritorios. El diseño futuro partirá de la
  configuración que el usuario termine de preparar en Plasma; no se modificó la configuración activa de su PC.

- 2026-11-16 — Diagnóstico visual con la captura de Plasma. El panel blanco no era blur: `translucent/widgets/panel-background.svg`
  tenía el centro blanco opaco, por lo que teñía de crema tanto la barra superior como el dock. Además, la paleta de la variante
  Cream dejó Preferencias del sistema clara frente a la estantería oscura. Corregido: fondo translúcido real oscuro, esquema Night
  restaurado, islas ajustadas al contenido y glifos sustituidos por iconos del sistema. `.run` reconstruido e incluye los cambios;
  todavía no se ha instalado ni validado en la sesión real de Plasma.

- 2026-11-16 — Variante visual Omnia Cream. Se cambiaron barra e islas a marfil/crema translúcido con tinta marrón y
  acento salvia, además de panel, paleta global y decoración de ventana cálidos; se conserva la geometría y funcionalidad
  de las tres islas. El instalador `.run` se reconstruyó y el paquete contiene la variante Cream. Falta instalarla y
  validar visualmente en la sesión de Plasma.

- 2026-11-16 — Corrección del tema Omnia Night tras comprobar que la entrega anterior solo aplicaba una barra nativa
  estándar. Se agregó el applet `org.omnia.topbar`: cinta superior translúcida de 25 px y tres islas propias de 30 px
  (Omnia/escritorios, ventana activa, controles del sistema); los escritorios cambian desde la isla izquierda y los
  accesos de audio/red/Bluetooth abren sus módulos de configuración. El layout instala el applet en lugar de repartir
  widgets estándar y mantiene el dock de 64 px. El instalador universal y paquete Arch incorporan la fuente del applet.
  Se actualizó el tema de panel para dejar pasar más fondo y ofrecer máscara de blur. El instalador `.run` se reconstruye
  con esta corrección; todavía no se ha instalado ni aplicado en la sesión KDE del usuario.

- 2026-11-15 — Diagnóstico de entrada en wallpaper nativo: `focus: true` en `WallpaperItem` no basta. En esta sesión Plasma tiene el containment `org.kde.plasma.folder`; el wallpaper es solo la capa de dibujo y no recibe de forma fiable teclado/mouse (el mando sí llega por KWin → D-Bus → API). Solución de arquitectura: mover `OmniaShell` interactivo a un Plasmoid de escritorio (`PlasmoidItem`) full-screen, añadido/configurado con la API de scripting de Plasma, conservar el plugin Wallpaper solo como fondo/fallback y apagar `omnia-ui.service` para evitar dos clientes de mando. KDE documenta wallpaper y widget como roles diferentes y el scripting permite añadir widgets al desktop. No hay cambios de código en esta etapa.
- 2026-11-15 — Wallpaper nativo e interacción: el root `WallpaperItem` mantiene `focus: true`; KWin considera activa la estantería cuando Plasma/escritorio tiene el foco, aunque haya ventanas inactivas detrás, y sigue retirando el mando cuando una aplicación normal tiene el foco. Al quitarse `covered` (cierre/minimización de ventana a pantalla completa), la UI refresca la biblioteca inmediatamente para retirar «EN EJECUCIÓN»; el core ya detecta procesos cada 2 s. El paquete `.11` fue rechazado porque `WallpaperItem.activeFocusOnTab` no está disponible; se quitó y se construyó `.12`, que el usuario instaló. La estantería nativa carga y el mando funciona. Falta teclado/mouse: Plasma no da esos eventos de forma fiable al wallpaper bajo el containment folder-view. Se recomienda mover `OmniaShell` a un Plasmoid de escritorio interactivo full-screen, conservando el wallpaper plugin como fondo/fallback; hacerlo reversible desde `omnia-setup` y apagar `omnia-ui.service` para evitar dos clientes de mando.
- 2026-11-16 (4) — Salida de audio, Power y buscador con mando. Core: `audio_out.py` (`GET /audio/outputs`, `POST /audio/set`):
  lista los dispositivos de `pactl` (uno por sink y por puerto disponible) y cambia el predeterminado moviendo lo que suena; la
  petición solo puede elegir sinks/puertos listados. UI: menú «Salida de audio» (A elige, B cierra, «✓ ACTIVO»). El botón de
  apagado abre el Big Menú directamente en «Energía y sesión» (`BigMenu.startMode`). Buscador con mando: la lupa abre el
  teclado virtual (A escribe, B borra y con el campo vacío cierra, X mayús, Y espacio, Start = BUSCAR, que conserva el filtro).
  Tiempos y barra del reproductor centrados en el mismo eje (altura real de los números). Verificado con mando emulado y capturas
  (teclado virtual, 3 dispositivos reales de audio, energía). 262 pruebas OK.

- 2026-11-16 (3) — Teclado y mando no hacían nada. Causa: `list` era un `ListView` invisible SIN delegate (contador 0), así que
  `incrementCurrentIndex()`/`decrementCurrentIndex()` no movían nada aunque el core entregara los botones; ahora es un
  `QtObject` propio. Navegación por zonas como en el prototipo (`shelf` carrusel · `hero` ports y Jugar · `player` · `head`
  filtros y botones) con anillos de foco, Intro/A activa, Esc/B vuelve, y un clic devuelve el foco del teclado. Reproductor:
  botones alineados al mismo eje, al terminar o cambiar la reproducción se mantiene 2 s y se desvanece en 2 s (conserva la
  última pista), sombra radial difuminada. Menú contextual con los iconos Kirigami del prototipo. Avisos (`Api.notify`):
  3 s visibles + fundido de 2 s, sobre una cápsula oscura. Pastillas: icono y texto centrados por altura de mayúscula
  medida (`TextMetrics`). Cursor de mano en todos los botones con acción. Verificado con el core aislado y la UI: mando
  (r r r → u u), menú contextual, teclado con `ydotool`, aviso al actualizar. Pendiente: teclado virtual del mando y salida
  de audio.

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

- 2026-11-15 — Tras actualizar `main` a `ffd8765`, corregida la gestión de errores de `pactl`: Omnia ahora rechaza el cambio
  de salida cuando el comando termina con código distinto de cero y expone el error recibido. Añadida prueba para ese caso;
  suite completa: 263 pruebas OK. Paquetes Arch `0.1.0-6` reconstruidos en `/tmp/omnia-pkg-audiofix/`; no instalados,
  commit ni push.

- 2026-11-15 — En el selector de audio, el dispositivo actual ahora se reconoce por un check y un fondo/borde con el acento
  activo; se eliminó la etiqueta «ACTIVO». Los botones de búsqueda, energía, refresco y audio usan el mismo acento cuando
  su acción está abierta o en curso. La UI completa carga con Qt Quick en modo offscreen; `qmllint` no está instalado.
  Paquetes `0.1.0-6` reconstruidos en `/tmp/omnia-pkg-audio-selector/`, aún sin instalar.

- 2026-11-15 — Iniciada la transición a wallpaper nativo Plasma 6. Añadido el KPackage `Plasma/Wallpaper`
  `org.omnia.launcher`, que monta `OmniaShell` sobre `WallpaperItem` y conserva Big Menu como ventana fullscreen superior.
  Añadido módulo QML C++ `org.omnia.session` para leer el token por `QStandardPaths::RuntimeLocation` sin habilitar lectura
  de archivos QML global en plasmashell; `Api.qml` acepta el token suministrado por el plugin. Módulo compilado, ruta de
  imports corregida, QML del wallpaper validado sin advertencias y KPackage reconocido por `kpackagetool6` en un
  packageroot temporal. Paquetes `0.1.0-8` construidos en `/tmp/omnia-pkg-native-wallpaper-final/`. Aún no instalados ni
  seleccionados: falta probar interacción/foco en una sesión Plasma real y adaptar el servicio layer-shell para que no
  duplique la estantería al activar el wallpaper.

- 2026-11-15 — Diagnóstico de la pantalla negra al seleccionar el wallpaper: el módulo QML se instaló como
  `omnia_sessionplugin.so`, pero Qt requiere el prefijo `lib`. Corregido el nombre de salida, verificada la importación del
  singleton `SessionToken` y cargado el QML completo del wallpaper por 6 s sin errores. Paquetes `0.1.0-9` listos en
  `/tmp/omnia-pkg-native-wallpaper-fix/`; falta instalarlos y comprobar el render en Plasma.

- 2026-11-15 — Instalado `0.1.0-9`; importación del token probada con el Qt del sistema. Reiniciado
  `plasma-plasmashell.service` para vaciar el caché de imports fallidos. En este momento Plasma volvió a
  `org.kde.image` (`north.png`) y `omnia-ui.service` está activo; falta volver a seleccionar Omnia para verificarlo tras
  la recarga. La interfaz anterior sigue disponible como recuperación.

- 2026-11-15 — Iniciada la arquitectura nativa de Plasma 6: `org.omnia.launcher` queda como wallpaper pasivo, que consulta
  al núcleo el arte/color del juego seleccionado; `org.omnia.desktop` es el widget interactivo que monta `OmniaShell` y
  persiste la selección en `state.json` mediante `/selection` y `/selection/set`. Se ocultó el fondo interno de la shell
  cuando se usa el wallpaper para evitar taparlo. El primer arranque ahora habilita solo `omnia.service`; el instalador
  detiene `omnia-ui.service` para no duplicar el escritorio/control del mando.

- 2026-11-15 — Añadido `packaging/universal/build-run.sh` para producir un instalador autoextraíble `.run` con instalación
  por usuario. Comprueba Plasma 6, systemd de usuario y Python ≥3.11; reconoce Arch/CachyOS, Debian/Ubuntu, Fedora y
  openSUSE para dependencias CMake/Qt 6, y compila localmente el proveedor del token en vez de distribuir un binario Qt
  ligado a una sola distro. Añade wallpaper, widget, núcleo y configuración de KWin; muestra los pasos finales de
  selección del fondo y expansión del widget. No se anuncia soporte para Plasma 5 ni distros sin gestor reconocido.
  Cambio aún sin instalación real ni validación en una sesión Plasma; sin commit ni push.

- 2026-11-15 — Corregida la ruta de instalación de QML compartido para que coincida con los imports relativos de los
  KPackages en `~/.local/share`: ahora se instala como `~/.local/share/omnia/ui/qml`. La versión anterior lo dejaba un
  nivel arriba, provocando el error “no such directory” al cargar Omnia Desktop y la pantalla negra del wallpaper.

- 2026-11-15 — Diagnóstico de fondo sin imagen/selección que no se actualiza: el servicio del instalador universal
  todavía ejecutaba `/usr/bin/omnia-core`, por lo que podía permanecer activo con una versión anterior y no conocer las
  rutas de sincronización. Ahora el unit apunta al wrapper instalado en `~/.local/bin` y el instalador reinicia el núcleo
  tras actualizarlo. La shell reenvía la selección actual al reconectar con el API, además de sincronizar cada cambio de
  juego. Pendiente confirmar en la sesión Plasma del usuario.

- 2026-11-15 — Acelerada la detección de cierre: el núcleo ahora revisa juegos cada 350 ms (antes 2 s), cierra la sesión
  tras dos muestras ausentes y publica una revisión de estado al cambiar el conjunto de juegos o el historial de sesión.
  La petición larga del widget escucha esa revisión y refresca la biblioteca al instante, incluso con el escritorio cubierto;
  así el fondo/estado vuelve al juego seleccionado en menos de un segundo en condiciones normales. Paquete Arch sube a
  `pkgrel=14`. Sin pruebas ejecutadas, por instrucción del flujo; pendiente validar en una sesión real.

- 2026-11-16 — Medido el API local desde la sesión: `GET /selection` respondió 200 en 9 ms y entregó fondo para Mario
  Kart 64; el acceso al bus systemd del usuario está aislado en esta sesión, así que no pude confirmar qué unit está activo.
  El retraso principal estaba en el wallpaper: consultaba cada 1,2 s. Reemplazado por espera larga autenticada en `/selection`
  que se despierta al cambiar juego o arte seleccionado; el trabajador de SteamGridDB también notifica cuando descarga el
  fondo que faltaba. El wallpaper ya no hace sondeo periódico. Pendiente reconstruir/instalar en Plasma y medir el cambio
  de imagen real.

- 2026-11-16 — Evolución a pack nativo de widgets Plasma: se añadieron `org.omnia.header`, `hero`, `activity`, `system`
  y `carousel`, que recortan la composición compartida de `OmniaShell` según zonas del prototipo. El carrusel es el único
  propietario del mando y del sondeo de audio; los demás widgets siguen la selección, filtro y búsqueda mediante el API
  autenticado. El wallpaper conserva solo fondo/arte dinámico. El instalador universal aplica un layout coordinado por
  escritorio, escala y centra las posiciones de referencia 1920×1080 según la pantalla, quita el antiguo widget fullscreen,
  y deja huecos para el menú contextual Plasma. También instala `omnia-layout` para repetir la distribución. El paquete
  Arch instala los cinco nuevos applets (`pkgrel=19`). Falta validar en una sesión Plasma real; todavía no instalar, commit
  ni push.

- 2026-11-16 — Al probar el pack, Plasma cargó el wallpaper pero mantuvo en su motor QML una versión anterior de
  `OmniaShell` sin `sectionMode`; por eso los applets fallaron al inicializar aunque el archivo actualizado sí contiene esa
  propiedad. El instalador universal ahora reinicia únicamente `plasma-plasmashell.service` tras copiar QML y applets (sin
  cerrar sesión), espera a que vuelva a registrarse y aplica después el layout. Falta reconstruir/instalar esta corrección
  y validar visualmente los widgets.

- 2026-11-16 — Como el error de `sectionMode` persistió tras reiniciar Plasma, se aisló el import de los cinco widgets en
  la ruta nueva `omnia/ui/plasma-widgets/qml`, mientras el wallpaper conserva `omnia/ui/qml`. El instalador universal y el
  paquete Arch instalan ambas rutas. Los applets reciben así una URL QML distinta de la que podía estar resolviendo a la
  shell antigua. Pendiente reconstruir e instalar para validar la carga.

- 2026-11-16 — El usuario informó que Plasma aparentemente no reiniciaba. Se eliminó la condición silenciosa
  `is-active`; el instalador ahora siempre solicita `systemctl --user restart plasma-plasmashell.service` y muestra un
  comando explícito si falla. La unidad existe en el sistema, pero el bus de usuario no es accesible desde este entorno
  de trabajo; no se ejecutó el reinicio aquí.

- 2026-11-16 — Confirmada la causa del error persistente: una instalación anterior dejó una copia plana antigua en
  `~/.local/share/omnia/ui/OmniaShell.qml` sin `sectionMode`; el instalador actual solo actualizaba `ui/qml/`, por lo que
  esa copia sobrevivía y Plasma la resolvía para los applets. Ahora se sincronizan también los QML en la ruta plana
  heredada, además de `ui/qml` y `ui/plasma-widgets/qml`. PKGBUILD actualizado a `pkgrel=17`.

- 2026-11-16 — El layout automático falló porque el motor `evaluateScript` de Plasma no expone el objeto QML `Qt`; el error
  era `ReferenceError: Qt is not defined` al asignar `widget.geometry`. El script ahora elimina/recrea solo los applets Omnia
  con las coordenadas pasadas directamente a `desktop.addWidget(type,x,y,w,h)`, API que usa también el layout de Plasma
  instalado localmente. Esto vuelve idempotente el despliegue y corrige ejecuciones parciales anteriores.
  Se copió la versión corregida al usuario y se ejecutó contra la sesión real: `Omnia: layout aplicado a 1 escritorio(s)`.
  El mensaje final del instalador también se condiciona al resultado real, para no afirmar que el layout se aplicó cuando
  falla.

- 2026-11-16 — La shell funciona en una carga QML aislada, pero Plasma sigue reportando que la propiedad pública
  `sectionMode` no existe al importar el tipo compartido desde fuera del KPackage. Para eliminar esa resolución externa,
  los cinco applets ahora usan `import "omnia"` y cada instalador incluye las QML compartidas dentro de
  `contents/ui/omnia/`. El paquete Arch también las incluye (`pkgrel=19`). Quedó pendiente aplicar esta nueva estructura
  en la sesión y confirmar el render.

- 2026-11-16 — Copiados los cinco applets autocontenidos a la instalación del usuario; reiniciado Plasma y reaplicado el
  layout. D-Bus respondió `Omnia: layout aplicado a 1 escritorio(s)`. Una carga QML del import local reportó
  `LOCAL PROBE section=header viewport=960`; no aparecieron nuevos errores `sectionMode` en el journal tras el reinicio.
  La herramienta de escritorio no expone la pantalla para confirmar el render visual.

- 2026-11-16 — Se revierte la distribución en cinco applets tras los errores de carga y la pérdida del menú de escritorio.
  Omnia vuelve a un único widget `org.omnia.desktop` de pantalla completa; el wallpaper conserva solo el fondo animado y
  el arte seleccionado. El clic derecho en el fondo del widget queda sin consumir y el applet no define acciones
  contextuales propias; Plasma recibe el evento para mostrar su menú contextual nativo. El menú contextual de Omnia queda
  solo en las tarjetas de juegos. `omnia-layout` elimina instancias viejas, aplica el applet único según el tamaño del
  display y conserva el wallpaper; la shell QML llena explícitamente la representación del applet. `PlasmoidItem` declara
  el ancho y alto de pantalla como tamaño mínimo dinámico (`Screen.width`/`height`). Plasma solo aplica el tamaño de
  `addWidget` cuando x o y son mayores que cero, así que el layout pasa x=0.01 para activar el tamaño completo sin desplazar
  perceptiblemente la interfaz. La prueba en Plasma produjo 0.01,0 y 1920×1080 para un display 1920×1080. No hace falta
  editar a mano la configuración ni reiniciar Plasma para aplicar el layout. El instalador universal deja de desplegar
  los cinco applets separados y retira sus paquetes locales tras aplicar correctamente el layout. El PKGBUILD vuelve a
  empaquetar solo el applet único (`pkgrel=24`). Se comprobó que x=y=0 dejaba el widget en 96×96 y que el setter de
  `geometry` no mueve el applet en la versión instalada. Una prueba temporal confirmó que
  `addWidget(applet, 0.01, 0, width, height)` crea el tamaño exacto. La llamada se aplicó al layout real y Plasma confirmó
  `0.01,0 con 1920x1080 en pantalla 1920x1080`; la configuración guardó `Applet-155:0.01,0,1920,1080,0;`. El widget temporal
  se retiró y el layout final permanece aplicado. Al reemplazar la instancia anterior aparecieron callbacks tardíos de esa
  instancia; se calificaron las propiedades con `api`/`shell`, se captura la shell antes de `Qt.callLater` y se valida el
  cuerpo de audio. Luego Plasma informó una sola instancia activa (`Applet-157`) con geometría `0.01,0 1920x1080`; no
  hubo mensajes QML nuevos en los 30 s recientes. Queda la comprobación visual de los dos tipos de menú.

- 2026-11-16 — Al cambiar rápidamente entre plataformas, el selector podía volver a una vista anterior: el sondeo largo
  `/selection` podía responder con el `filterKey` antiguo mientras la escritura debounced `/view/set` aún no se enviaba.
  `OmniaShell.qml` ahora mantiene una revisión local de filtro/búsqueda y descarta únicamente esos campos de una respuesta
  obsoleta; conserva el juego seleccionado recibido y sincroniza después la vista local con el core. La biblioteca actual
  tiene 10 juegos N64, 5 PC, 2 Switch y 2 Switch 2; los dos Switch son BOTW y TOTK, así que ver solo esos dos al elegir
  Switch es el contenido esperado. Se incrementó `pkgrel` a 25 para Arch. Pendiente: confirmar visualmente el cambio
  rápido de filtros en la sesión Plasma del usuario.
- 2026-11-16 — Caso específico del filtro «Todos»: al reconstruirse la lista, `currentIndex` podía apuntar por un
  instante a otra tarjeta; `onCurrentChanged` sincronizaba ese juego transitorio y podía competir con la restauración
  del filtro/selección. Al cambiar de sección, `OmniaShell.qml` ahora reinicia siempre el carrusel en el índice 0 de la
  sección resultante («Todos», Favoritos o plataforma), ignora cambios intermedios y sincroniza una sola vez el primer
  juego. Las respuestas `/selection` obsoletas tampoco pueden cambiar el ID elegido localmente. El instalador universal
  se regeneró; queda verificar visualmente los cambios repetidos hacia/desde «Todos» en la sesión Plasma.
- 2026-11-16 — Seguimiento del índice persistente: `/selection` podía iniciar su long-poll tras el cambio local, pero
  antes del debounce `/view/set`; por ello la revisión local no cambiaba durante la petición y la respuesta antigua podía
  restaurar el juego situado en el índice previo. La shell ahora mantiene `viewSyncPending` hasta recibir confirmación
  del core, considera obsoletas también las peticiones iniciadas durante ese intervalo y fija el índice 0
  sincrónicamente usando la lista calculada para el nuevo filtro. Además, el cambio de sección vacía temporalmente la
  selección anterior y no acepta IDs del long-poll hasta confirmar `/selection/set`; se invalida cualquier restauración
  diferida creada para la sección previa. `Api.setView` y `Api.selectGame` aceptan callback para confirmar escritura.
  Los callbacks diferidos capturan la referencia de la shell para sobrevivir a cambios de contexto QML. Instalador
  universal regenerado y QML aplicado en la sesión Plasma; pendiente confirmar visualmente con el usuario.

- 2026-11-16 — Instalador gráfico de Omnia Desktop Suite (Qt 6 Widgets/C++, empaquetado dentro de `omnia-kde.run`).
  Se abre con `launch-gui.sh`; conserva `--cli` y `--check`. Cinco pantallas: lectura obligatoria con aceptación,
  detección automática de Steam y múltiples carpetas externas, volumen del monitor, clave SteamGridDB opcional con
  validación HTTPS, y resumen/progreso. Instala por usuario; solo los gestores de paquetes se elevan con `pkexec` y el
  agente Polkit de KDE. Nunca recoge la contraseña. Qt se compila como usuario. La clave viaja por stdin, se mantiene
  en un temporal 0600 mientras corre el instalador y se guarda por reemplazo atómico con 0600; no pasa por argumentos.
  Dejarla vacía conserva la existente. Las carpetas se guardan como accesos para el explorador de Omnia; no se inventan
  comandos para ports desconocidos: se agregan después con ejecutable/emulador. El volumen se guarda por UUID; el
  monitor resuelve su etiqueta real y evita mostrar otro disco si el elegido se desconecta. Hay copia de configuración
  de Plasma antes de aplicar el layout. Instalación no transaccional: puede dejar dependencias/archivos si falla.
  Se retiraron `BigMenu.qml`, su ventana, el botón y las rutas del mando; Meta vuelve a Plasma en el setup y ya no se
  registra OmniaMenu. D-Bus ToggleMenu queda inerte por compatibilidad. `pkgrel=26`. El tema completo aún no se instala.
  Comprobaciones: compilación del asistente, apertura offscreen y navegación por sus cinco pantallas con bloqueo por
  consentimiento, 20 pruebas de setup (incluida migración desde Big Menu), 8 del monitor, 25 de juegos manuales y 3 del
  almacenamiento de ajustes/clave. No se ejecutó una instalación real ni una autorización Polkit con contraseña.
  El `.run` y el AppImage son gráficos; el AppImage se construye para la máquina actual y el lanzador
  intenta recompilar desde fuentes si el binario no arranca en otra distro. Compatibilidad entre distros aún pendiente.

- 2026-11-16 — Falso negativo al validar SteamGridDB: comprobación real de la clave guardada dio HTTP 403 con
  el User-Agent predeterminado de urllib, y HTTP 200/success=true en la misma consulta al usar User-Agent `omnia`.
  La búsqueda de arte también respondió HTTP 200/success=true. El instalador ahora usa la misma identidad HTTP que
  el cliente de arte, valida el campo success y distingue errores 401, 403, 429, conexión y timeout sin exponer la clave.
  Añadidas tres pruebas de regresión; instalador universal regenerado. La comprobación no cambia la clave guardada.

- 2026-11-16 — Rutas retiradas y ajustes generales persistentes. `library_paths.py` mantiene exclusiones reversibles:
  quitar una raíz de `external_roots` la añade a `excluded_external_roots`; la API filtra sus ports manuales aunque
  continúen instalados. No se borran biblioteca, arte, historial, partidas ni ejecutables, y reañadir la raíz recupera
  las entradas. La regla más específica manda en rutas anidadas; Steam/Heroic/Lutris conservan su gestión automática.
  La API impide iniciar por ID un port excluido y retira su selección del wallpaper. Configuración se lee al generar
  el catálogo, de modo que no depende de regenerar la biblioteca para mantener las exclusiones.
  El ejecutable Qt incluye modo `--settings`: pestañas Bibliotecas, Monitor, SteamGridDB y Acerca de; permite agregar/
  quitar carpetas, elegir volumen, validar/reemplazar/eliminar clave. Guardar usa stdin y reinicia solo omnia.service,
  sin Polkit ni reiniciar Plasma. Un disco ya configurado puede conservarse desconectado al modificar otros ajustes.
  Se instala `omnia-settings`, entrada «Omnia — Ajustes generales» en Plasma y botón de engranaje en la cabecera de Omnia.
  El instalador y ajustes llevan el logo Onda aprobado como propuesta de marca, copiado a assets/branding/omnia-logo.png.
  Instalador universal y PKGBUILD incorporan binario, backend, logo y acceso; pkgrel=27 y arquitectura explícita por el
  código Qt nativo. Se corrigieron empaquetadores para omitir archivos versionados eliminados (BigMenu.qml).
  Verificación: 8 pruebas del backend y 6 de rutas/catálogo, incluida exclusión tras recarga y recuperación sin borrar
  archivos; compilación Qt, navegación offscreen del asistente y apertura offscreen de los cuatro tabs de ajustes,
  inspección visual de capturas con logo, sintaxis QML/shell y diff sin errores. No se aplicaron cambios a las rutas reales
  del usuario ni se ejecutó la instalación real; disponibles al instalar el .run actualizado.

- 2026-11-16 — Revisión de instalaciones existentes. El backend identifica Omnia y reconstruye `linked_roots` desde
  configuración y checks/cwd de ports/ROMs manuales antiguos, respetando raíces excluidas. El instalador presenta modo
  Actualizar y los ajustes muestran las mismas rutas recuperadas; quitar una ruta inferida también la excluye al guardar.
  `route_inspection.py` hace análisis de lectura con límite de 25 000 archivos, profundidad 8 y presupuesto de 3 segundos;
  cuenta IDs vinculados por ruta y candidatos ROM/ejecutable (ejecutables agrupados por carpeta). No ejecuta archivos,
  no sigue symlinks, informa rutas inaccesibles y resultados parciales. Los candidatos son orientativos y no se confunden
  con juegos vinculados ni se importan automáticamente. Steam mantiene su detección separada.
  Los widgets Qt compartidos `RouteList` y `KeyPanel` se usan en instalador y ajustes. El recuento se realiza en procesos
  asíncronos al cargar/agregar rutas. La clave guardada se valida automáticamente sin devolver su valor a la GUI; tras
  fallo se pide otra o aplazar explícitamente. Una clave nueva requiere validación o aplazamiento; aplazar conserva la
  existente y no guarda el texto nuevo sin validar. Se cancelan procesos al cerrar para evitar callbacks sobre objetos
  destruidos (detectado y corregido durante smoke tests). Se conservan rutas previamente vinculadas desconectadas.
  Comprobaciones: 12 pruebas de backend, 6 del catálogo, compilación Qt y apertura/cierre offscreen de instalador/ajustes;
  la lectura real encontró 5 rutas vinculadas (incluidas dos inferidas) y la prueba de clave guardada devolvió acceso
  confirmado por SteamGridDB. No se cambiaron rutas ni claves del usuario. `pkgrel=28`; instalador universal regenerado.

- 2026-11-16 — Revisión explícita de candidatos antes de agregarlos. `inspect_route` devuelve hasta 1000 fichas con
  nombre, tipo, ROM o grupo de ejecutables (hasta 40), y marca las ya vinculadas. Tanto instalador como ajustes ofrecen
  «Revisar candidatos…» sobre la ruta seleccionada; el diálogo comienza sin marcas, permite editar nombres, elegir
  ejecutable en carpetas ambiguas y especificar Gopher64 u otro ejecutable de emulador para ROMs. Otro emulador recibe
  la ROM como primer argumento (se informa al usuario); Windows usa el soporte umu-run existente y falla claramente
  si falta. Confirmar el diálogo deja selección pendiente; solo Instalar/Aplicar la guarda. Las vinculadas no se duplican.
  `candidate_import.py` valida y prepara todas las entradas elegidas en biblioteca temporal antes de modificar ajustes;
  verifica existencia, permisos, raíz y nombre, deduplica por archivo, y no ejecuta los juegos. Una selección inválida
  no modifica la biblioteca real. Se detiene el núcleo durante escritura de biblioteca y se inicia después para evitar
  que un refresco del servicio pise los nuevos juegos. En ajustes, guardar actualiza recuentos y limpia la selección.
  Comprobación: 16 pruebas del backend (incluidas selección vacía, archivos fuera de raíz, deduplicación y fallo de lote
  sin cambios) y 6 del catálogo, compilación y smoke tests de revisión/instalador/ajustes con inspección visual del
  diálogo. Ningún juego real importado durante el desarrollo. `pkgrel=29`; .run actualizado.

- 2026-11-16 — Fallo al abrir ajustes: el núcleo estaba inactivo desde las 03:15:02. La ventana de ajustes se lanzaba
  con Popen/start_new_session, que no la separa del cgroup de omnia.service; al guardar y detener el núcleo, systemd
  podía matar también la ventana y su backend antes de volver a iniciar el servicio. `/settings/open` ahora arranca una
  unidad transitoria independiente con systemd-run --user --collect y Type=exec, espera confirmación de arranque y
  comunica fallos reales. Se conserva el entorno gráfico necesario mediante variables explícitas. No cambia rutas ni
  claves para esta reparación; se recupera el núcleo y se genera instalador actualizado.

- 2026-11-16 — Distribuciones del asistente de Omnia Desktop Suite. `packaging/distros/build.py` genera .deb all,
  .pkg.tar.zst any, RPM noarch separados para Fedora/openSUSE, .run gráfico basado solo en fuentes y .tar.gz fuente.
  Son paquetes del asistente, no conversiones de binarios de CachyOS: contienen fuentes, lanzador e icono en /usr,
  y el usuario abre el menú para compilar GUI/puente Qt contra su distro y aplicar Omnia en ~/.local con consentimiento.
  No hay postinst/scriptlets que reinicien escritorios como root. Eliminar el paquete no elimina el despliegue del usuario.
  Dependencias por familia en profiles.json; mínimo Plasma 6, Qt 6.6 y Python 3.11 con systemd de usuario. Se corrigieron
  nombres de Qt5Compat/Kirigami/sensores para openSUSE y módulos QML Debian; se incluyeron neon/tuxedo en el mapa apt.
  El lanzador comprueba sesión KDE6 y rechaza root/OSTree antes de compilar. Bazzite/Kinoite no están cubiertos todavía.
  build-run.sh admite --source-only y omite salidas de distros para evitar empaquetado recursivo. La salida tiene
  checksums SHA256 y manifest.json. Se mantienen aparte los paquetes Arch existentes del núcleo y la UI.
  Para generar RPM se descargaron herramientas oficiales de Arch y sus bibliotecas a /tmp, sin instalarlas globalmente;
  rpmbuild usa base/temporales propios y formato RPM4/gzip. Verificación: metadata/payload de formatos, reconocimiento
  por pacman/ar/rpm, desktop-file-validate y tres pruebas del builder que comprueban ausencia de ELF del host y scripts
  de cambios de usuario. No se instalaron los paquetes nuevos en el OS ni se validaron en VMs Debian/Fedora/openSUSE.
  Uso, comandos y límites en docs/INSTALADORES.md. Los artefactos quedan en packaging/distros/out (ignorado por git).

- 2026-11-16 — README público de Omnia Desktop Suite actualizado con logo, versión 0.1.0/revisión 1, tabla por distro
  y enlaces exactos a ocho assets previstos de GitHub Releases v0.1.0 (seis artefactos, SHA256SUMS y manifest.json).
  Se indica expresamente que la release/descargas todavía no están publicadas. Incluye comandos nativos y .run,
  requisitos, arquitectura de paquetes basados en fuentes, estado experimental/pruebas pendientes, exclusión de
  Plasma5/OSTree, flujo de consentimiento y ajustes. Corrige estructura antigua y no anuncia Hydra ni tema ya disponible.
  Se cotejaron nombres/versiones con manifest local y pyproject; no se subieron binarios ni se publicó el repositorio.

- 2026-11-16 — Corrección del usuario sobre la identidad del proyecto: Omnia Desktop Suite es un desarrollo desde
  cero. Estantería fue un prototipo de referencia; Omnia no se presenta como reestructuración, reescritura ni migración.
  Se corrigió la sección Desarrollo del README y se retiraron de ella los enlaces a migración y contexto histórico.

- 2026-11-16 — Tema base Omnia Night 0.1.0 creado y aplicado en la sesión del usuario. Paquete LookAndFeel nativo
  org.omnia.desktop.theme, paleta OmniaNight (derivada de Breeze Dark con atribución), símbolo SVG y layout por pantalla:
  top bar 36 px (dashboard, appmenu, reloj, tray), dock flotante 64 px FitContent/dodgewindows con icontasks. El Big Menú
  de la base es Application Dashboard de Plasma, separado del launcher; conserva búsqueda, categorías y favoritos.
  No se ha creado aún un menú propio ni validado navegación por mando de ese dashboard. Los escritorios no se eliminan.
  `omnia-theme` instala/aplica/restaura; respalda config, defaults, paneles y atajos antes de cambios. La copia activa quedó
  en ~/.config/omnia/theme-backups/1794818630125733155. Dos pruebas de backup/restore en temporales pasaron. La API
  real confirmó dos paneles (IDs 164/184), dimensiones, tipos de widgets y atajo Meta del dashboard. Apertura real del
  menú y capturas revisadas. No se aplicó la restauración real para dejar el tema activo; multimonitor pendiente.
  Instalador: casilla opt-in para aplicar la base; ajustes: pestaña Tema y layout con aplicar/restaurar. Se desplegaron
  gestor y ajustes actualizados en el usuario. Los paquetes incluyen recursos; pkgrel=30. Guía docs/TEMA.md y README
  actualizados. Se preservó la biblioteca; no se importaron juegos ni se tocaron claves para este trabajo.

- 2026-11-16 — Propuestas visuales del tema inspiradas en Plasma Drawer (p-connor/plasma-drawer). Se revisaron README
  y captura de referencia: búsqueda superior, cuadrícula amplia, carpetas y acciones de sesión. Tres conceptos propios
  de Omnia: Noche (centrado), Enfoque (favoritos laterales) y Colecciones (categorías). Cada propuesta incluye barra
  superior, menú y dock con paleta oscura/menta, búsqueda/carpetas y paneles simulados de audio/red/sesión. Son prototipos
  de revisión en la conversación: no se instaló Plasma Drawer ni se reemplazó el tema activo con estas propuestas.

- 2026-11-16 — Prototipos de top bar para Omnia Noche, guiados por módulos de DUX y Hyprland. Se ajustaron a dos
  diseños (Noche y DUX): la barra mide 30 px cerrada y comparte exactamente el ancho del conjunto de ventanas. El
  relieve se aplica a tres grupos completos: aplicación activa a la izquierda, espacios de trabajo al centro y sistema
  a la derecha; radios reducidos y acabado gamer sobrio. Cada panel desplegable queda limitado al ancho de su propio
  grupo y continúa esa superficie. Los grupos son controles HTML nativos; el menú de Firefox aparece al pasar sobre su
  nombre. Ventanas sin cabecera y separación uniforme de 20 px en márgenes superior/laterales/inferior, barra a
  ventanas y entre ventanas. Exploración visual solamente; no cambia Plasma.

- 2026-11-16 — Nueva composición de la barra a partir de las referencias Rice-Linux-nux-nux e Impasto: Agrupada,
  Extremos y Una isla, todas con el fondo Noche de Omnia. El grupo Omnia/escritorios permanece a la izquierda. El
  nombre de la app se sustituye por sus iconos de menú en el mismo espacio al pasar el puntero; no despliega otro
  panel. Solo Escritorios y Sistema expanden, cada panel bajo su sección y con el ancho de esta. Las cápsulas se
  limitan a sus módulos; la variante Una isla mide lo que ocupa su contenido. Son prototipos, no cambian la
  configuración aplicada de Plasma.

- 2026-11-16 — Ajuste de top bar solicitado a partir de una nueva referencia: una franja continua de 25 px conecta
  visualmente las islas y queda alineada en `top: 0`; las superficies de cada isla miden 30 px, nacen en el mismo
  borde y sobresalen 5 px por debajo de la franja. Las tres composiciones conservan sus grupos y expansiones locales.
  El mockup mantiene Omnia a la izquierda y el menú de la app sustituye su nombre en el mismo espacio. Prototipo
  visual solamente; no se aplicó a Plasma.

- 2026-11-16 — Implementación inicial de Omnia Night 0.2.0 para Plasma 6: barra nativa de 30 px organizada con
  launcher Omnia y pager a la izquierda, menú global centrado, reloj y bandeja a la derecha; dock flotante de tareas
  de 64 px. Se añadió Plasma Style con paneles/popups translúcidos y contraste/blur, además de decoración Aurorae
  Omnia Glass con máscara para blur y botones propios. El gestor guarda/restaura kwinrc y plasmarc y reconfigura KWin.
  Se incluyeron los recursos en el empaquetado Arch y universal. La transparencia interior depende de cada aplicación;
  esta implementación todavía requiere validación visual en una sesión Plasma real y no se ha aplicado en vivo.

- 2026-11-16 — Cambio de dirección visual: se retiró NextKDE (paquetes, servicios y checkout local) y se conserva
  Caelestia como shell deseado; el asistente
  de Caelestia se canceló al solicitar privilegios, por lo que falta completar su instalación. Panel Colorizer 8.1.0
  se compiló e instaló desde AUR. Se creó un panel inferior centrado con tareas en iconos y Panel Colorizer; se aplicó
  su preset Dock (blur activo, radio 15 px) y el tono #26374D. La sesión systemd de Plasma y Quickshell no aparecen
  activas, así que la apariencia debe comprobarse al iniciar Plasma. La
  configuración de Plasma mantiene `org.omnia.desktop` y `org.omnia.launcher` como escritorio
  y wallpaper. Se añadió `assets/branding/omnia-menu.svg`, un icono de Omnia con forma de portal/menú, y se asignó a la
  cabecera de Omnia y al ajuste `general.logo` de Caelestia para que el botón abra su launcher. Se añadió una capa
  gris azulada translúcida `#4835465E` sobre el arte del juego en el wallpaper y en la vista integrada, y se incorporó
  el icono SVG al empaquetado Arch, universal y de distros. Panel Colorizer se identificó como applet para paneles
  Plasma nativos; falta instalarlo y preparar un panel inferior independiente de la top bar Quickshell de Caelestia.

- 2026-11-16 — Se encontró la capa que aún bloqueaba la interacción: el fondo interactivo de Quickshell de Caelestia capturaba clic derecho para abrir su propio menú contextual. Se activó `background.disableQuickshellDesktop` en `~/.config/caelestia/shell.json` y se reinició Caelestia; su código aplica una máscara vacía para dejar pasar la entrada a Plasma/Omnia y desactiva el menú/captura de eventos del escritorio, sin apagar topbar ni dock. Plasma confirma que Omnia sigue siendo el único widget de 1920×1080 y mantiene el wallpaper `org.omnia.launcher`; el perfil oculta los iconos con una carpeta vacía sin borrar los archivos de `~/Escritorio`.

- 2026-11-16 — Historial: se añadió e instaló un prototipo de dock independiente de Omnia. Se retiró después a petición del usuario; véase la entrada de retirada al final del contexto.

- 2026-11-16 — Regresión del carrusel: al recibir una vista/plataforma remota, `followSelection()` restauraba el ID seleccionado globalmente aunque correspondiera a un índice posterior de la nueva vista. Ahora identifica el cambio de `filterKey`, suspende la restauración por ID y fija la selección al primer juego visible (índice 0), tanto en la transición local como en la remota; el controlador publica ese primer ID para mantener sincronizado el wallpaper. Se actualizó la QML activa de usuario y se reinició plasmashell. Falta que el usuario confirme navegación visual entre plataformas.
- 2026-11-16 — Refuerzo de selección por plataforma: el servicio guardaba `selected_game` sin indicar a qué `filter_key` pertenecía, por lo que un sondeo posterior podía volver a introducir el ID de una plataforma anterior. El estado ahora incluye `selected_filter_key`; `/selection` descarta IDs guardados para otra vista, y `/selection/set` persiste el juego junto con su filtro. `Api.selectGame` y todos sus puntos de llamada envían el filtro vigente. Se aplicó a las copias activas de usuario de QML y núcleo y se reiniciaron plasmashell y el servicio; queda confirmar que los cambios de plataforma mantienen el índice 0.
- 2026-11-16 — Causa restante del salto al navegar: `chooseFilter()` consultaba `visibleGames[0]` en el mismo ciclo en que cambiaba `filterKey`, antes de que QML recalculara la lista. Al venir de N64, podía volver a guardar el juego N64 como primer elemento de «Todos». El reinicio y la publicación del primer ID ahora esperan dos ciclos de QML; una revisión de transición impide que un cambio rápido posterior aplique el filtro viejo. `/view/set` también limpia una selección heredada de otra plataforma, y conserva una selección nueva si ya llegó para el filtro destino. Cambios aplicados al núcleo y QML activos; ambos servicios recargados. Falta confirmar visualmente el recorrido N64 → Todos.
- 2026-11-16 — Ajuste de sincronización para el índice: el reinicio se enlazó también a `onVisibleGamesChanged`, que es el momento en que QML ya terminó de recalcular la colección para el nuevo filtro. `completeFilterTransition()` valida la revisión de navegación, fija `currentIndex=0`, y solo entonces publica el ID de la primera tarjeta; el doble `Qt.callLater` queda como respaldo si la colección no emite cambio. Así no se toma el primer elemento de la lista N64 antigua al pasar a «Todos».
- 2026-11-16 — Retiro del dock Omnia independiente solicitado por el usuario. Se elimina su plasmoide `org.omnia.dock`, las instrucciones que creaban un panel inferior y las referencias de empaquetado universal y Arch. Se regeneran `.run`, `.deb`, Arch y fuentes; se verificó que el `.run` no contiene el applet ni lógica de creación del panel. Se retiraron los RPM antiguos del directorio de salida porque no había `rpmbuild` disponible para regenerarlos. La topología de escritorio conserva únicamente el wallpaper y el widget de Omnia.
- 2026-11-16 — Se activa en el wallpaper animado un desenfoque moderado (`blur: 10`) y se oscurece ligeramente la capa glass gris azulada (`#5235465E`) sobre el arte, manteniendo el paneo y los fundidos cruzados. Se aplica al paquete y a la copia instalada del usuario; plasmashell y omnia.service siguen activos tras recargar. Se regeneran los instaladores universales y nativos disponibles.
- 2026-11-16 — Ajuste visual solicitado: el wallpaper animado sube a `blur: 15` y la capa gris azulada se oscurece y refuerza a `#70303B4A`. La imagen conserva el paneo y el fundido cruzado.
- 2026-11-16 — Se retira el blur y la desaturación del wallpaper, dejando solo la cortina oscura gris azulada (`#80303B4A`). SteamGridDB ordena automáticamente los fondos por resolución; si hay varias imágenes ya descargadas, Omnia selecciona la de mayor área salvo que el usuario haya elegido/ciclado arte manualmente. `Backdrop` deja de limitar las imágenes a 1080 px y las carga a su resolución nativa; el escenario conserva `height: parent.height`, equivalente al 100 % de la altura visible, con paneo horizontal.
- 2026-11-16 — Se baja 20 px el grupo derecho del reproductor y el monitor del sistema: reproductor, broche decorativo y HUD conservan su separación relativa y se desplazan juntos.
- 2026-11-17 — El instalador AppImage rev16 detecta Omnia instalado y abre un flujo corto de actualización. Valida SteamGridDB y conserva biblioteca/ajustes; reemplaza los archivos de Omnia sin repetir dependencias, primera configuración, selección de discos ni importación. Si no hay instalación, mantiene el asistente completo.
- 2026-11-17 — Se integra MangoHud como superposición de métricas: el instalador agrega la dependencia, crea una configuración privada de Omnia a partir de `docs/MangoHud.conf` sin reemplazar los ajustes globales, y el núcleo lo antepone a juegos lanzados directamente desde la biblioteca. Ajustes permite desactivarlo; Steam/Lutris/Heroic requieren el prefijo en su propio cliente porque ya abierto no hereda el entorno de Omnia.
- 2026-11-17 — MangoHud ahora genera `cpu_text` y la lista `gpu_text` con los modelos detectados en `/proc/cpuinfo` y `lspci`; las instalaciones previas reciben estos nombres si aún no tenían etiquetas personalizadas. Se añade `pciutils` para disponer de `lspci`.
- 2026-11-21 — Inicio de la conversión de Omnia en aplicación independiente. Se creó `docs/ARQUITECTURA-INDEPENDIENTE.md` y una rama de trabajo que conserva los cambios locales previos. El servicio local incorpora lecturas autenticadas del catálogo público de Omnia Backend (juegos, detalle y plataformas), con timeout, límite de respuesta y caché offline; Big Mode añade Inicio con destacado, novedades, actividad local reciente, búsqueda y ficha del catálogo. Se añadió un centro de control de escritorio con Inicio, Biblioteca, Explorar, Instalaciones y Ajustes; Big Mode puede abrirse desde ahí compartiendo el servicio local. El paquete Arch `omnia-app` y una entrada XDG ya lo exponen como aplicación. Los ports instalados en RecompLauncher se migrarán una sola vez a la biblioteca local, usando su `AppRun` directamente; se retiró el detector recurrente y el worker de arte de esa aplicación. No se movieron archivos ni se publicó/desplegó el backend. Pendiente: completar gestión de carpetas/instalaciones, escaneo/reconocimiento de ROMs, manifiestos verificables, quitar la clave personal de SteamGridDB, localización completa y empaquetado independiente de Plasma.
- 2026-11-21 — Avance de la app independiente: gestor con Biblioteca/Explorar/Instalaciones/Ajustes, importación con detección de ROMs para 13 familias de consola, selección de emulador compatible y confirmación manual de formatos ambiguos; contratos de instalación verificada conectados al backend y al gestor local. Inicio de Big Mode muestra catálogo, destacados y hasta tres juegos locales recientes. Traducciones QML al inglés: 439/439 compiladas. La integración del panel illogical-impulse ya no solicita ni guarda claves personales de SteamGridDB; consume artwork publicado por omnia-backend. Chequeos estáticos de Python, Bash, traducciones QML y `git diff --check` correctos. Aún no se probaron suites automatizadas ni se desplegaron rutas/migración del backend; tampoco se publicó ningún paquete.
- 2026-11-21 — La pantalla Inicio de Big Mode distingue carga, catálogo vacío y estado sin conexión. El gestor y Big Mode comparten ahora el mismo objeto `Api`; la instancia local de Big Mode no inicia sondeos si el cliente fue inyectado, y el gestor activa/desactiva los controles de mando al abrir/cerrar Big Mode. El gestor ya no lanza varias cargas al iniciar ni sondea el sistema por una segunda vía. La app Arch se reconstruyó en `/tmp/omnia-pkg-single-startup/`; se verificó dentro del paquete la configuración de sondeos y el cliente compartido. Se amplió la localización inglesa de errores del servicio y se localizó la entrada XDG de Omnia. No se instalaron paquetes ni se validó el comportamiento en una sesión gráfica.
- 2026-11-21 — La caché offline del catálogo conserva los datos aunque superen 12 horas, pero incluye el tiempo de caché y un indicador de antigüedad; Inicio de Big Mode avisa cuando el catálogo guardado está desactualizado. Traducciones QML al inglés: 439/439 fuentes compiladas en catálogo.
- 2026-11-22 — Se aplicaron en producción de Omnia Backend las migraciones D1 0002/0003/0004 y se desplegaron las rutas de paquetes instalables e identificadores ROM (Worker `486f344b-a835-4895-b82e-bfe79e4e0652`). Health, catálogo y plataformas respondieron correctamente. Con aprobación explícita se vinculó The Legend of Zelda: Ocarina of Time con N64 y se publicó el ID de cabecera `CZLE`; el endpoint ROM ya entrega esa ficha y su región. No se publicaron los otros IDs de la seed ni manifiestos de descarga. Se actualizó la documentación de ambos repositorios; los cambios locales siguen sin commit ni push. El catálogo productivo sigue pequeño, así que el reconocimiento automático solo cubrirá juegos para los que se publiquen IDs curados.
- 2026-11-22 — Omnia ahora ofrece una entrada XDG **Omnia Big Mode** además del gestor, para abrir Big Mode directamente como ventana completa sin necesitar el panel. Se reconstruyeron los paquetes Arch del árbol actual en `~/Descargas/Omnia/0.2.1-arch-r5`; se inspeccionó el paquete y contiene ambos lanzadores, QML del gestor/Big Mode y traducción inglesa. SHA256SUMS verifica los seis artefactos. No se instalaron ni se abrió la interfaz en la sesión real.
- 2026-11-22 — La cola de instalaciones guarda el historial local con permisos de usuario. Si `omnia-core` se reinicia durante una instalación, la tarea aparece como interrumpida con una explicación localizada; Omnia no intenta reanudar archivos parciales. Arch `0.2.1-3` en `~/Descargas/Omnia/0.2.1-arch-r7`; se corrigió la dependencia inválida `qt6-quickcontrols2` (el módulo viene con `qt6-declarative`). Hashes verificados. No se instaló por falta de privilegios en el entorno.
