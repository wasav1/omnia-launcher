# Omnia como aplicación independiente

## Objetivo

Omnia será una aplicación de escritorio instalable para descubrir, organizar, instalar y ejecutar juegos. Mantendrá el
panel rápido y Big Mode que ya existen, y Big Mode tendrá una sección **Inicio** con descubrimiento y novedades del
catálogo de Omnia. El funcionamiento principal no dependerá de RecompLauncher.

## Límites de responsabilidad

- **Aplicación Omnia (local):** interfaz de gestión, preferencias, biblioteca local, rutas de instalación, análisis de
  carpetas/ROMs, historial, selección de plataforma, descargas autorizadas y lanzamiento.
- **Backend Omnia (remoto):** catálogo público, metadatos, plataformas, artwork y manifiestos versionados de contenido
  instalable. SteamGridDB permanece como proveedor interno del backend; el cliente nunca recibe ni solicita su clave.
- **RecompLauncher:** referencia de producto e interfaz para el contenido de Inicio; no será una dependencia necesaria
  para escanear, instalar, ejecutar ni mostrar arte.
- **Datos del usuario:** permanecen en el equipo. Las ROMs, ejecutables, partidas y rutas no se suben al backend.

## Navegación de la aplicación

La aplicación instalará un gestor con secciones **Inicio**, **Biblioteca**, **Descargas/Instalaciones** y **Ajustes**.
Desde ella se podrán añadir ubicaciones, importar juegos detectados, configurar controles y elegir idioma (español o
inglés). El panel rápido seguirá siendo una superficie ligera y Big Mode seguirá siendo una vista de pantalla completa.
Ambos compartirán biblioteca, juego seleccionado, actividad reciente y preferencias con el gestor.

Big Mode abrirá inicialmente en **Inicio** y ofrecerá también **Biblioteca** y **Detalles**. Inicio consumirá noticias, destacados, actualizaciones
y recomendaciones del backend cuando existan; la Biblioteca seguirá mostrando los juegos locales y podrá filtrar por
plataforma. Al detectar un mando se mostrarán ayudas de mando; al desconectarlo, las de teclado y ratón.

## Contratos implementados y datos pendientes

La API pública actual de `omnia-backend` cubre catálogo, plataformas y artwork, sin clave del cliente. Se añadió un
primer contrato de paquetes curados: solo los publicados son visibles, con URL HTTPS, fuente y licencia, formato
permitido, tamaño máximo de 20 GiB, SHA-256, subcarpeta de instalación y punto de entrada relativo. El endpoint
administrativo requiere credenciales y puede crear o retirar paquetes; la migración está en
`migrations/0003_install_packages.sql` y ya se aplicó en producción. Omnia expone esa lectura y la cola de instalaciones a QML por su servicio
loopback. El gestor exige aceptar licencia, permite elegir un destino, limita la descarga al tamaño publicado,
comprueba SHA-256, bloquea hosts privados y redirecciones no HTTPS, conecta directamente a una IP pública validada
por intento (sin proxies ambientales), limita el tamaño expandido y rechaza traversal, enlaces y archivos especiales.
Reserva espacio por volumen para las descargas y la expansión, coordinando las tareas simultáneas y conservando un
margen libre. Solo registra el juego después de extraer y validar el punto de entrada. No ejecuta
comandos recibidos. El desinstalador propio de paquetes solo retira instalaciones registradas por Omnia y pregunta
antes de borrar sus archivos.

El reconocimiento local comienza con escaneo explícito de carpetas elegidas por el usuario: N64, NES, SNES, Game Boy,
Game Boy Color, Game Boy Advance, Nintendo DS, GameCube/Wii, Nintendo 3DS, Switch, PlayStation, PlayStation 2 y PSP.
Comprueba cabeceras cuando el formato las expone; para contenedores cifrados o discos usa extensión y nombre como
sugerencia, nunca como prueba de identidad. Los formatos de disco ambiguos permiten escoger la consola antes de elegir
un emulador compatible instalado. Antes de añadir cada candidato el usuario puede corregir el nombre y elegir consola y
emulador. No mueve ni borra ROMs, y no sube su contenido ni hashes.
Para identificar títulos, el backend publica un índice curado de IDs de cabecera por plataforma. Omnia descarga el
índice por consola y compara IDs exclusivamente en el equipo; no consulta al backend con el ID hallado en una ROM. Una
coincidencia puede sugerir el nombre del catálogo y asociar el slug para artwork. El usuario confirma la importación.
Los IDs se administran en el backend y requieren aplicar su migración antes de que el endpoint esté disponible. Para
juegos locales detectados por Steam, Heroic, Lutris o añadidos como ports, el gestor permite iniciar una búsqueda
manual y asociar una ficha elegida. No envía el nombre local automáticamente; solo transmite la consulta que escribe
el usuario y el slug de la ficha seleccionada. El vínculo se guarda localmente y se puede quitar o cambiar.
Descargas de contenido solo aparecerán para elementos que tengan un manifiesto verificable, licencia/fuente y pasos de
instalación explícitos.

