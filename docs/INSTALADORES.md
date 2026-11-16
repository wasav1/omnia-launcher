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
