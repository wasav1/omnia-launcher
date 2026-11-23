#!/usr/bin/env bash
# Prepara la carpeta de publicación del AUR (no sube nada). Uso, desde la raíz del repo y con la etiqueta vX.Y.Z ya publicada:
#   packaging/arch/prepare-aur.sh [DESTINO]          # DESTINO por defecto: ../aur-omnia-launcher
# Hace: comprueba que la etiqueta de pkgver existe en origin, fija el sha256 con updpkgsums, genera .SRCINFO y, si están
# instalados, ejecuta namcap sobre el PKGBUILD. Luego copia PKGBUILD y .SRCINFO a DESTINO (clon de ssh://aur@aur.archlinux.org/omnia-launcher.git).
set -euo pipefail
cd "$(dirname "$0")/../.."
dest="${1:-../aur-omnia-launcher}"
ver="$(sed -n 's/^pkgver=//p' packaging/arch/PKGBUILD | head -1)"
git ls-remote --exit-code --tags origin "refs/tags/v${ver}" >/dev/null || { echo "La etiqueta v${ver} no está en origin: crea y sube la etiqueta primero (git tag v${ver} && git push --tags)." >&2; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp packaging/arch/PKGBUILD "$work/"
( cd "$work" && sed -i 's/^pkgrel=.*/pkgrel=1/' PKGBUILD && updpkgsums && makepkg --printsrcinfo > .SRCINFO && { command -v namcap >/dev/null && namcap PKGBUILD || true; } )
[ -d "$dest" ] || { echo "No existe $dest: clónalo antes (git clone ssh://aur@aur.archlinux.org/omnia-launcher.git $dest)." >&2; exit 1; }
cp "$work/PKGBUILD" "$work/.SRCINFO" "$dest/"
echo "Listo en $dest. Revisa 'git diff' allí y haz commit + push al AUR."