## Etapas de implementación

1. **Congelar el punto de partida:** preservar el estado local de Omnia y trabajar en una rama aislada. Auditar
   empaquetado, panel, Big Mode, fuentes de juegos y el contrato actual del backend.
2. **Definir contratos:** documentar catálogo, Inicio, artwork, manifiestos instalables, fuentes/licencias, versiones,
   sumas de comprobación y estados de instalación. Mantener las rutas actuales compatibles.
3. **Independizar biblioteca:** introducir un modelo local de juegos y adaptadores de fuentes (Steam, Heroic, Lutris,
   ports/manuales y ROMs) sin requerir RecompLauncher. Migrar las entradas existentes sin perder datos ni IDs.
4. **Conectar Omnia Backend:** cliente público con caché, paginación, búsqueda, artwork y Inicio; funcionamiento local
   degradado si el backend no está disponible.
5. **Construir gestor instalable:** catálogo, escaneo/importación, cola de descargas, selección de carpetas, progreso,
   pausa/reanudación, verificación de hashes y desinstalación segura.
6. **Integrar superficies actuales:** panel y Big Mode usarán el mismo servicio local. Añadir Inicio a Big Mode y
   mantener controles de mando/teclado. No duplicar escaneos ni sondeos de recursos.
7. **Localización y distribución:** traducir interfaz, mensajes y documentación a español/inglés; preparar instaladores
   y actualización para las distribuciones objetivo.
8. **Revisión de seguridad y publicación:** revisar permisos, URLs, archivos comprimidos, ejecución y secretos; preparar
   cambios revisables en ambos repositorios. No desplegar backend ni publicar releases sin autorización específica.

## Estado de auditoría

- El árbol de trabajo de Omnia ya contenía cambios locales antes de este plan; se conservaron y se generó una copia de
  seguridad externa al repositorio.
- El repositorio backend privado se reconstruyó localmente desde la fuente autorizada y se verificó que su árbol coincide
  con `main`; su copia local permite cambios y revisión, aunque no tiene un remoto autenticado.
- El backend ya ofrece lecturas públicas de catálogo, plataformas y artwork. Sus nombres internos y recursos Cloudflare
  conservan el legado RecompiHub; no se renombrarán sin una migración compatible.
- El servicio de Omnia ya tiene rutas loopback para catálogo, detalle, plataformas e IDs ROM. El cliente público usa
  paginación, timeout, límite de respuesta y caché local; la búsqueda no crea cachés ilimitadas.
- El escáner extrae IDs de cabecera de N64, GameCube, Wii, GBA y Nintendo DS; para discos PS1/PS2 extrae localmente
  el serial de SYSTEM.CNF desde ISO, BIN o CUE sin extraerlos y evita listar dos veces el BIN enlazado por un CUE.
  El analizador lee solo el descriptor ISO, la entrada raíz y el
  archivo de configuración, con límites de lectura. Se amplió el contrato del backend para ps1 y ps2; faltan IDs
  curados para que el serial encuentre una ficha. Se añadió al backend un índice público
  por plataforma y su reemplazo administrativo; Omnia descarga ese índice, compara todo localmente y solo adjunta el
  slug del catálogo al importar tras confirmación. La ruta pública es `GET /api/v1/games/rom-identifiers`; el cliente
  local de Omnia la consume a través de `/catalog/rom-identifiers`. No transmite rutas, archivos, hashes ni IDs
  hallados en ROMs. La migración `0004_game_rom_identifiers.sql` ya está aplicada en producción. El endpoint público
  ya devuelve el ID N64 `CZLE` de The Legend of Zelda: Ocarina of Time, asociado a su plataforma; la respuesta se
  verificó después de publicar el registro. La seed idempotente se redujo a ese único vínculo e ID aprobados. No hay
  otros títulos/IDs ROM publicados todavía; ampliar el índice requiere curar IDs y vincular las plataformas de las
  fichas correspondientes.
