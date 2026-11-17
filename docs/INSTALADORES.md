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
