# Instaladores de Omnia Desktop Suite

### Revisión 38: recuperación si falla el despliegue (Q-05)

`Omnia-Installer-0.1.0-38-x86_64.AppImage` incluye el diario de transacción y el rollback ante errores detectables. El
instalador universal crea un respaldo privado en `~/.local/share/.omnia-install-transaction-*` antes de modificar
archivos. Si una etapa falla, repone los destinos previos, quita los archivos que creó, recarga systemd y restaura los
servicios que estaban activos. También conserva el diario si no logra completar la restauración. Al finalizar con éxito,
descarta el respaldo. El snapshot incluye código y recursos de Omnia, accesos systemd, configuración relacionada con la
instalación y los archivos de Plasma que este flujo modifica; no incluye biblioteca, arte, historial ni partidas.

Esta protección es rollback ante errores detectables mientras el instalador sigue ejecutándose, no una transacción
atómica frente a apagado, corte eléctrico, `SIGKILL` o fallo del almacenamiento. Tampoco revierte las dependencias de
sistema añadidas con `rpm-ostree`. La restauración de archivos y servicios tiene pruebas unitarias en directorios
temporales y se verificó la extracción del AppImage con ambos scripts presentes. La revisión 38 se construyó en
CachyOS x86-64 y se instaló en Bazzite. Se cotejaron con el repositorio el core, QML, wallpaper, applet, scripts KWin y
fuentes instalados; `omnia.service` está activo/habilitado y `/health` y `/library` responden 200 (36 elementos).
No se forzó un fallo en la máquina real para probar la ruta de rollback.

### Revisión 34: conflicto con el puerto de Estantería y respuestas inválidas

`Omnia-Installer-0.1.0-37-x86_64.AppImage` incorpora estos cambios. El prototipo anterior (`estanteria-helper.service`) escuchaba en el mismo puerto 47831 y respondía 200 a rutas
desconocidas, incluida `/selection`. Al instalar Omnia encima, `omnia-core` no podía abrir el puerto y la interfaz
hablaba con el servicio viejo: el carrusel volvía al índice 0 en un bucle y el wallpaper no recibía arte.
El instalador ahora detiene y deshabilita `estanteria-helper.service` antes de arrancar Omnia y comprueba `/health`
al terminar; si detecta la firma antigua (`padName`) o que el puerto no responde, muestra el diagnóstico y los
comandos para resolverlo. `OmniaShell` y el wallpaper ignoran los 200 sin `id`/`revision` y reintentan con espera,
en lugar de aceptarlos como una selección vacía.

### Revisión 33: desinstalar en homes con enlace (Bazzite/OSTree)

En Fedora Atomic y Bazzite, `/home` es un enlace a `/var/home`, así que todo el home cuelga de un enlace.
El validador del desinstalador lo interpretaba como una redirección sospechosa y se detenía con
«Ruta redirigida mediante enlace; se conserva: …». Ahora permite los enlaces que forman parte de la ruta del
home y sigue bloqueando los que aparecen dentro de él (`~/.local/share/omnia/ui -> ~/Juegos`, por ejemplo),
de modo que nunca se borra el destino de un enlace ni archivos de juegos o partidas.

### Revisión 32: instalador para Bazzite (OSTree)

`Omnia-Installer-0.1.0-32-x86_64.AppImage` incorpora la detección de Bazzite/Fedora OSTree y el flujo de
dependencias con `rpm-ostree`: prepara el deployment con `--idempotent`, aplica en caliente solo si el cambio
son adiciones y pide reiniciar cuando reemplaza o retira paquetes base. La comprobación Fedora acepta paquetes
cubiertos por otro nombre (`rpm -q --whatprovides`), así que `mangohud` cuenta como satisfecho con
`terra-mangohud`. La GUI se recompiló para cerrar la sesión con `qdbus6`, `qdbus-qt6` o `qdbus`, y el
manifiesto del AppImage se etiqueta también para Bazzite.

