#!/usr/bin/env bash
# Estado del mando según el núcleo de Omnia (GET /pad): una línea JSON; sin núcleo o sin token imprime {"connected":false}.
token_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omnia/token"
[ -r "$token_file" ] || { echo '{"connected":false}'; exit 0; }
curl -s -m 2 -H "Authorization: Bearer $(cat "$token_file")" http://127.0.0.1:47831/pad || echo '{"connected":false}'
