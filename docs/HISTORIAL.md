# Historial de juego

Omnia anota cada partida de los juegos de la biblioteca: última vez, tiempo total y número de partidas. Todo vive en
`~/.config/omnia/state.json` (`sessions`, `last_played`, `history`) y la estantería se ordena por último jugado.

## Reglas
- Una sesión empieza tras 2 sondeos seguidos (cada ~2 s) con el juego en marcha y termina tras 3 sin verlo; la duración llega
  hasta la **última vez que se vio**, no hasta que se notó el cierre.
- Las sesiones de menos de 10 s no cuentan (lanzadores que abren y cierran).
- Un reinicio breve del juego (vuelve antes del tercer sondeo) sigue siendo la misma sesión.
- `history` guarda las últimas 200 sesiones: `{id, name, start, end, secs}`.

## Si el servicio se cae a mitad de una partida
La sesión en curso se anota cada 30 s en `active_sessions`. Al arrancar de nuevo se cierra con la última hora vista, así que
se pierden como mucho 30 s. Al parar el servicio con normalidad se cierra con la hora actual.

## Ficha
«Última vez hace 2 h · 5 h 33 min en total · 4 partidas», o «Jugando ahora · desde hace 12 min».

## Consultar el registro
`journalctl --user -u omnia.service | grep -E 'sesión|modo juego'`
