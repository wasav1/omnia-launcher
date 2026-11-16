#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_ONLY=0
if [[ "${1:-}" == --source-only ]]; then SOURCE_ONLY=1; shift; fi
OUT="${1:-$REPO/packaging/universal/out/omnia-kde.run}"
mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARCHIVE="$TMP/payload.tar.gz"
if ((!SOURCE_ONLY)); then
  cmake -S "$REPO/packaging/universal/gui" -B "$TMP/gui" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$TMP/gui" --parallel 2
fi
git -C "$REPO" ls-files -co --exclude-standard | grep -v -e '^legacy/' -e '^packaging/universal/out/' -e '^packaging/distros/out/' | while IFS= read -r file; do
  [[ ! -f "$REPO/$file" ]] || printf '%s\n' "$file"
done | tar cf "$TMP/payload.tar" -C "$REPO" -T -
if ((!SOURCE_ONLY)); then tar rf "$TMP/payload.tar" -C "$TMP/gui" omnia-installer; fi
gzip -c "$TMP/payload.tar" > "$ARCHIVE"
cat > "$OUT" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
SELF="$(readlink -f "$0")"
MARKER="#__OMNIA_PAYLOAD_BELOW__"
LINE="$(awk -v m="$MARKER" '$0==m {print NR+1; exit}' "$SELF")"
[[ -n "$LINE" ]] || { echo 'Omnia: archivo instalador dañado' >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tail -n +"$LINE" "$SELF" | tar xz -C "$TMP"
ROOT="$(find "$TMP" -type f -path '*/packaging/universal/install.sh' -print -quit | xargs -r dirname | xargs -r dirname | xargs -r dirname)"
[[ -n "$ROOT" && -f "$ROOT/packaging/universal/install.sh" ]] || { echo 'Omnia: no se pudo extraer el contenido' >&2; exit 1; }
if bash "$ROOT/packaging/universal/install.sh" "$@"; then exit 0; else status=$?; exit "$status"; fi
#__OMNIA_PAYLOAD_BELOW__
STUB
cat "$ARCHIVE" >> "$OUT"
chmod 755 "$OUT"
printf 'Instalador creado: %s\n' "$OUT"
