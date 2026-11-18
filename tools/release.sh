#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cd "$ROOT" && python3 -c 'import pathlib,tomllib; print(tomllib.loads(pathlib.Path("pyproject.toml").read_text())["project"]["version"])')"
RELEASE="${OMNIA_PKGREL:-34}"
OUT="${1:-${TMPDIR:-/tmp}/omnia-release-$VERSION-$RELEASE}"
mkdir -p "$OUT"
cd "$ROOT"
OMNIA_PKGREL="$RELEASE" python3 packaging/distros/build.py --output "$OUT"
printf 'Versión: %s-%s\nArtefactos y SHA256SUMS: %s\n' "$VERSION" "$RELEASE" "$OUT"
