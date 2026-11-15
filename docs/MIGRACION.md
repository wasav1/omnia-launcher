# Omnia — mapa de migración (Bazzite → CachyOS)

Origen: `legacy/scripts/helper.py` (1651 líneas, un solo archivo) y los plasmoides `org.wsaenz.*`.
`legacy/` es solo referencia: no se edita, se porta pieza por pieza a `core/` y `plasmoid/`.

## Módulos del núcleo (de dónde sale cada uno)

| Módulo nuevo (`core/omnia/`) | Líneas en helper.py | Qué contiene |
|---|---|---|
| `paths.py` | 18-26 | Rutas XDG (`~/.config/omnia`, `~/.local/share/omnia`), sin `/var/home` |
| `store.py` | 40-76, 988 | JSON atómico, biblioteca, estado |
| `games/` (plugins) | 178-260, 594-686, 729 | Detectores: steam, heroic, lutris, hydra, gfn, roms. Contrato: `detect()`, `launch()`, `is_installed()` |
| `saves.py` | 77-120, 338-388 | Partidas, respaldos, abrir carpeta |
| `art.py` | 136-175, 389-587 | SteamGridDB (clave del usuario, permisos 600) |
| `gamemode.py` | 774-892 | Congelar apps, perfil de energía, Glass |
| `pad.py` | 943-1134 | Mando (evdev/SDL en vez de `/dev/input/js0`) |
| `audio.py` | 686-728, 1135-1217 | pactl/parec, niveles y bandas |
| `system.py` | 893-942, 1218-1250 | Monitor, discos, estadísticas |
| `apps.py` | 1251-1354 | Big Menu: apps vía XDG/Gio, favoritos |
| `desktop_kde.py` | 262-310, 1386-1473 | Panel, tinte/Glass, energía, entorno gráfico (módulo solo KDE) |
| `api.py` | 1474-1651 | Servidor HTTP/socket y rutas |

## Hallazgos del código actual a corregir

1. **API sin autenticación y con acciones por GET** (`do_POST = do_GET`, línea 1622). Rutas como
   `/power?a=poweroff`, `/launch`, `/gamemode`, `/tint` y `/art/pick?url=` se pueden disparar desde
   cualquier página web abierta en el navegador (una petición `fetch` a `127.0.0.1:47831` no necesita
   permisos). Corrección **hecha** en `core/omnia/api.py` + `security.py`: token por sesión en
   `$XDG_RUNTIME_DIR/omnia/token` (0600), validación de `Host`, acciones solo por POST, sin CORS, y el
   comando de lanzamiento sale de la biblioteca, nunca de la petición. (Se descartó el socket Unix: QML
   no puede conectarse a uno; el plasmoide leerá el token del archivo con `QML_XHR_ALLOW_FILE_READ=1`.)
   Pendiente: `/art/pick` con lista blanca de dominios (hoy descarga cualquier URL).
2. **`/log` y `/emit`** aceptan texto arbitrario y escriben en el journal: limitar.
3. **Rutas fijas** (`/var/home`, `~/.config/estanteria`, `~/.config/steamgriddb.key`) → XDG.
4. **Id de panel `TOP_PANEL = 218`** (línea 1408): cambia en cada instalación. Hay que detectarlo.
5. **Acoplamiento a Bazzite**: `distrobox-host-exec`, `flatpak run` de Gopher64 y rutas del Flatpak.
6. **Un solo archivo con 10 hilos** sin apagado limpio: pasar a módulos con arranque/parada ordenados.

## Lecciones del proyecto (no repetir errores)

- plasmashell **cachea el QML**: tras editar, `kquitapp6 plasmashell; kstart plasmashell`.
- La tecla Windows no funciona con `ModifierOnlyShortcuts` propio: usar `X-Plasma-Provides:
  ["org.kde.plasma.launchermenu"]` + `Plasmoid.onActivated`.
- El desenfoque real viene de efectos de KWin compilados (Glass, Better Blur DX); `PlasmaCore.Dialog` con
  `NoBackground` **no** se desenfoca. Hay que recompilar tras cada actualización de KWin.
- Con ~300 juegos: tarjetas virtualizadas (Loader ±9), fondos en Loader, y pausar animaciones cuando
  hay una ventana maximizada encima.
- Plasma Login Manager (6.8) no admite temas QML; revisar qué gestor trae CachyOS antes de diseñar el login.
- La capa `layer-shell` de fondo ya funcionó en Plasma 6.8.2 (la misma versión que hay ahora en CachyOS).

## Estado

- [x] Repo creado y código vivo copiado (sin `.bak`, sin arte, sin datos del usuario).
- [ ] Núcleo portado a `core/omnia/` con pruebas.
- [ ] API segura.
- [ ] Plasmoide renombrado (`org.wsaenz.*` → `org.omnia.*`) y probado en CachyOS.
- [ ] Paquetes `PKGBUILD`.
- [ ] Decisiones abiertas: licencia, nombre definitivo, gestor de login.

## Datos del usuario (fuera del repo)

`library.json`, `state.json`, `config.json` y el arte viven en `/mnt/bazzite/home/wsaenz/` y **no** se copian
al repo. Se importarán a `~/.config/omnia` cuando el núcleo nuevo exista.
