# Omnia Desktop Suite

<img src="assets/branding/omnia-logo.png" alt="Logo de Omnia Desktop Suite" width="220">

Tu biblioteca de juegos en el escritorio de **KDE Plasma 6**: Omnia Launcher, wallpaper animado por juego,
monitor del sistema y ajustes generales en un solo proyecto.

**Versión preparada: 0.1.0 · Revisión de paquetes: 1 · Estado: experimental.**

> **Descargas pendientes de publicación.** Los enlaces siguientes están preparados para la release `v0.1.0`.
> Funcionarán cuando publiquemos esa release y adjuntemos los archivos. Hacer público el repositorio no los sube automáticamente.

## Instalador AppImage local

El instalador gráfico también se construye como **AppImage para CachyOS x86-64**, con el icono circular
azul grisáceo de Omnia y Qt incluido. La salida actual es `Omnia-Installer-0.1.0-12-x86_64.AppImage`.
Consulta [construcción y compatibilidad del AppImage](docs/INSTALADORES.md). Es un artefacto local;
no se ha adjuntado todavía a una release de GitHub.

## Descargar e instalar

Elige el archivo para tu distribución. Todos incluyen el mismo asistente gráfico.

| Distribución de destino | Descargar | Versión / revisión | Estado de instalación |
| --- | --- | --- | --- |
| Debian 13; Ubuntu/Kubuntu con Plasma 6 y Qt compatible | [Instalador .deb](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/omnia-desktop-suite-installer_0.1.0-1_all.deb) | 0.1.0 / 1 | Pendiente de prueba en destino |
| Arch Linux, CachyOS y EndeavourOS con dependencias compatibles | [Instalador .pkg.tar.zst](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/omnia-desktop-suite-installer-0.1.0-1-any.pkg.tar.zst) | 0.1.0 / 1 | Formato verificado; instalación del paquete pendiente |
| Fedora KDE y derivados tradicionales compatibles | [Instalador .rpm para Fedora](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/omnia-desktop-suite-installer-0.1.0-1.fedora.noarch.rpm) | 0.1.0 / 1 | Pendiente de prueba en destino |
| openSUSE Tumbleweed con KDE Plasma 6 | [Instalador .rpm para openSUSE](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/omnia-desktop-suite-installer-0.1.0-1.opensuse.noarch.rpm) | 0.1.0 / 1 | Pendiente de prueba en destino |
| Familias anteriores, con las dependencias disponibles | [Instalador gráfico portable .run](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/Omnia-Desktop-Suite-0.1.0-source.run) | 0.1.0 | Variante basada en fuentes; validación entre distros pendiente |

También disponibles: [fuentes del asistente](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/omnia-desktop-suite-installer-0.1.0-sources.tar.gz),
[checksums SHA256](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/SHA256SUMS) y
[manifiesto de la versión](https://github.com/wasav1/omnia-launcher/releases/download/v0.1.0/manifest.json).

Los formatos y contenidos de estos paquetes se verificaron localmente. El flujo universal de Omnia se ha usado en
CachyOS; eso todavía no confirma la instalación completa de los nuevos paquetes en las demás distros.
Los paquetes locales de esta versión aún no están firmados.

### Requisitos y compatibilidad

- Sesión **KDE Plasma 6**, **Qt ≥ 6.6** y **Python ≥ 3.11**.
- **systemd de usuario** activo y las dependencias disponibles en los repositorios de tu distribución.
- Herramientas de compilación Qt/C++; el asistente compila los componentes con la versión de Qt de tu sistema.
- Conexión a Internet para descargar dependencias y, opcionalmente, arte de SteamGridDB.

Tener KDE Plasma no basta si la versión de Qt o la distribución no cumplen los requisitos. Plasma 5 y las ediciones
OSTree/inmutables como Bazzite o Fedora Kinoite no están cubiertos por estos instaladores todavía.

Los paquetes son `all`, `any` o `noarch` porque distribuyen **fuentes**, no binarios Qt de CachyOS. Eso no garantiza
compatibilidad con cualquier arquitectura: los componentes y sus dependencias deben poder compilarse en el equipo.
Omnia instala su wallpaper animado y el widget de biblioteca. No instala ni cambia el tema, los paneles, la decoración
de ventanas ni la paleta global de Plasma; conserva la configuración visual que ya tenga el usuario.

### Instalar el asistente

Puedes abrir el paquete con el gestor gráfico de software si tu distribución lo admite, o usar el comando correspondiente
**desde la carpeta donde lo descargaste**:

```sh
# Debian / Ubuntu / Kubuntu compatibles
sudo apt install ./omnia-desktop-suite-installer_0.1.0-1_all.deb

# Arch Linux / CachyOS / EndeavourOS
sudo pacman -U ./omnia-desktop-suite-installer-0.1.0-1-any.pkg.tar.zst

# Fedora KDE
sudo dnf install ./omnia-desktop-suite-installer-0.1.0-1.fedora.noarch.rpm

# openSUSE Tumbleweed
sudo zypper install ./omnia-desktop-suite-installer-0.1.0-1.opensuse.noarch.rpm
```

Después abre **Omnia Desktop Suite — Instalar o actualizar** desde el menú de aplicaciones de Plasma,
**como usuario normal, sin sudo**. Instalar el paquete coloca el asistente en el sistema; el escritorio de Omnia
se configura después, en tu usuario y con tu aceptación.

Para el `.run`, activa **Propiedades → Permisos → Es ejecutable** y ábrelo con doble clic si tu gestor de archivos
lo permite. También puedes ejecutarlo así, sin sudo:

```sh
chmod +x Omnia-Desktop-Suite-0.1.0-source.run
./Omnia-Desktop-Suite-0.1.0-source.run
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
