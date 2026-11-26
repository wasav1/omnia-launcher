#!/bin/sh
# Avisa (no bloquea) si hay cambios de código preparados sin tocar docs/CONTEXTO.md.
staged=$(git diff --cached --name-only)
[ -z "$staged" ] && exit 0
code=$(printf '%s\n' "$staged" | grep -E '^(core|ui|integrations|packaging|tools|plasma|kwin)/' | head -1)
doc=$(printf '%s\n' "$staged" | grep -x 'docs/CONTEXTO.md')
if [ -n "$code" ] && [ -z "$doc" ]; then
  echo "AVISO: hay cambios de código pero no actualizaste docs/CONTEXTO.md (registro de cambios)." >&2
fi
exit 0
