#!/usr/bin/env bash
# Construye los paquetes con makepkg a partir del árbol de trabajo actual (sin publicar nada ni instalar).
#   packaging/arch/build-local.sh            construye en /tmp/omnia-pkg y deja los .pkg.tar.zst allí
# Requiere: base-devel python-build python-installer python-wheel python-setuptools
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
VER="$(sed -n 's/^pkgver=//p' "$REPO/packaging/arch/PKGBUILD")"
OUT="${OMNIA_PKG_OUT:-/tmp/omnia-pkg}"
rm -rf "$OUT" && mkdir -p "$OUT"
cd "$REPO"
# tarball con lo versionado y lo nuevo no ignorado (incluye cambios sin commit), como lo haría una versión publicada
git ls-files -co --exclude-standard | grep -v '^legacy/' | while IFS= read -r file; do
  [[ ! -f "$file" ]] || printf '%s\n' "$file"
done | tar czf "$OUT/omnia-launcher-$VER.tar.gz" \
  --transform "s|^|omnia-launcher-$VER/|" -T -
sed -e "s|^source=.*|source=(\"omnia-launcher-$VER.tar.gz\")|" packaging/arch/PKGBUILD > "$OUT/PKGBUILD"
cd "$OUT" && makepkg -f --nocheck "$@"
ls -1 "$OUT"/*.pkg.tar.zst
