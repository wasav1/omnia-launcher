# Prueba: app QML independiente en la capa de fondo (CachyOS, Plasma/KWin 6.8.2)

Código: `ui/spike/` (`spike-layer.qml`, `SpikeContent.qml`). Se ejecuta con `qml6`.

## Cómo se ejecuta
    QT_WAYLAND_SHELL_INTEGRATION=layer-shell QML_XHR_ALLOW_FILE_READ=1 \
      qml6 ui/spike/spike-layer.qml -- --token $XDG_RUNTIME_DIR/omnia/token --auto [--top|--bottom]
`QT_WAYLAND_SHELL_INTEGRATION=layer-shell` es obligatoria: sin ella Qt crea una ventana normal y la prueba engaña.

## Resultados
| Punto | Resultado |
|---|---|
| KWin ofrece `zwlr_layer_shell_v1` | Sí (v5) |
| La app crea la superficie y KWin la configura a 1920×1080 | Sí |
| Orden de apilado (script de KWin) | escritorio de plasmashell (0) < app (1) < ventanas normales < panel (dock) |
| Se ve sobre el wallpaper y bajo el panel | Sí (captura con las demás ventanas minimizadas) |
| La app lee el token y llama a la API | Sí (5 juegos) |
| Tapa los iconos/widgets del escritorio de Plasma | Sí (como en el prototipo) |
| Sobrevive a «Mostrar escritorio» de KWin | **No**: KWin oculta toda superficie layer-shell externa, incluso en la capa `top`; una regla de tipo «Escritorio» no se aplica a layer-shell |
| Clic con el ratón en la capa | Sí (el usuario pulsó «Probar API» y apareció la lista de juegos) |
| Teclado (← → Enter F) y botón «Jugar» en la capa de fondo con `omnia-ui` | Sí (verificado por el usuario; hay que hacer clic una vez en el escritorio para dar el foco) |
| Win+D con el atajo de Omnia (Meta+D reasignado por D-Bus) | Sí (verificado por el usuario) |
| Saber qué ventanas hay abiertas desde fuera | Viable con un script de KWin (`workspace.stackingOrder`); sin implementar |

## Solución a Win+D: `kwin/omnia-showdesktop`
La API de scripting de KWin 6.8 no expone `workspace.showingDesktop` ni su señal, así que no se puede interceptar el modo
nativo. El script registra un atajo propio («Omnia: mostrar escritorio») que minimiza las ventanas normales (las que no
tienen `skipTaskbar`, como la capa de Omnia) y las restaura al repetirlo. Verificado invocando el atajo: 3 ventanas
minimizadas con la estantería visible, y restauradas a la segunda vez.
Para usarlo con Win+D hay que quitar Meta+D del «Show Desktop» de KWin y asignárselo al atajo de Omnia (Ajustes → Atajos).
El botón «Mostrar escritorio» del panel y las esquinas activas siguen usando el modo nativo y ocultarían la estantería.

Reasignar Meta+D por programa: `org.kde.KGlobalAccel.setForeignShortcut(actionId, keys)` sobre
`['kwin','Show Desktop','KWin','Dar un vistazo al escritorio']` con `[]` (Meta+D = 268435524 = Qt::META|Qt::Key_D).
El valor original se guarda en `~/.config/omnia/setup-backup.json` para poder deshacerlo.

Atajo de prueba: `ui/spike/run.sh [clic|auto|ventana]`. Los argumentos de la app van tras `--` (`qml6 f.qml -- --token X`).

## Pendiente
1. Mando sobre la capa de fondo (ratón y teclado ya funcionan).
2. Script de KWin que avise a omnia-core de ventanas maximizadas o a pantalla completa.
