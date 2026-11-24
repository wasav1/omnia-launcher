# Histórico: decisiones y estado del diseño con KDE Plasma (noviembre de 2026)

> Archivado el 2026-11-24. Era el contenido de las secciones 4–6 de `CONTEXTO.md` cuando el proyecto giraba en torno a Plasma 6 y su wallpaper/widget. Se conserva por si hace falta un detalle (mando, modo juego, partidas, plantillas); **no describe el estado actual**: para eso, `docs/HANDOFF.md` y `docs/CONTEXTO.md`.

## Decisiones y hallazgos clave
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

## Estado (entonces)
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

## Operación (entonces)
- Compilar paquetes: `packaging/arch/build-local.sh` (deja los `.pkg.tar.zst` en `/tmp/omnia-pkg/`; copiarlos a `out/`).
- Instalar: `sudo pacman -U packaging/arch/out/omnia-*.pkg.tar.zst` y
  `systemctl --user restart omnia.service omnia-ui.service`.
- Configuración de KDE: `omnia-setup --status | --dry-run | --yes | --undo` (copia en `~/.config/omnia/setup-backup.json`).
- Pruebas manuales: usar `XDG_*` temporales, `OMNIA_DBUS_NAME` único y otro puerto; teclas del mando con `POST /emit?k=…`;
  capturas con `spectacle -b -n -a`. No usar `pkill -f`.
- El usuario ejecuta los `sudo`; nunca imprimir la clave de SteamGridDB; confirmar antes de commit/push.

