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

## Importar la biblioteca anterior (el prototipo «Estantería»)
Desde «＋ Añadir juego → Importar mi biblioteca anterior…» (aparece si se encuentra `library.json` en el disco de Bazzite o en
`~/.config/estanteria`). Primero muestra una **vista previa** (no escribe nada) y solo al aceptar añade los juegos nuevos.
- **Se importan** los ports y emuladores (Longshot, NX2navi, Savage Wind, TOTK Recomp, Gopher64 y sus ROM) como juegos manuales,
  con sus carpetas de partidas y de respaldos tal como estaban; las rutas `/var/home/<usuario>` pasan al home actual.
- Un juego con varios ports pasa a **un juego por port** («Ocarina of Time · Longshot»): la interfaz lanza un port por tarjeta.
- **Se omiten**, con el motivo a la vista: Steam y Lutris (los detecta Omnia sola), Heroic (aparecerá al abrir Heroic e
  importar sus juegos instalados), Hydra (no se importan carpetas de Hydra), GeForce NOW (aún sin soporte), y los ports sin
  lanzador o cuyo archivo ya no existe.
- Es idempotente: repetirlo no duplica nada. El servidor **recalcula** el plan al aplicar (no se fía del cliente).
- La API: `GET /import/find`, `GET /import/preview?path=…`, `POST /import/apply?path=…` (opcional `{"ids": [...]}`).
