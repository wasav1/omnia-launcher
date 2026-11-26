#!/usr/bin/env bash
# Instala (o actualiza) el plugin «Panel de Omnia» en la barra de Dux. La versión anterior queda en ~/.config/dms/plugins-backup.
#   integrations/dux/install.sh           # copia el plugin y lo recarga en Dux si está en marcha
# Instala también la pestaña «Omnia» del dashboard. Después añade el widget «Panel de Omnia» a la barra en Ajustes de Dux → Barra (ya está si lo tenías).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/omnia-panel"
[ -d "$SRC" ] || SRC=/usr/share/omnia/dux/omnia-panel
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins/omnia-panel"
BACKUP="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins-backup"

if [ -d "$DEST" ]; then
    mkdir -p "$BACKUP"
    cp -a "$DEST" "$BACKUP/omnia-panel-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/
chmod +x "$DEST"/*.sh
echo "Plugin instalado en $DEST"
if command -v dms >/dev/null 2>&1 && dms ipc call plugins reload omniaPanel >/dev/null 2>&1; then
    echo "Plugin recargado en Dux."
else
    echo "Reinicia Dux para ver los cambios."
fi
echo "Si es la primera vez (o el plugin gana archivos nuevos), reinicia Dux con «dms restart»: solo lee los archivos nuevos de un plugin al arrancar."
