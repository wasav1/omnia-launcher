# Omnia Desktop Suite

<img src="assets/branding/omnia-logo.png" alt="Logo de Omnia Desktop Suite" width="220">

Tu biblioteca de juegos en el escritorio de **KDE Plasma 6**: Omnia Launcher, wallpaper animado por juego,
monitor del sistema y ajustes generales en un solo proyecto.

**Omnia 0.2.0 · Revisión de paquetes 1 · Validado en KDE Plasma 6 sobre Bazzite.**

Esta versión renueva la ficha del juego, el monitor del sistema, el menú contextual y el asistente de instalación,
actualización, ajustes y desinstalación.

## Instaladores

El asistente se construye como **AppImage x86-64** con Qt e iconos incluidos. La salida local se llama
`Omnia-Installer-0.2.0-1-x86_64.AppImage`. El proyecto también permite generar paquetes de fuentes `.deb`,
`.pkg.tar.zst`, `.rpm` y un asistente portable `.run`.

Consulta la [guía de construcción y compatibilidad](docs/INSTALADORES.md) para generar el formato de tu distribución.
La validación en Bazzite corresponde al flujo AppImage.

### Requisitos y compatibilidad

- Sesión **KDE Plasma 6**, **Qt ≥ 6.6** y **Python ≥ 3.11**.
- **systemd de usuario** activo y las dependencias disponibles en los repositorios de tu distribución.
- Herramientas de compilación Qt/C++; el asistente compila los componentes con la versión de Qt de tu sistema.
- Conexión a Internet para descargar dependencias y, opcionalmente, arte de SteamGridDB.

Tener KDE Plasma no basta si la versión de Qt o la distribución no cumplen los requisitos. Plasma 5 no está cubierto.

**Bazzite / Fedora OSTree (Kinoite):** el asistente detecta el sistema inmutable y usa `rpm-ostree` para crear una capa
con las dependencias de compilación (Qt 6, CMake, PyGObject, etc.). Omnia se instala siempre en `~/.local`; no se
modifica `/usr`. Si `rpm-ostree` no admite `--apply-live`, será necesario reiniciar para que la capa esté activa antes
de compilar los componentes QML. Consulta [instalación en Bazzite](docs/INSTALADORES.md#instalación-en-bazzite-ostree).

Los paquetes son `all`, `any` o `noarch` porque distribuyen **fuentes**, no binarios Qt de CachyOS. Eso no garantiza
compatibilidad con cualquier arquitectura: los componentes y sus dependencias deben poder compilarse en el equipo.
Omnia instala su wallpaper animado y el widget de biblioteca. No instala ni cambia el tema, los paneles, la decoración
de ventanas ni la paleta global de Plasma; conserva la configuración visual que ya tenga el usuario.

### Instalar el asistente

Puedes abrir el paquete con el gestor gráfico de software si tu distribución lo admite, o usar el comando correspondiente
**desde la carpeta donde lo descargaste**:

```sh
# Debian / Ubuntu / Kubuntu compatibles
sudo apt install ./omnia-desktop-suite-installer_0.2.0-1_all.deb

# Arch Linux / CachyOS / EndeavourOS
sudo pacman -U ./omnia-desktop-suite-installer-0.2.0-1-any.pkg.tar.zst

# Fedora KDE
sudo dnf install ./omnia-desktop-suite-installer-0.2.0-1.fedora.noarch.rpm

# openSUSE Tumbleweed
sudo zypper install ./omnia-desktop-suite-installer-0.2.0-1.opensuse.noarch.rpm
```

Después abre **Omnia Desktop Suite — Instalar o actualizar** desde el menú de aplicaciones de Plasma,
**como usuario normal, sin sudo**. Instalar el paquete coloca el asistente en el sistema; el escritorio de Omnia
se configura después, en tu usuario y con tu aceptación.

Para el `.run`, activa **Propiedades → Permisos → Es ejecutable** y ábrelo con doble clic si tu gestor de archivos
lo permite. También puedes ejecutarlo así, sin sudo:

```sh
chmod +x Omnia-Desktop-Suite-0.2.0-source.run
./Omnia-Desktop-Suite-0.2.0-source.run
```

### Configurar Omnia

El asistente permite:

1. Leer y aceptar los cambios que realizará en la sesión.
2. Revisar las rutas ya vinculadas o agregar nuevas ubicaciones; Steam se detecta por sus bibliotecas registradas.
3. Revisar los candidatos encontrados y seleccionar cuáles agregar, indicando ejecutable o emulador cuando haga falta.
4. Elegir el volumen que aparecerá en el monitor del sistema con su nombre real.
5. Comprobar la conexión guardada con SteamGridDB o introducir una clave nueva; el arte es opcional.
6. Confirmar la instalación. Plasma se reinicia al aplicar el escritorio y sus paneles pueden desaparecer unos segundos.

La contraseña de administración, si hacen falta dependencias, la solicita **KDE/Polkit**. Omnia no recibe ni guarda esa
contraseña. La clave de SteamGridDB se conserva localmente con permisos privados.

Después puedes modificar la configuración desde el engranaje de Omnia o **Omnia — Ajustes generales** en el menú de
Plasma. Quitar una ruta excluye sus juegos del catálogo sin borrar archivos, partidas ni historial; reañadirla recupera
sus entradas. Los candidatos sin marcar no se importan.

[Guía completa de instaladores y construcción](docs/INSTALADORES.md).

## Desarrollo

Omnia Desktop Suite es un desarrollo desde cero para KDE Plasma 6. El proyecto reúne el launcher,
el wallpaper animado, los widgets y la integración con el escritorio en un mismo repositorio.

```text
core/        núcleo Python: biblioteca, detectores, API local y servicios
ui/          interfaz QML del launcher
plasma/      wallpaper, widget nativo y puente de sesión para Plasma 6
kwin/        scripts de integración con el escritorio
assets/      logo y recursos visuales
packaging/   asistente gráfico y construcción de paquetes por distribución
tests/       pruebas con datos de ejemplo
```

Los archivos de descarga se adjuntan a **GitHub Releases**, no se guardan como binarios dentro del repositorio.
Para preparar los paquetes consulta `packaging/distros/build.py`; su salida incluye los nombres de archivo usados arriba,
`SHA256SUMS` y `manifest.json`. Al publicar otra versión se deben actualizar el tag, los nombres y el estado de pruebas
en esta tabla para que cada enlace corresponda al paquete anunciado.

## Licencia

El código original de Omnia se distribuye bajo [GPL-3.0-or-later](LICENSE).
Los recursos de terceros conservan sus licencias, incluidas las [tipografías](assets/fonts/README.md),
los [iconos Lucide](ui/qml/images/lucide/LICENSE) y las [indicaciones de mando de Kenney](ui/qml/images/pad/LICENSE-Kenney-CC0.txt).
