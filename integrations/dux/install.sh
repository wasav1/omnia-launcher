#!/usr/bin/env bash
# Instala (o actualiza) el plugin «Panel de Omnia» en la barra de Dux. La versión anterior queda en ~/.config/dms/plugins-backup.
#   integrations/dux/install.sh           # copia el plugin y lo recarga en Dux si está en marcha
# Después añade el widget «Panel de Omnia» a la barra en Ajustes de Dux → Barra (ya está si lo tenías).
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
# Instancia mínima de Quickshell que carga solo el panel (OmniaEdge); necesita los módulos de Omnia dentro de la configuración «ii».
II="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii"
if [ -d "$II/modules/ii/omnia" ]; then
    cp -a "$(dirname "$SRC")/omnia-dms-shell.qml" "$II/omnia-dms-shell.qml" 2>/dev/null || cp -a /usr/share/omnia/dux/omnia-dms-shell.qml "$II/omnia-dms-shell.qml"
    echo "Instancia del panel: $II/omnia-dms-shell.qml"
else
    echo "Aviso: no hay módulos de Omnia en $II; instala primero el panel de Hyprland (paquete omnia-hyprland) para que el botón pueda abrirlo."
fi
if command -v dms >/dev/null 2>&1 && dms ipc call plugins reload omniaPanel >/dev/null 2>&1; then
    echo "Plugin recargado en Dux."
else
    echo "Reinicia Dux (o desactiva y activa el plugin) para ver los cambios."
fi
