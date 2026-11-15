# Modo juego

Mientras un juego de la biblioteca está en marcha, Omnia:
1. **Congela** (SIGSTOP) los clientes de descargas en segundo plano de tu usuario.
2. **Sube el perfil de energía** a `performance` con power-profiles-daemon.
Al cerrar el juego reanuda lo congelado y suelta el perfil. Los juegos en la nube (`"cloud": true`) no lo activan.

## Cómo entra y sale
Sondea cada ~2 s: entra tras 2 sondeos con un juego en marcha y sale tras 3 sin ninguno, para no parpadear con lanzadores
que cierran y reabren procesos.

## Configuración (`~/.config/omnia/config.json`)
```json
{"game_mode": {"enabled": true, "profile": "performance",
               "freeze": ["qbittorrent", "transmission-gtk", "transmission-qt", "deluge", "deluged", "aria2c"]}}
```
`freeze` son nombres **exactos** de proceso (el campo «comm» de `/proc`); solo se tocan procesos de tu usuario.
Para desactivarlo: `"enabled": false`.

## Si algo falla
- El perfil lo retiene la conexión de `omnia-core` al bus del sistema (`HoldProfile`): si el servicio muere, el sistema lo
  suelta solo. Verificado con `kill -9`.
- Lo congelado se anota en `~/.cache/omnia/gamemode.json` (pid + hora de arranque) y se reanuda al arrancar el servicio; un pid
  reutilizado por otro proceso no se toca.
- Sin PyGObject o sin power-profiles-daemon no hay cambio de perfil (se avisa en el registro), pero sí se congela.

## Detalle técnico que costó un error
La conexión al bus del sistema debe mantenerse viva mientras dure la retención (`self.conn`): GDBus cierra las conexiones
compartidas sin referencias y el demonio suelta el perfil al ver desaparecer a quien lo pidió.
