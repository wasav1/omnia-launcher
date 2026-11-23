#!/usr/bin/env bash
# Núcleo de Omnia AISLADO para pruebas del panel: biblioteca falsa con N juegos y 0–3 jugados recientemente.
# No usa ~/.config/omnia ni el servicio omnia.service: puerto propio, carpetas temporales y token propio.
# Uso: ./test-core.sh [juegos=30] [jugados=3] [puerto=47900]     Imprime el token y el puerto; Ctrl+C para parar.
set -euo pipefail
N="${1:-30}"; PLAYED="${2:-3}"; PORT="${3:-47900}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/omnia-core-test.XXXXXX")"
trap 'kill $CORE 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/cfg/omnia" "$T/data" "$T/cache" "$T/state" "$T/run"
python3 - "$T" "$N" "$PLAYED" <<'PY'
import json, sys, time
t, n, played = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
games = [{"id": f"test-{i:02d}", "name": f"Juego de prueba {i:02d}", "src": "Prueba", "platform": ["pc", "sw1", "sw2", "n64"][i % 4],
          "sub": "", "s": "Juego falso para probar el panel.", "chips": [], "pal": ["#10150f", "#1f3328", "#18271f", "#0d1510", "#6fc3c9"],
          "acc": "#6fc3c9", "added": int(time.time()) - i * 86400, "ports": [{"id": f"p{i}", "name": "Prueba", "launch": ["true"], "check": "/tmp", "proc": ""}]}
         for i in range(n)]
json.dump({"games": games}, open(f"{t}/cfg/omnia/library.json", "w"))
now = int(time.time())
json.dump({"last_played": {f"test-{i:02d}": now - 3600 * (i + 1) for i in range(min(played, n))}}, open(f"{t}/cfg/omnia/state.json", "w"))
PY
export XDG_CONFIG_HOME="$T/cfg" XDG_DATA_HOME="$T/data" XDG_CACHE_HOME="$T/cache" XDG_STATE_HOME="$T/state" XDG_RUNTIME_DIR="$T/run"
PYTHONPATH="$REPO/core" python3 -m omnia.service --port "$PORT" --refresh 3600 > "$T/core.log" 2>&1 &
CORE=$!
for _ in $(seq 1 50); do [ -s "$T/run/omnia/token" ] && break; sleep 0.2; done
echo "puerto=$PORT token=$T/run/omnia/token"
wait $CORE
