# Partidas, juegos manuales y explorador de carpetas

## Qué hace
- **Panel de partidas** de cada juego (botón «Partidas», tecla `P`, o `X` en el mando): dónde están, respaldar, restaurar,
  elegir la carpeta y abrirla. Muestra sugerencias de carpeta para confirmar con un clic.
- **Añadir juego** (botón «＋ Añadir juego», tecla `N`, o `SELECT` en el mando): ports, emuladores, juegos de Windows (umu) y
  nativos. Los manuales no los toca el refresco de los detectores, y tienen historial, modo juego y arte como los demás.
- **Explorador de carpetas** propio, manejable con mando. El núcleo solo deja mirar dentro del home y de los discos externos.

## Plantillas verificadas
- **Gopher64**: las partidas se llaman `NOMBRE-<SHA256 de la ROM>.*`; el hash se calcula también en los otros órdenes de
  bytes (v64, n64). Comprobado con 3 partidas reales (Mario Kart 64, Star Fox 64, Chameleon Twist).
- **Longshot**, **Hookshot**, **NX2navi**, **TOTK Recomp**: rutas de tu prototipo.
- **Savage Wind**: «ubicación sin comprobar» → no se afirma nada; se ofrecen candidatas dentro de su carpeta.
- **Steam/Proton**: sugerencias, nunca el prefijo entero: caché de Steam Cloud y carpetas de `AppData`/`Documents` cuyo nombre
  se parece al del juego (también `AppData/LocalLow/<Empresa>/<Juego>`).

## Respaldos
`.tar.gz` con manifiesto (`omnia-backup.json`) en `<carpeta de respaldos>/<Juego>-AAAAMMDD-HHMMSS.tar.gz`. Carpeta por defecto:
`~/Juegos/_Partidas/<Juego>` (se cambia con `saves.backup_root` en `config.json`, o por juego en el panel).
- Restaurar solo escribe dentro de las carpetas de partidas del juego, rechaza enlaces y rutas con `..`, **valida todo el
  respaldo antes de escribir** y guarda antes lo que había («…-antes-de-restaurar»).
- Los respaldos del prototipo (sin manifiesto) se listan pero no se restauran solos: ábrelos con el gestor de archivos.
- Un respaldo de más de 2 GiB se rechaza: casi seguro es una carpeta mal elegida.

## Dónde se guarda la configuración
Por juego, en `state.json` (`saves`), aparte de la biblioteca: sobrevive a que Steam, Heroic o Lutris la regeneren.
