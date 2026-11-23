# Qué esperamos de un port para entrar al catálogo de Omnia

Basado en «Recomp Standards» del SDK de RecompLauncher (MIT, https://github.com/elripalda/RecompLauncher-SDK) y en las revisiones de seguridad de
RecompStore; adaptado a lo que Omnia puede comprobar. Lo que bloquea un paquete está marcado **(bloquea)**; el resto son avisos.

## Seguridad (`tools/release-packages/build_packages.py`, backend)
- **Sin datos del juego (bloquea):** ni en el nombre del archivo ni, con `--deep`, dentro del zip/tar: ROMs, discos, paquetes de consola (`.nsp`, `.xci`, `.nup`,
  `.iso`, `.rvz`, `.z64`…), `baserom*`, `prod.keys` o archivos de más de 1,5 GB. `--allow-game-data` solo tras revisarlo a mano.
- **VirusTotal por hash** (`VT_API_KEY`; solo se consulta el SHA-256, no se sube nada). ≥ 3 motores lo marcan: **bloquea**; 1–2: aviso (suele ser un falso positivo).
- Siempre HTTPS desde la release del desarrollador (GitHub), con SHA-256 verificado por Omnia antes de instalar y extracción segura.
- No se ejecuta nada del descriptor (`prepare` se ignora).

## Calidad de la release (avisos)
- Etiqueta con versión (`v1.2.0`) y archivos adjuntos a la release, no solo en Actions.
- Nombre del archivo con versión, sistema y arquitectura (`juego-1.2.0-linux-x86_64.AppImage`).
- Notas de la release, aunque sea una línea.
- Un único programa que el jugador inicia; sin descargas al primer arranque sin preguntar; settings en archivo legible; logs en un sitio conocido; sin permisos de administrador.

## Descriptor `recomplauncher.json` (lo que Omnia lee de un port instalado; ver `core/omnia/descriptor.py`)
| Campo | Qué hace Omnia con él |
|---|---|
| `start.args` | argumentos de lanzamiento (`--play {install}/Longshot`) |
| `saves` | respaldo de partidas automático (si el usuario no eligió otras carpetas) |
| `inputs[].check.nup_build_id` | dice si la copia del jugador (carpeta `exefs`+`romfs`) es la versión que acepta el port |
| `folders` + `actions` | botones «abrir carpeta» (partidas, logs, carpeta del juego) en la ficha |
| `system.linux` | muestra los requisitos (glibc, Vulkan) y avisa si este PC no cumple el glibc |
| `exit_codes` | mensaje de la ficha cuando el juego se cierra con un código que el port explica |
Marcadores admitidos: `{install}` `{data}` `{local}` `{config}` `{home}` `{documents}`; `{input:…}` y `{pad}` se descartan.
Limitaciones: un `.nup` no se lee todavía (su build ID está dentro del paquete), así que la compatibilidad solo se comprueba con carpetas; `dumps`
(CRC32 de Redump), `settings`, `looks`, `mods` y los logros no se usan.