### Revisión 31: sincronización inmediata del estado visual de juego

La opacidad de la ficha, el reloj y el monitor, además de los sondeos de audio y sensores, ahora sigue el
mismo estado inmediato de juego que la pantalla «Jugando». La histéresis del perfil de energía sigue siendo
independiente para evitar cambios bruscos al cerrar un juego.

### Revisión 30: iniciar Longshot sin abrir su launcher

El launcher de Longshot interpreta `--launch <carpeta>` como «abrir la interfaz en ese build»; `--play <carpeta>`
inicia el juego sin ventana. Omnia lee el `builder=` de `longshot_version.txt` y usa `--play` para entradas que
ya estaban guardadas con el wrapper `longshot`.

### Revisión 29: lanzar AppImages bajo NoNewPrivileges

Omnia ejecuta el núcleo con `NoNewPrivileges=true`. Esta protección impedía que `fusermount` montara los
AppImages de juegos, aunque FUSE estuviera instalado. El lanzador ahora usa `APPIMAGE_EXTRACT_AND_RUN=1`
para que los ports AppImage se extraigan temporalmente y conserven la protección del servicio.

### Revisión 28: escaneo y vinculación en pasos separados

El asistente primero escanea los discos y muestra los juegos reconocidos. Al continuar, abre la selección de carpetas
y la revisión para vincular o desvincular juegos. La ventana de candidatos incluye búsqueda por nombre, port y archivo.
Los ajustes de Omnia usan el mismo flujo de dos pasos. La revisión también incorpora la migración de Minecraft de la revisión 27.

### Revisión 27: migración de Minecraft BedrockOnLinux

Al iniciar el servicio, Omnia corrige las entradas anteriores de `Minecraft.Windows.exe` que se habían guardado
como juegos Windows genéricos con UMU. Las cambia al AppImage BedrockOnLinux con argumento `play`, manteniendo
el identificador y los datos del juego.

### Revisión 26: Minecraft Bedrock en el escáner

El escáner agrupa `Minecraft.Windows.exe` con el lanzador BedrockOnLinux y los presenta como **Minecraft Bedrock · PC**.
Al confirmar, Omnia reutiliza `BedrockOnLinux-*.AppImage play`; no solicita UMU ni importa las herramientas internas.

### Revisión 25: reconocimiento del marcador de Minecraft Bedrock

BedrockOnLinux guarda su marcador de instalación junto a `Minecraft.Windows.exe`, dentro de la carpeta de versión.
Omnia busca el marcador en esa ruta y sus directorios superiores, y lanza el AppImage asociado con el argumento
`play`.

### Revisión 24: detección y lanzamiento de Minecraft BedrockOnLinux

El asistente reconoce `Minecraft.Windows.exe` de BedrockOnLinux y registra Minecraft Bedrock como juego manual.
Omnia lo inicia mediante el AppImage `BedrockOnLinux-*.AppImage play`, reutilizando su prefijo, sesión y datos
existentes; no crea un prefijo UMU genérico. Para agregarlo, usa **Añadir juego**, elige ese ejecutable y confirma
el nombre sugerido.

Todos estos formatos abren el mismo asistente para rutas, candidatos, SteamGridDB y volumen del monitor.
Requieren una sesión KDE Plasma 6, Qt >= 6.6, Python >= 3.11 y systemd de usuario. No son compatibles con Plasma 5.

| Archivo | Destino |
| --- | --- |
| `omnia-desktop-suite-installer_0.1.0-1_all.deb` | Debian 13 y Ubuntu/Kubuntu con Plasma 6 y Qt compatible |
| `omnia-desktop-suite-installer-0.1.0-1-any.pkg.tar.zst` | Arch, CachyOS, EndeavourOS; derivados con dependencias compatibles |
| `Omnia-Desktop-Suite-0.1.0-source.run` | Instalador gráfico portable basado en fuentes para las familias anteriores |
| `omnia-desktop-suite-installer-0.1.0-sources.tar.gz` | Fuentes del asistente para compilación local |

