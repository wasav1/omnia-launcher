# Omnia en Dux (Dux Modular Shell)

Dos piezas:

1. **Plugin de barra `omnia-panel`** (`omnia-panel/`): el botón del mando en la barra de Dux. Abre el panel rápido de Omnia y, con un mando
   conectado, muestra su nombre y su batería (`Xbox ▮ 100 %`; naranja ≤30 %, rojo ≤10 %, verde al cargar). Lee `GET /pad` del núcleo de
   Omnia cada 5 s con `pad-status.sh`; si el sistema no da batería, solo enseña el nombre.
2. **Instancia del panel** (`omnia-dms-shell.qml`): una instancia mínima de Quickshell que carga solo `OmniaEdge` (el panel rápido), sin la
   barra ni el resto de la configuración «ii». La arranca `toggle-omnia-panel.sh` cuando hace falta (también con `Super+Shift+O`).

Instalar o actualizar: `integrations/dux/install.sh` (o `/usr/share/omnia/dux/install.sh` con el paquete `omnia-hyprland`). Deja una copia de la
versión anterior en `~/.config/dms/plugins-backup` y recarga el plugin en Dux. Después, en Ajustes de Dux → Barra, añade «Panel de Omnia».

Requisitos: Dux (`dux-shell`), Quickshell, el núcleo de Omnia en marcha y los módulos del panel de Hyprland (`omnia-hyprland`) en
`~/.config/quickshell/ii/modules/ii/omnia`.
