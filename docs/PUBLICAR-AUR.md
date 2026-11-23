# Publicar Omnia en el AUR

Fecha: 2026-11-23. Estado: **listo para preparar; faltan pasos que solo puedes hacer tú** (repo público, cuenta AUR, clave SSH).

## Comprobado hoy
- Nombres libres en el AUR: `omnia-launcher`, `omnia-core`, `omnia-app`, `omnia-hyprland` y `omnia-kde` no existen (sí hay un `omnia` ajeno: un REPL de Clojure; no colisiona).
- `packaging/arch/PKGBUILD` es de varios paquetes (`pkgbase=omnia-launcher`); el AUR admite un repositorio por `pkgbase` con todos los `pkgname`.
- Licencia: `LICENSE` del repo es GPLv3 y el PKGBUILD declara `GPL-3.0-or-later` (ya sin la nota «decisión abierta»).
- Compila y se instala en local (`OMNIA_PKGREL=N packaging/arch/build-local.sh`, 0.2.1-50 probado en tu equipo).

## Falta (en este orden)
1. **Hacer público `github.com/wasav1/omnia-launcher`.** El AUR descarga `…/archive/v$pkgver.tar.gz`; con el repo privado `makepkg` falla para todos.
   Antes de publicar: revisar que no haya secretos ni rutas personales en el historial (`git log -p | grep -iE "token|secret|password"`), y los `docs/` que quieras mantener.
2. **Etiquetar una versión nueva.** Las etiquetas existentes (`v0.2.0`, `v0.2.1`) son anteriores a todo el trabajo reciente (instalación de ports, aviso del mando…).
   Propuesta: subir `pkgver` a `0.3.0` en `PKGBUILD` y `pyproject.toml`, `git tag v0.3.0` y `git push --tags`.
3. **Preparar la carpeta del AUR:** `packaging/arch/prepare-aur.sh ../aur-omnia-launcher` hace los pasos 3 a 5 de una vez (comprueba la etiqueta, `updpkgsums`, `.SRCINFO`, `namcap`) y copia los archivos. Manualmente: **fijar el checksum.** En el directorio del PKGBUILD: `updpkgsums` (sustituye `sha256sums=('SKIP')`) y probar `makepkg -sf` en limpio
   (idealmente en un chroot: `extra-x86_64-build` de `devtools`).
4. **Revisar con `namcap`** (`sudo pacman -S namcap`; `namcap PKGBUILD *.pkg.tar.zst`) y corregir avisos de dependencias.
5. **Generar `.SRCINFO`:** `makepkg --printsrcinfo > .SRCINFO`.
6. **Cuenta y clave SSH en aur.archlinux.org**, luego:
   ```bash
   git clone ssh://aur@aur.archlinux.org/omnia-launcher.git aur-omnia-launcher
   cp packaging/arch/PKGBUILD .SRCINFO aur-omnia-launcher/ && cd aur-omnia-launcher
   git add PKGBUILD .SRCINFO && git commit -m "omnia-launcher 0.3.0" && git push
   ```
7. **Soporte:** al publicar, responderás comentarios y marcas de «desactualizado»; cada versión nueva repite 2–6.

## Riesgos y decisiones
- **Nombre «Omnia»:** hay otros proyectos con ese nombre; el repo se llama `omnia-launcher` y los paquetes `omnia-*`. Sin conflicto en el AUR, pero conviene un nombre de marca distinto si algún día se distribuye fuera de Arch.
- **`aarch64`** figura en `arch=`; solo se ha probado `x86_64`. Quitarlo si no se prueba.
- **Telemetría/red:** Omnia solo habla con su backend público y con las releases de GitHub de los ports (SHA-256 verificado); conviene decirlo en la descripción del AUR.
