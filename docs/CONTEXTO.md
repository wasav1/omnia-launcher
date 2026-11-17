# Omnia — documento de contexto

> Documento vivo. Se actualiza con **cada cambio** (ver «Registro de cambios» al final). Es el punto de entrada para
> retomar el proyecto sin haber visto las conversaciones anteriores. Detalles por tema: ver `docs/`.

## 1. Qué es
Omnia es un lanzador de juegos para **KDE Plasma 6** (rehacer y mejorar el prototipo «Estantería», que vivía en
Bazzite). Biblioteca unificada (Steam, Heroic, Lutris, juegos manuales: ports y emuladores), el **wallpaper nativo** anima
el fondo del juego seleccionado y un **widget Plasma de pantalla completa** aloja el escritorio interactivo y el Big Menu.
Comparten el estado mediante `omnia-core`; también incluye control con **mando**, **modo juego**, **historial**,
**respaldo/restauración de partidas**, e instalación por paquetes Arch con configuración de KDE **automática y reversible**.

Repo: https://github.com/wasav1/omnia-launcher (privado por ahora). Se planea publicarlo para el AUR.
Principios: todo automático al instalar (no pasos manuales), cambios en KDE siempre reversibles, nada de piratería
(no hay ROMs ni detección de carpetas de Hydra), el disco de Bazzite se monta solo lectura y no se modifica.

## 2. Estructura del repo
| Ruta | Contenido |
|---|---|
| `core/omnia/` | Servicio `omnia-core` (Python, solo biblioteca estándar) |
| `ui/qml/` | Componentes QML compartidos por el widget nativo Plasma y la interfaz layer-shell anterior |
| `plasma/` | Wallpaper pasivo, widget interactivo y proveedor QML del token de sesión |
| `kwin/` | Scripts de KWin: `omnia-showdesktop`, `omnia-watch` |
| `packaging/arch/` | PKGBUILD (pkgbase `omnia-launcher`: `omnia-core`, `omnia-ui`, `omnia-kde`), `build-local.sh`, `out/` (ignorado) |
| `tests/` | Pruebas `unittest` (263). Ejecutar: `PYTHONPATH=core python -m unittest discover -s tests` |
| `docs/` | `MIGRACION`, `SPIKE-LAYER-SHELL`, `MODO-JUEGO`, `HISTORIAL`, `PARTIDAS`, y este documento |
| `legacy/`, `plasmoid/`, `tools/`, `install-arch.sh` | Material del prototipo y utilidades |

**Importante:** sin `PYTHONPATH=core` los tests importan el paquete instalado en el sistema (más antiguo).

## 3. Arquitectura
- **Servicio** `omnia.service` (systemd de usuario): API HTTP en `127.0.0.1:47831`. Token de sesión en
  `$XDG_RUNTIME_DIR/omnia/token` (0600), cabecera `Authorization: Bearer`, comprobación de `Host`, rutas que modifican solo
  por POST, sin CORS.
- **Interfaz nativa actual**: wallpaper `org.omnia.launcher` consulta la selección persistida en el núcleo; widget
  `org.omnia.desktop` monta `OmniaShell` en modo transparente. El servicio `omnia-ui.service` queda como alternativa
  layer-shell anterior y el instalador nuevo lo desactiva para evitar interfaces duplicadas. Autostart de primera vez:
  `omnia-first-run.desktop` (activa solo `omnia.service`).
- **D-Bus** `org.omnia.Core` (Gio/PyGObject): los scripts de KWin informan `SetDesktop(active, covered)` y llaman `ToggleMenu`.
- **Rutas API** (resumen): `/health /library /library/refresh /game/{fav,hide,add,remove} /launch /apps /app/{launch,fav}
  /events /pad /emit /desktop /menu /menu/state /gamemode /fs/list /templates /saves /saves/{config,backup,restore,open,suggest}
  /art/{browse,pick,cycle} /audio /audio/{outputs,set} /system /power /import/{find,preview,apply}`.
- **Módulos del core:** `paths, store (state.json/library.json), security, launcher (systemd-run --user --scope), api, events,
  pad (evdev sin dependencias), audio (parec → 32 bandas mel con Goertzel, sin guardar audio), system (CPU, disco de juegos, batería), audio_out (salida de audio), power (bloquear/suspender/cerrar sesión/reiniciar/apagar), dbus, service, setup (omnia-setup), firstrun, apps, art (SteamGridDB), gamemode, sessions,
  saves, fsbrowse, templates, manual, importer, games/{base,vdf,steam,heroic,lutris,gfn,refresh,registry}`.
- **Datos del usuario** (fuera del repo): `~/.config/omnia/{library.json,state.json,first-run.json,setup-backup.json,
  steamgriddb.key}`, `~/.local/share/omnia/art`.

## 4. Decisiones y hallazgos clave
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

**Instalador local:** revisión 5 del asistente Arch y `.run` de fuentes preparados con dependencias completas para CachyOS.
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
Más reciente primero. Cada cambio añade una línea aquí (y actualiza las secciones 4–5 si procede).

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
  El `.run` es gráfico; no se ha generado un AppImage. El binario se construye para la máquina actual y el lanzador
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
