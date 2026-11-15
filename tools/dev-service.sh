#!/usr/bin/env bash
# Servicio de desarrollo: corre omnia-core desde este repo como servicio de usuario (sin instalar nada en /usr).
#   tools/dev-service.sh install     crea y arranca omnia-dev.service
#   tools/dev-service.sh uninstall   lo detiene y lo borra
#   tools/dev-service.sh status      estado y últimas líneas del journal
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNIT="$HOME/.config/systemd/user/omnia-dev.service"
case "${1:-}" in
  install)
    mkdir -p "$(dirname "$UNIT")"
    cat > "$UNIT" <<UNITEOF
[Unit]
Description=Omnia (desarrollo, desde $REPO)

[Service]
Environment=PYTHONPATH=$REPO/core
ExecStart=/usr/bin/python3 -m omnia.service
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNITEOF
    systemctl --user daemon-reload
    systemctl --user enable --now omnia-dev.service
    ;;
  uninstall)
    systemctl --user disable --now omnia-dev.service 2>/dev/null || true
    rm -f "$UNIT"
    systemctl --user daemon-reload
    ;;
  status)
    systemctl --user status omnia-dev.service --no-pager || true
    journalctl --user -u omnia-dev.service -n 15 --no-pager
    ;;
  *) echo "uso: $0 install|uninstall|status" >&2; exit 2 ;;
esac
