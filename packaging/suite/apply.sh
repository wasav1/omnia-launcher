#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ $EUID == 0 ]]; then
  echo 'Ejecuta el instalador desde tu sesión de usuario.' >&2
  exit 1
fi
case ${XDG_CURRENT_DESKTOP:-} in
  *Hyprland*|*hyprland*) ;;
  *) [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || { echo 'Abre una sesión de Hyprland.' >&2; exit 1; } ;;
esac
[[ -x /usr/bin/pacman && -x /usr/bin/pkexec ]] || { echo 'Se necesitan pacman y Polkit.' >&2; exit 1; }
version=$(cat "$ROOT/version")
current=$(/usr/bin/pacman -Q omnia-app 2>/dev/null | cut -d ' ' -f 2 || true)
if [[ -n $current && $(/usr/bin/vercmp "$version" "$current") -lt 0 ]]; then
  echo "Ya tienes Omnia $current. Este instalador contiene $version." >&2
  exit 1
fi
legacy="$HOME/.config/systemd/user/omnia.service"
if [[ -e $legacy ]] && ! grep -qxF "ExecStart=$HOME/.local/bin/omnia-core" "$legacy"; then
  echo 'Hay una unidad omnia.service personalizada. Revísala antes de migrar.' >&2
  exit 1
fi
/usr/bin/pkexec /usr/bin/pacman -U --noconfirm "$ROOT"/packages/*.pkg.tar.zst
vars=()
for v in DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS; do
  [[ -v "$v" ]] && vars+=("$v")
done
if ((${#vars[@]})); then systemctl --user import-environment "${vars[@]}"; fi
if [[ -f $legacy ]]; then
  mv -- "$legacy" "$legacy.pre-suite-$(date +%Y%m%d-%H%M%S)"
fi
systemctl --user daemon-reload
systemctl --user reenable omnia.service
systemctl --user restart omnia.service
if [[ ${1:-} == dux ]]; then
  /usr/share/omnia/dux/install.sh
fi
/usr/bin/python3 "$ROOT/setup-library.py" "${2:-}" "${3:-}" "${4:-}"
