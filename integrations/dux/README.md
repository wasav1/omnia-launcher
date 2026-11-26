# Omnia en Dux (Dux Modular Shell)

Plugin **`omnia-panel`** (botón de la barra + popout):

- **Botón de la barra** (`OmniaPanelWidget.qml`): logo de Omnia en azul sólido. Abre el panel en barras horizontales y verticales.
- **Popout compacto** (`OmniaPanel.qml`, 400 px, una columna, anclado al botón): muestra el nombre del mando y su batería.
  Lee `GET /pad` cada 5 s mientras el panel está abierto. Si el sistema no informa el nivel, muestra «Batería no disponible».
  Incluye buscador, **lo último que jugaste anclado** (banner, Jugar, favorito, detalles y carpeta), una lista con
  scroll de **máximo 10 juegos: favoritos primero y después los jugados más recientes** (Jugar en cada fila; tocar el nombre abre sus
  detalles en la app), «y N más en tu biblioteca», y Big Mode y Descargas. El buscador mira toda la biblioteca. Habla con el núcleo de
  Omnia por HTTP local con el token de sesión (`$XDG_RUNTIME_DIR/omnia/token`); no depende de illogical-impulse.
- **Atajo de teclado:** `toggle-omnia-panel.sh` (`dms ipc call omniaPanel toggle`), p. ej. `Super+Shift+O`. Dux no ofrece IPC para abrir
  popouts de plugins, así que el plugin registra el suyo.

Instalar o actualizar: `integrations/dux/install.sh` (o `/usr/share/omnia/dux/install.sh` con el paquete `omnia-hyprland`). Deja una copia
de la versión anterior en `~/.config/dms/plugins-backup`. Dux solo registra los archivos nuevos de un plugin al arrancar: la primera vez
ejecuta `dms restart`. Después, en Ajustes de Dux → Barra, añade «Panel de Omnia».

Limitaciones: el popout no navega con el mando ni tiene la zona de activación por borde del panel de illogical-impulse (que sigue
funcionando con `omnia-hyprland` si usas esa configuración).

Requisitos: Dux (`dux-shell`) y el núcleo de Omnia en marcha.
