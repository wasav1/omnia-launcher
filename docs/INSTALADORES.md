# Instaladores de Omnia Desktop Suite

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
Las ediciones OSTree/inmutables (Bazzite, Kinoite y similares) requieren un flujo específico y se rechazan por ahora;
tener KDE Plasma por sí solo no garantiza que permitan instalar dependencias con dnf o escribir componentes de sesión.

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

Se publica QML_IMPORT_PATH en systemd de usuario antes de reiniciar Plasma y se guarda en
`~/.config/environment.d/60-omnia-qml.conf` para las siguientes sesiones. El script de sesión KDE
se mantiene para los procesos iniciados directamente desde Plasma.

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