La construcción del asistente también admite RPM de Fedora y openSUSE cuando `rpmbuild` está disponible; esos dos
paquetes no forman parte de los artefactos actuales.

## Uso

Los paquetes `.deb`, `.rpm` y `.pkg.tar.zst` instalan **el asistente con sus fuentes**, un icono y la entrada
**Omnia Desktop Suite — Instalar o actualizar** en el menú. El paquete no toca escritorios ni servicios de usuarios
durante la transacción del gestor de paquetes. Ábrelo desde tu sesión Plasma normal, sin sudo.

El asistente compila los componentes contra el Qt local y despliega Omnia en `~/.local`, con consentimiento previo.
KDE/Polkit pide autorización si hacen falta dependencias. Los paquetes declaran sus dependencias de compilación.
El `.run` portable puede necesitar instalar esas dependencias al abrirse. Tras darle permiso de ejecución se abre
con doble clic según las preferencias del gestor de archivos. El archivo de fuentes se extrae y se abre con
`bash packaging/universal/launch-gui.sh` desde su carpeta.

Comandos alternativos para instalar el paquete del asistente:

```sh
# Debian / Kubuntu
sudo apt install ./omnia-desktop-suite-installer_0.1.0-1_all.deb
# Arch / CachyOS
sudo pacman -U ./omnia-desktop-suite-installer-0.1.0-1-any.pkg.tar.zst
```

Los paquetes de esta compilación local no están firmados; la firma de releases se preparará antes de publicación.
Eliminar el paquete nativo retira el asistente global, pero no elimina Omnia instalado por usuario, ni juegos ni partidas.
Los paquetes anteriores `omnia-core`, `omnia-ui` y `omnia-kde` de Arch siguen siendo la vía de instalación del sistema;
los nuevos archivos `omnia-desktop-suite-installer` son la vía del asistente por usuario.

## Alcance comprobado