- Big Mode ya tiene un módulo Inicio conectado al catálogo: destacado, novedades, tres juegos recientes, búsqueda,
  ficha de catálogo y presentación offline. Abre inicialmente en Inicio. Cuando el backend todavía no publica títulos, usa el juego local más
  reciente como destacado y permite lanzarlo sin conexión. Desde las fichas del catálogo puede iniciar una instalación
  publicada.
- La clave de proveedor dejó de ser parte de los flujos activos del cliente: el instalador y los ajustes de
  illogical-impulse ya no la solicitan ni la guardan. El servicio retira el archivo de clave antiguo al arrancar. El panel
  obtiene el artwork publicado desde el backend para los juegos vinculados al catálogo y conserva imágenes locales
  anteriores. `core/omnia/art.py` ahora solo localiza esa caché local; no contiene cliente ni funciones de credenciales.
- Hay selector de idioma español/inglés en el gestor y Big Mode. Se persiste por usuario; el lanzador carga el catálogo
  Qt al abrir y reinicia la interfaz conservando el modo cuando cambia el idioma. El catálogo inglés contiene 461
  entradas traducidas (sin traducciones vacías) y el `.qm` compilado se incluye en `omnia-app`. Los mensajes de error
  del núcleo, ROMs, biblioteca, instalaciones, partidas y artwork tienen traducciones inglesas explícitas; errores
  poco frecuentes aún pueden mostrarse con un mensaje genérico.
- Se añadió un primer centro de control en ventana (Inicio, Biblioteca, Explorar, Instalaciones, Ajustes) y una entrada
  `omnia-ui --manager`; el botón Big Mode abre la biblioteca existente compartiendo el objeto local de API. El paquete
  Arch `omnia-app` incorpora accesos XDG separados para el gestor y para Big Mode en pantalla completa. Ajustes gestiona rutas; el gestor tiene una cola de descargas,
  progreso, cancelación y desinstalación confirmada de paquetes registrados. La compatibilidad completa del instalador
  universal sigue pendiente.
- Se construyó localmente el conjunto split de Arch desde un snapshot del árbol de trabajo, sin instalarlo: `omnia-core`,
  `omnia-app`, `omnia-hyprland` y `omnia-kde`. Se inspeccionaron `omnia-app` y `omnia-hyprland`: el primero declara
  dependencias Qt/Core sin dependencias de Plasma e incluye el gestor, Big Mode, Inicio, los dos `.desktop`, `org.omnia` y el
  catálogo inglés; el complemento depende de `omnia-app`, empaqueta el panel y su instalador reversible. El CLI incluido
  respondió `--help`; su estado detectó la integración actual de illogical-impulse y el `install --dry-run` reconoció sus
  anclas sin escribir cambios. Los paquetes son artefactos de revisión sin firma y no se publicaron.
- Se retiró RecompLauncher de los detectores activos y del worker de artwork. La compatibilidad quedó aislada en
  `core/omnia/games/legacy_recomp.py`: una migración de una sola vez convierte los ports que ya estaban instalados en
  entradas locales de Omnia y apunta directamente a sus `AppRun`; no mueve archivos ni ejecuta el lanzador antiguo.
- Ajustes incorpora una primera gestión de ubicaciones: añadir mediante selector de carpetas o ruta y retirar sin borrar
  archivos. El core limita las ubicaciones a subcarpetas del home y unidades montadas, y conserva exclusiones para que
  los juegos registrados no reaparezcan si se retira una ubicación. La carpeta de instalación de paquetes se puede
  guardar como preferencia compartida por el gestor y Big Mode; el core valida que exista dentro de una raíz permitida.
- Biblioteca escanea carpetas elegidas para N64, NES, SNES, GB/GBC/GBA, DS, GameCube/Wii, 3DS, Switch, PS1, PS2 y PSP. Comprueba
  cabeceras disponibles y usa nombre/extensión para formatos sin metadatos accesibles. La vista de confirmación ofrece
  solo emuladores compatibles detectados (Gopher64, RetroArch con core local, Dolphin, melonDS, Citra/Azahar, Ryujinx,
  Yuzu o Suyu, según el sistema); al importar vuelve a validar la ruta, formato y emulador. No calcula ni envía hashes,
  y no prueba identidad comercial. Los formatos compartidos como ISO, CHD, PBP y CSO muestran una selección explícita de
  plataforma para no atribuirlos automáticamente a una consola incorrecta. No incluye todavía ROMs dentro de archivos.
