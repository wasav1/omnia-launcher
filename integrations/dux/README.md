# Omnia en Dux (Dux Modular Shell)

Plugin **`omnia-panel`** (composite: botón de barra + pestaña del dashboard), con el mismo mecanismo que usan otros plugins de Dux:

- **Botón de la barra** (`OmniaPanelWidget.qml`): icono del mando y, con un mando conectado, su nombre y su batería
  (`Xbox ▮ 100 %`; naranja ≤30 %, rojo ≤10 %, verde al cargar). Un clic abre la pestaña «Omnia» anclada al botón.
  Lee `GET /pad` del núcleo de Omnia cada 5 s con `pad-status.sh`; si el sistema no da batería, solo enseña el nombre.
- **Pestaña «Omnia» del dashboard** (`OmniaDashboard.qml`): el panel rápido con el estilo, los colores y la animación de Dux (igual que
  la pestaña de ASUS TUF): a la izquierda **lo último que jugaste, anclado** (banner, tiempo jugado, última vez, Jugar, favorito,
  detalles y carpeta); a la derecha una lista con scroll de **máximo 10 juegos: favoritos primero y después los jugados más recientes**
  (cada fila con favorito y Jugar; tocar el nombre abre sus detalles en la app); el buscador mira toda la biblioteca; y el mando con su batería. Habla con el núcleo de Omnia por HTTP local con el token de sesión
  (`$XDG_RUNTIME_DIR/omnia/token`); no depende de illogical-impulse ni de otra instancia de Quickshell.
- `toggle-omnia-panel.sh`: abre/cierra la pestaña desde un atajo de teclado (`dms ipc call dash toggle plugin_omniaPanel`).

Instalar o actualizar: `integrations/dux/install.sh` (o `/usr/share/omnia/dux/install.sh` con el paquete `omnia-hyprland`). Deja una copia
de la versión anterior en `~/.config/dms/plugins-backup`. Dux solo registra los archivos nuevos de un plugin al arrancar: la primera vez
ejecuta `dms restart`. Después, en Ajustes de Dux → Barra, añade «Panel de Omnia».

Limitaciones: la pestaña no navega con el mando ni tiene la zona de activación por borde del panel de illogical-impulse (que sigue
funcionando con `omnia-hyprland` si usas esa configuración).

Requisitos: Dux (`dux-shell`) y el núcleo de Omnia en marcha.