Se verificaron los formatos, metadatos, dependencias declaradas y contenido. El flujo universal ya se usa en CachyOS.
No se ha ejecutado todavía una instalación completa de estos nuevos paquetes en Debian, Fedora u openSUSE: requieren
validación en máquinas virtuales de destino. No se empaquetan binarios Qt de CachyOS en estos archivos; la GUI y el
puente QML se compilan en destino. El `omnia-kde.run` anterior con binario local se conserva para la máquina actual.
Las ediciones OSTree/inmutables (Bazzite, Kinoite y similares) son compatibles mediante el flujo descrito en
[Instalación en Bazzite (OSTree)](#instalación-en-bazzite-ostree). Tener KDE Plasma por sí solo no garantiza que se
puedan escribir componentes de sesión; Omnia los instala en `~/.local` y nunca toca `/usr`.

## Instalación en Bazzite (OSTree)

Bazzite (Kinoite, edición KDE) es un sistema **inmutable basado en Fedora con rpm-ostree**: `/usr` es de solo lectura y
las dependencias del sistema se añaden como **capas** con `rpm-ostree install`. Omnia ya no rechaza estos sistemas:

1. **Detección.** `packaging/universal/distro.sh` lee `/etc/os-release` (o `/run/host/os-release` si el asistente se
   ejecuta desde un sandbox Flatpak) y detecta `ID=bazzite`, `ID_LIKE=fedora` y el marcador `/run/ostree-booted`.
   Selecciona el perfil de dependencias `fedora` y el gestor `rpm-ostree`.
2. **Dependencias.** El asistente propone instalar, mediante Polkit, los paquetes del perfil Fedora (Qt 6, CMake,
   compilador, Kirigami, PyGObject, `qdbus6`/`qdbus-qt6`, MangoHud…). Primero se **prepara el deployment** con
   `rpm-ostree install --idempotent`. Si el cambio son solo adiciones, se aplica en caliente con `rpm-ostree apply-live`;
   si reemplaza o retira paquetes base (habitual al añadir `-devel` sobre un Qt algo más antiguo), el instalador avisa de
   que hay que **reiniciar** y volver a ejecutarlo. Tras el reinicio, los paquetes de desarrollo ya están activos y la
   instalación continúa. La comprobación Fedora acepta nombres alternativos mediante `rpm -q --whatprovides` (por
   ejemplo, Bazzite cubre `mangohud` con `terra-mangohud`).
3. **Instalación de Omnia.** El núcleo Python, el wallpaper, el widget Plasma, los scripts de KWin y los binarios de
   usuario se copian a `~/.local`, igual que en CachyOS. No se escribe en `/usr`.
4. **Reinicio de Plasma.** Tras compilar el proveedor del token QML con el Qt del sistema, se reinicia
   `plasma-plasmashell.service` (o se pide cerrar sesión) y se aplica el layout del widget.

El instalador ".run portable" o el AppImage se pueden abrir desde el menú de Plasma en Bazzite. Si se usa el `.run`,
el propio asistente compila la GUI Qt contra el Qt del sistema; no se distribuye un binario ligado a otra distro.
**Validación real (Bazzite 45 Kinoite, revisión 36, 2026-11-18):** actualización comprobada en la sesión KDE Plasma 6.8.3.
`omnia.service` está habilitado y activo; `/health` devuelve 200 y `/library` responde con 36 juegos. Las dependencias
del instalador pasan `--check`; el deployment activo tiene las capas Qt/CMake requeridas. Los árboles instalados de
Python, QML, wallpaper, applet y KWin coinciden con los archivos del proyecto. Plasma registra el wallpaper Omnia y
no hay errores de importación de su plugin. Tras reiniciar Plasma, ya no aparece la advertencia QML de `undefined`
en el botón “Aceptar cambios” del editor de arte. Sigue apareciendo una advertencia ajena a Omnia sobre el plugin
opcional `org.kde.plasma.panelcolorizer`, que solo afecta su fondo blur personalizado. No se verificaron interacciones
manuales de todas las pantallas del asistente. La revisión 37 añade las fuentes licenciadas al árbol QML; su carga y
archivos quedaron instalados con hashes coincidentes; tras reiniciar Plasma no hay errores QML de Omnia y el wallpaper
carga. No se hizo una comparación visual de métricas tipográficas ni se recorrieron manualmente todas las pantallas.

## Construcción

```sh
python3 packaging/distros/build.py
# Para formatos concretos:
python3 packaging/distros/build.py --formats deb,arch,run,source
```

Se necesitan `ar`, `zstd` y herramientas RPM (`rpmbuild`) para los formatos correspondientes. La construcción de RPM
usa base de datos y temporales privados. La salida va en `packaging/distros/out/`, con `SHA256SUMS` y `manifest.json`.
`profiles.json` centraliza dependencias de los paquetes. Los nombres de dependencias de distribuciones pueden variar
entre versiones; las entradas son objetivos de prueba, no garantía de compatibilidad con cualquier derivada.

Fuentes de referencia:
- https://www.debian.org/doc/manuals/packaging-tutorial/packaging-tutorial
- https://packages.debian.org/trixie/plasma-workspace
- https://packages.debian.org/trixie/libs/qml6-module-org-kde-ksysguard
- https://packages.fedoraproject.org/pkgs/qt6-qt5compat/
- https://packages.fedoraproject.org/pkgs/plasma-workspace/

## Instalación limpia en Arch y CachyOS (revisión 2)

El paquete nativo y el preflight universal usan la misma lista de `packaging/distros/profiles.json`.
Incluye CMake, GCC y Make para compilar; Qt Base/Declarative/5Compat, Kirigami y libksysguard para QML;
Qt Tools para `qdbus6`; PyGObject y GLib para D-Bus; libpulse para `pactl`/`parec`, además de Plasma,
KWin y Polkit con agente KDE. No exige instalar Steam, emuladores ni launchers externos.
El servidor de audio PulseAudio o PipeWire-Pulse debe estar activo para las funciones de audio de la sesión.

Antes de abrir la GUI y antes de desplegar archivos, el instalador universal comprueba también las dependencias
que no intervienen en la compilación. `--check` y `--no-deps` fallan si falta alguna; en el flujo normal ofrece
instalarlas mediante Polkit y verifica el resultado. El paquete nativo deja que Pacman resuelva esas dependencias.
La vía recomendada para una instalación limpia es el paquete nativo; el `.run` presupone una sesión Plasma con
Python y Polkit disponibles. Si faltan incluso kdialog o Polkit, instala primero el paquete nativo.

Para instalar el artefacto local en un sistema actualizado:

```sh
sudo pacman -U ./omnia-desktop-suite-installer-0.1.0-2-any.pkg.tar.zst
```

Si Pacman informa que falta una base de datos o que las dependencias requieren una actualización, ejecuta
primero `sudo pacman -Syu` y después repite la instalación. No uses una sincronización aislada `pacman -Sy`
seguida de una instalación parcial. Abre después **Omnia Desktop Suite — Instalar o actualizar** desde el menú.

### Revisión 3 (Arch/CachyOS)

El asistente declara también `umu-launcher`: importar un ejecutable Windows necesita `umu-run`.
Proton y su runtime se descargan al ejecutar el primer juego Windows; requieren Internet y espacio adicional.
Los lanzadores Linux de NX2navi, TOTK y Savage Wind no utilizan UMU.

### Revisión 4: carga del puente QML

El proveedor nativo de token se instala junto a los componentes QML de Omnia y wallpaper/widget lo importan
por una ruta relativa. La instalación no añade `QML_IMPORT_PATH` al entorno de toda la sesión. El actualizador
migra el plugin desde la ruta global usada por versiones anteriores.

### Revisión 5: tamaño automático por pantalla

La superficie interactiva se ancla a la ventana del escritorio de su propio monitor (dimensiones lógicas Qt),
no a la celda movible y redimensionable del widget. Sigue cambios de resolución, escala y ventana sin fijar
1920×1080 en la superficie. Se oculta al editar Plasma; los paneles conservan sus ventanas independientes.
El layout reutiliza la instancia existente y retira duplicados al reaplicar.

### Revisión 6: asistente visual

Interfaz oscura con cabecera de pasos, tarjetas de configuración, capacidad real del volumen y resumen final.
El progreso es indeterminado mientras se instala: no muestra porcentajes estimados. Los detalles están plegados
inicialmente y se abren si falla la instalación. Se conserva el flujo de consentimiento y la clave de SteamGridDB
al reintentar. El estilo también se aplica a Ajustes generales y al diálogo de candidatos.

### Revisión 7: ports, selección y complementos

El catálogo `core/omnia/port_catalog.py` reconoce inicialmente Longshot, Hookshot, NX2navi, Savage Wind y TOTK Recomp
por el ejecutable y su contexto de carpeta. Propone el nombre del juego, Switch/Switch 2 y un lanzador; la propuesta
es editable y requiere confirmación. Agrupa versiones y omite builders, launchers y traductores auxiliares.
La identificación no valida hashes de la edición ni garantiza compatibilidad de cualquier versión.

La revisión muestra juego, port/plataforma, ejecutable y emulador. N64 propone Gopher64. Antes de confirmar se
comprueban Gopher64 nativo/Flatpak, UMU para Windows y los emuladores externos; si falta algo, se explica qué instalar
y se conserva la selección para volver a confirmar. No se instalan emuladores automáticamente.

Cada carpeta muestra juegos vinculados, candidatos y selección pendiente; el total distingue juegos de ports/archivos.
Dos ports conocidos del mismo juego cuentan como un juego; las rutas superpuestas no duplican archivos.
La importación agrupa esos ports sin cambiar el ID ni perder el historial de una entrada reconocida existente.
Las entradas ya importadas no se renombran ni migran automáticamente al actualizar el asistente.

### Revisión 8: selección de juegos

Casillas centradas y redondeadas, sin resaltado vacío de celda; foco visible y control con Espacio.
Las entradas ya vinculadas muestran una insignia verde y no se vuelven a importar.

### Revisión 9: desinstalar

Abre **Omnia — Desinstalar** o el botón de Ajustes generales. La pantalla explica los datos que se eliminarán
(configuración, clave, historial, arte y componentes propios) y requiere marcar una confirmación antes de proceder.
No elimina juegos, ROMs, emuladores, partidas ni respaldos externos. Utiliza una lista de rutas propias y bloquea
el borrado si una ruta contiene juegos/partidas registrados o un padre está redirigido por un enlace.

Retira solo los widgets de Omnia y restaura los atajos guardados. Para instalaciones nuevas se guarda el wallpaper
y carpeta anterior de cada escritorio; para instalaciones previas sin ese registro se usa el fondo nativo de Plasma.
Conserva otros widgets y paneles existentes. Reinicia Plasma al finalizar. No restaura el layout completo antiguo.

En Arch/CachyOS puede retirar también `omnia-desktop-suite-installer` con autorización de Polkit, sin desinstalar
sus dependencias. Si se cancela esa autorización, la interfaz informa que el asistente sigue instalado.
La instalación antigua de paquetes `omnia-core`, `omnia-ui`, `omnia-kde` debe retirarse desde el gestor de paquetes
antes de limpiar datos de usuario. El desinstalador no se ejecuta al actualizar el asistente.

### Revisión 23: reutilizar la selección del escáner y priorizar el lanzador Longshot

El instalador ya no vuelve a pedir los discos en el paso **Escritorio**: el monitor usa los discos marcados
en el escáner y los muestra como resumen. El catálogo distingue el wrapper oficial `rc/longshot` del binario
interno `rc/bin/longshot` y propone primero el wrapper, que delega en Longshot Launcher con `--launch`.

### Revisión 22: escáner por disco, monitor múltiple y restauración de Omnia

La sección **Juegos y discos** permite marcar varios volúmenes montados y escanearlos antes de elegir carpetas
manualmente. El escaneo es de solo lectura hasta confirmar; usa el catálogo de ports y propone el ejecutable que
inicia el juego (para NX2navi, `ocarina`, no su script auxiliar). La revisión de candidatos ahora permite vincular
o desvincular entradas sin borrar archivos ni partidas. Los volúmenes seleccionados aparecen individualmente en
el monitor de Omnia.

**Monitor** conserva las estadísticas de componentes y muestra uso, temperatura y VRAM en la fila de GPU.
La sección **Escritorio** añade «Volver a aplicar el escritorio Omnia al iniciar sesión»: restaura wallpaper y
widget en las pantallas sin reemplazar el shell de Caelestia ni quitar otros widgets. La opción queda activada
por defecto al actualizar una instalación existente; se puede desactivar desde Ajustes.

### Revisión 21: selección de la GPU dedicada para MangoHud

El generador detecta los adaptadores PCI y prioriza una GPU dedicada sobre la integrada; cuando hay
varias dedicadas, usa la VRAM disponible para desempatar. Escribe `pci_dev` para que MangoHud use ese
adaptador de forma explícita, sin depender del orden de enumeración, y actualiza su etiqueta `gpu_text`.
Esta revisión elimina `gpu_list` de la configuración generada porque su índice podría contradecir el PCI.

### Revisión 20: etiquetas de CPU/GPU con los modelos detectados

El generador de `~/.config/omnia/MangoHud.conf` detecta el nombre del procesador desde `/proc/cpuinfo`
y los adaptadores gráficos con `lspci`, y los escribe en `cpu_text` y `gpu_text`. Así la superposición
muestra modelos como «Intel Core i9…» y «GeForce RTX 3050…» en vez de etiquetas genéricas. En actualizaciones
añade los nombres si la configuración previa aún no los tenía, conservando etiquetas personalizadas.

### Revisión 19: superposición MangoHud

Omnia instala MangoHud como dependencia. La configuración de `docs/MangoHud.conf` se copia por usuario
a `~/.config/omnia/MangoHud.conf` sin reemplazar el archivo global de MangoHud ni sobreescribir una
configuración previa de Omnia. Los juegos y ejecutables directos lanzados desde la biblioteca de Omnia
se envuelven con MangoHud; los accesos directos de juegos Vulkan del menú de aplicaciones reciben el
entorno de MangoHud. Steam, Lutris y Heroic delegan en clientes que ya suelen estar abiertos, así que
requieren su opción de lanzamiento correspondiente. En Steam: `MANGOHUD_CONFIGFILE=$HOME/.config/omnia/MangoHud.conf mangohud %command%`.
La pestaña **Ajustes → Monitor** permite activar o desactivar el HUD.

### Revisión 18: desvincular juegos y AppImage para CachyOS x86-64

`Omnia-Installer-0.1.0-18-x86_64.AppImage` incluye la acción **Desvincular de Omnia** en el menú
contextual de las entradas manuales. Omnia retira el juego y sus datos asociados sin borrar sus archivos.
También elimina el botón directo para agregar un ejecutable desde el layout; las carpetas se administran
desde la configuración.

### Revisión 16: actualización rápida para CachyOS x86-64

`Omnia-Installer-0.1.0-16-x86_64.AppImage` detecta una instalación existente y abre directamente
la validación de SteamGridDB y el resumen de actualización. Omite la selección de bibliotecas y disco,
no vuelve a importar juegos y conserva la configuración. La actualización reemplaza los componentes
de Omnia, actualiza la clave de arte solo si se introduce una clave validada y reinicia el servicio y Plasma.
Si no detecta una instalación, conserva el asistente completo de primera instalación.

### Revisión 15: AppImage para CachyOS x86-64

`Omnia-Installer-0.1.0-15-x86_64.AppImage` incluye la GUI Qt y sus plugins para Wayland y XCB.
El icono circular azul grisáceo está en `assets/branding/omnia-icon-bluegray.png`; se conserva el original.
La GUI restaura el entorno de bibliotecas del host antes de iniciar Python, CMake o Polkit. No se copia
la GUI con Qt del bundle a la instalación del usuario: se vuelve a compilar con Qt del destino.

Construcción local:

```sh
python3 packaging/distros/build_appimage.py \
  --appimagetool /ruta/appimagetool-x86_64.AppImage \
  --runtime /ruta/runtime-x86_64
```

Herramientas oficiales usadas: appimagetool 1.9.1 y type2-runtime 20251108. Los hashes de ambas se registran
en el manifiesto de salida, junto a la glibc del host; el archivo también tiene un checksum SHA-256.
Se necesita CMake, compilador C++, qmake6, Qt Widgets/Wayland/SVG y sus plugins para construirlo.
La GUI se puede abrir desde el AppImage antes de compilar el resto. La instalación de Omnia requiere
Plasma 6, Python >=3.11 y las dependencias ya descritas (se comprueban desde el asistente).

Este artefacto se compila en CachyOS para la máquina actual: no se anuncia compatibilidad universal con
distribuciones cuya glibc sea más antigua. Para distribuirlo ampliamente habría que compilar y probar
sobre una base compatible más antigua. Si no está disponible FUSE, se puede abrir con
`./Omnia-Installer-0.1.0-11-x86_64.AppImage --appimage-extract-and-run`.