- La Biblioteca del gestor expone el asistente local existente para añadir ports, ejecutables, juegos de Windows y ROMs
  N64, e Instalaciones muestra juegos locales y trabajos de paquetes publicados, permite cancelar, lanzar y desinstalar.
  Las instalaciones pueden pausarse y reanudarse entre bloques de descarga y extracción mientras el servicio siga en
  ejecución. El historial se conserva al reiniciar `omnia-core`; las tareas que estaban activas aparecen como
  interrumpidas y deben iniciarse de nuevo, porque los archivos parciales no se reanudan automáticamente.
  La instalación directa está limitada por ahora a paquetes de PC con punto de entrada ejecutable declarado; no se han
  publicado paquetes ni desplegado la migración de backend.
- Pendiente: publicar paquetes con licencia,
  añadir identificación de títulos mediante una base local de metadatos/hashes, admitir más formatos de disco y ROMs
  comprimidas, añadir reanudación de descargas desde archivos parciales y ampliar el instalador independiente fuera del paquete
  Arch. El gestor QML independiente ya se incluye en el instalador universal de escritorio; el paquete Arch también lo
  ofrece como `omnia-app`. Los mensajes infrecuentes del núcleo aún pueden mostrarse de forma genérica en inglés.
- La instalación del módulo de illogical-impulse ya no pide una clave personal: el panel muestra que las imágenes
  publicadas se sirven desde `omnia-backend`. La rotación/selección del panel queda limitada al artwork público asociado
  al catálogo; para juegos aún no vinculados se mantiene el arte que ya esté guardado localmente.
- La descarga de manifiestos fija la conexión TLS a una IP pública resuelta para esa conexión y no usa proxies de
  entorno. También revalida redirecciones HTTPS, evitando que una resolución DNS distinta entre validación y conexión
  permita alcanzar una dirección privada.
- Revisión del 2026-11-22: se reconstruyeron los cuatro paquetes Arch (`omnia-app`, `omnia-core`, `omnia-hyprland` y
  `omnia-kde`) desde el árbol actual, sin instalarlos. El paquete independiente contiene el gestor, Inicio de Big Mode,
  la biblioteca, la traducción inglesa, el lanzador y la entrada XDG; se verificó también que el paquete de núcleo lleva
  la ruta persistente para guardar la carpeta de instalación. `qmllint` no está instalado en el entorno, por lo que
  QML no recibió esa validación. El backend pasó `tsc --noEmit` y `wrangler deploy --dry-run`. Se ejecutaron
  comprobaciones estáticas de Python y `git diff --check`, pero no pruebas automatizadas. El 2026-11-22 se aplicaron
  en D1 las migraciones 0002, 0003 y 0004 y se desplegó el Worker (versión
  `486f344b-a835-4895-b82e-bfe79e4e0652`). `/health` y `/api/v1/health` respondieron `ok`; catálogo, plataformas e
  índice ROM respondieron correctamente. Luego se publicó, con autorización, solo la relación N64 y el ID `CZLE` de
  Ocarina of Time; ambos endpoints de catálogo ya devuelven esos datos. Big Mode usa el juego local reciente como
  destacado cuando no hay otros títulos publicados.
- Actualización: Big Mode abre en Inicio y conserva Biblioteca como sección directa. Se reconstruyeron los cuatro
  paquetes Arch y se verificó dentro de `omnia-app` la vista QML con Inicio como página inicial. Los paquetes de esta
  revisión están en `~/Descargas/Omnia/0.2.1-arch` junto al PKGBUILD, la fuente empaquetada y `SHA256SUMS` (todos
  verificados); no se instalaron.
- 2026-11-22 — Se añadió un segundo acceso XDG, **Omnia Big Mode**, que abre `omnia-ui --window` sin depender del
  panel de illogical-impulse. Se reconstruyeron los cuatro paquetes Arch desde el árbol de trabajo actual y se
  conservaron aparte en `~/Descargas/Omnia/0.2.1-arch-r5`; `omnia-app` contiene ambos `.desktop`, el gestor, Big Mode
  y el catálogo inglés. Los seis artefactos de revisión tienen sus sumas SHA-256 verificadas. No se instalaron.
- 2026-11-22 — El historial de instalaciones ahora sobrevive reinicios de `omnia-core`; las descargas que estaban
  activas quedan marcadas como interrumpidas, sin intentar reanudar datos parciales. Paquetes Arch `0.2.1-3`
  construidos desde el árbol local en `~/Descargas/Omnia/0.2.1-arch-r7`; sumas SHA-256 verificadas e inspección
  estática de ambos accesos XDG y recursos QML/inglés. La dependencia inválida `qt6-quickcontrols2` se retiró; el
  requisito de Qt Quick Controls viene incluido en `qt6-declarative`. No se instalaron por falta de privilegios.
