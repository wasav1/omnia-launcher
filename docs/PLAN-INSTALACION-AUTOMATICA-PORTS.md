# Plan: detectar tu juego y ofrecer instalar su port

Fecha: 2026-11-23. Estado: **plan, nada implementado.** Idea tomada de cómo trabaja RecompLauncher (repos públicos
`elripalda/RecompLauncher`, GPL-3.0, y `elripalda/RecompLauncher-SDK`, MIT), sin copiar su código.

## 1. Objetivo y límites

Cuando Omnia detecte una ROM o una copia de un juego que tiene un port instalable, mostrar «Port disponible» y, con una
confirmación, descargarlo, verificarlo, instalarlo y dejar el juego listo para jugar.

- **Siempre con confirmación** del usuario y aceptación de la licencia. Nunca se instala en silencio: es código de terceros.
- Omnia **no incluye ni descarga ROMs**; el usuario aporta su copia, que solo se lee (cabecera / identificador).
- **Fase 1 no ejecuta pasos de preparación de terceros** (`prepare` de RecompLauncher). Los ports que lo necesiten quedan fuera al principio.
- El cliente sigue hablando **solo con el backend de Omnia** (catálogo y paquetes); la descarga final viene de la release del desarrollador, con SHA-256.

## 2. Qué existe ya en Omnia

| Pieza | Dónde | Estado |
|---|---|---|
| Detección de ROMs por cabecera/ID (N64, GC/Wii, discos PlayStation, Switch) | `core/omnia/roms.py` | hecho |
| Enlace ROM → ficha por identificador | `rom_identifier_index`, `link_roms_by_id` (`service.py`), tabla `game_rom_identifiers` | hecho |
| Fichas y módulos (ports) con `repositoryUrl` | backend, 1.642 fichas | hecho, módulos «planned» |
| Paquetes instalables verificados | backend `install_packages` + `core/omnia/package_installs.py` | infraestructura hecha; solo unos pocos paquetes de ejemplo |
| Descarga segura (HTTPS, IP públicas, SHA-256, extracción sin rutas fuera del destino, límites de tamaño) | `package_installs.py` | hecho |
| Plantillas de ports/emuladores conocidos y dónde guardan partidas | `core/omnia/templates.py` | hecho, a mano |
| Instalar desde Explorar (elegir paquete, licencia, destino) | app de escritorio | hecho |

**Lo que falta:** (a) datos: casi ningún port tiene paquete publicado; (b) el puente «ROM detectada → hay paquete → ofrecer instalar»;
(c) saber cómo arrancar el port con la ROM del usuario sin escribir una receta a mano por port.

## 3. Cómo lo resuelve RecompLauncher (resumen)

- Catálogo en su web (`recomplauncher.com`), alimentado por envíos con el repo de GitHub/GitLab/Forgejo.
- Instala **desde la release del propio desarrollador**; comprueba el SHA-256 que publica GitHub. Elige el archivo por el sistema y la CPU en el nombre
  (`Linux-x64`, `arm64`…) e ignora los que traen `debug`, `symbols`, `source`, `.sha256`, `.sig`.
- Cada port puede incluir `recomplauncher.json` (formato 1; esquema en el SDK) en la release, en el AppImage, en su entrada del catálogo o en el repo (Forgejo).
  Campos: `inputs` (qué copia pide y cómo comprobarla: `check` por `ids`, `iso9660`, `file`, `xdvdfs`, `nup_build_id`; `dumps` con hashes), `start` (programa y
  argumentos con `{input:game}`), `saves`, `settings`, `system`, `prepare`, `games`, `mods`…

## 4. Diseño propuesto

### 4.1 Backend: de «módulo con repo» a «paquete verificado» (herramienta + revisión humana)
Nueva herramienta `tools/release-packages/` en `omnia-backend`:
1. Para cada módulo elegido, lee la **última release** del repo (API de GitHub, con caché y con token de lectura solo en el equipo del mantenedor).
2. Selecciona el archivo para Linux x86_64 con reglas de nombre (`Linux`, `x64`/`x86_64`, `.AppImage`, `.tar.*`, `.zip`; descarta `debug|symbols|source|\.sha256|\.sig`).
   Los nombres no son uniformes (hoy: `…-Linux-X64.zip`, `….appimage`, `…_SteamOS.zip`), así que **las reglas proponen y una persona confirma**.
3. Obtiene el **SHA-256**: el campo `digest` de GitHub si existe (la mayoría de las releases actuales); si falta (p. ej. Starship), la herramienta
   descarga el archivo una vez y lo calcula, y lo anota como «calculado por Omnia».
4. Si la release trae `recomplauncher.json`, lo valida contra el esquema (MIT, se vendoriza con atribución) y guarda un **descriptor de instalación**
   reducido (ver 4.2) junto al paquete. **Nunca se guardan comandos ni scripts.**
5. Crea el paquete como **borrador** por la API de administración existente (`POST /admin/games/:slug/install-packages`); se publica tras revisar.
   Reutiliza `install_packages` (`source_url`, `sha256`, `size_bytes`, `archive_format`, `entrypoint`, `install_subdir`, licencia).

Necesidad de esquema: una columna JSON `setup` en `install_packages` (migración 0007), validada con zod: `{ inputs[], start{program[],args[]}, saves[], system{} }`.

### 4.2 Subconjunto de `recomplauncher.json` que Omnia entiende (formato 1)
- `inputs[]`: `id`, `label`, `role` (`game`, `disc`, `dlc`, `update`), `formats` (`file` / `folder` + extensiones), `optional`, `check` limitado a
  `ids`, `iso9660`, `file`. (`xdvdfs`, `nup_build_id` y `dumps` en fase 2.)
- `start`: lista `program` (se usa el primero que exista) y `args` con `{input:<id>}`.
- `saves`: rutas de partidas (alimenta el gestor de partidas y evita pedirlas a mano).
- `system`: requisitos, solo informativos.
- **Ignorado a propósito:** `prepare`, `actions`, `exit_codes`, `mods`, `looks`, `settings` (fase 3 si hace falta).

### 4.3 Cliente: puente ROM → paquete
1. `roms.inspect_file` ya da el identificador (tipo + ID). `link_roms_by_id` ya enlaza con la ficha.
2. Nuevo: si la ficha tiene un paquete **publicado** y su `setup.inputs[].check.ids` contiene ese ID (o la ficha coincide por ROM identifier), el juego se marca
   `portAvailable: {packageId, title, version}` en `/library`.
3. Instalar usa `/installations/start` (ya existe). Al terminar, el núcleo **crea la entrada del juego** a partir del descriptor: busca `start.program` en la carpeta
   instalada, sustituye `{input:game}` por la ruta de la ROM del usuario y registra los `saves`. El port queda como un módulo más del juego.
4. Si no hay `check.ids` o la ROM no coincide, no se ofrece (no se adivina).

### 4.4 Interfaz (escritorio y BigMode)
- Etiqueta **«Port disponible»** en la tarjeta/ficha de la ROM, y acción en el menú contextual («Instalar port»).
- Diálogo de confirmación: paquete, versión, tamaño, fuente (GitHub), licencia con casilla de aceptación, destino. Manejable con mando.
- Progreso en Instalaciones (ya existe), y al terminar «Jugar» con el port.
- Estado «Actualización disponible» (fase 3): se compara la versión instalada con la última release publicada.

## 5. Seguridad y legal

- Sin ejecución de scripts de terceros en las fases 1 y 2. Los argumentos del descriptor se arman como lista (no por shell) y solo admiten `{input:id}`.
- Hosts de descarga con lista blanca (`github.com`, `objects.githubusercontent.com`, y los que admita `package_installs.py`); se rechazan redirecciones a otros.
- SHA-256 obligatorio; si no coincide, se descarta y se informa. Límites de tamaño ya vigentes (20 GiB paquete / 40 GiB expandido).
- Se respeta la licencia de cada port (se muestra y se acepta); la información de licencia sale del repo/paquete y se revisa al publicar.
- El usuario aporta su ROM; no se transmite ni se sube. La telemetría sigue sin existir.
- Revocación: el administrador puede retirar un paquete (`DELETE /admin/install-packages/:id`).

## 6. Riesgos conocidos

- **Linux no está garantizado:** RecompLauncher es sobre todo Windows/macOS. Algunos ports no publican build para Linux. Opciones: solo ofrecer los que lo tengan
  (fase 1) o instalar el build de Windows con Proton/umu (`kind: windows` ya existe; fase 4).
- **Nombres de assets irregulares:** de ahí la revisión humana de las reglas.
- **Releases sin `recomplauncher.json`:** el port se instala pero sin descriptor; el usuario elige el ejecutable (flujo actual) o se usa una plantilla de `templates.py`.
- **Repos que cambian de nombre o dejan de publicar** (p. ej. 2Ship devolvió una redirección permanente al consultarlo): el módulo debe guardar la URL canónica.
- **Límite de la API de GitHub sin token** (60 consultas/hora): por eso la consulta la hace la herramienta del mantenedor y el backend sirve el resultado cacheado.

## 7. Fases

| Fase | Entregable | Pruebas |
|---|---|---|
| **0 · Selección** | 5 ports iniciales con build de Linux y `digest`: candidatos verificados hoy en GitHub: `Zelda64Recomp/Zelda64Recomp` (zip Linux-X64/ARM64, con digest), `HarbourMasters/Shipwright` (AppImage, con digest), `coop-deluxe/sm64coopdx` (zip Linux, con digest), `HarbourMasters/Starship` (zip Linux, **sin digest**); más Longshot, que Omnia ya conoce. Revisar licencia de cada uno | script que lista assets y los clasifica |
| **1 · Backend** | `tools/release-packages/`, migración `setup`, esquema zod, 5 paquetes en borrador → publicados | pruebas de selección de asset y de validación del descriptor con releases simuladas |
| **2 · Núcleo** | `portAvailable` en `/library`, creación de la entrada del juego tras instalar, `saves` | pruebas con ROM de ejemplo (cabeceras sintéticas) y paquete falso |
| **3 · Interfaz** | etiqueta, menú contextual, diálogo de confirmación (ratón y mando), progreso, actualizaciones | capturas offscreen y revisión en pantalla |
| **4 · Ampliación** | más ports, `xdvdfs`/`nup_build_id`/`dumps`, builds de Windows con Proton, `prepare` aislado (si se decide) | según el caso |

## 8. Decisiones pendientes (del usuario)

1. ¿Empezamos solo con ports que tengan build de Linux, o también con el de Windows vía Proton?
2. ¿Qué 5 ports quieres primero? (la propuesta de la fase 0 es una base.)
3. ¿Se aprueba dejar `prepare` fuera hasta tener una forma de aislarlo?
4. ¿La herramienta de releases usa el token de GitHub del mantenedor (tú) en tu equipo?

## 9. Avance (2026-11-23): fase 0 y fase 1

Decisiones del usuario: solo ports con build de Linux, sin `prepare`, empezar por Zelda64Recomp, Shipwright, sm64coopdx y Starship.

**Hallazgos de la fase 0 (comprobados descargando los archivos)**
- Ninguna de las cuatro releases trae `recomplauncher.json`: los descriptores los redactamos nosotros (`tools/release-packages/ports.json`), solo con datos.
- Zelda64Recomp: el zip contiene **un único `.tar.gz`** con el ejecutable `Zelda64Recompiled` → el cliente debe descomprimir un archivo interno (fase 2).
- Shipwright: **un solo AppImage** (sin zip) → nuevo formato `appimage` (migración 0007). Guarda datos en `~/.local/share/soh`.
- sm64coopdx: zip con el ejecutable `sm64coopdx` (más `coopdx_updater`).
- Starship: zip con `starship.appimage`; **GitHub no publica checksum**, se calcula una vez (`85dd03d3…`).
- Los tres ports que piden la ROM la piden **ellos mismos al primer arranque** (no por argumento): Omnia solo mostrará tu ROM detectada como ayuda.
- **Licencias:** Zelda64Recomp es GPL-3.0 y Starship CC0-1.0 (GitHub las identifica). **Shipwright** solo tiene `ASSETS-LICENSE.md` (CC BY-NC 4.0 para los assets, sin licencia de código
  identificable) y **sm64coopdx** no tiene archivo de licencia. La herramienta se detiene en esos casos: hace falta una decisión manual.

**Hecho en el backend (fase 1)**
- Migración `0007_install_package_setup.sql`: formato `appimage` y columna `setup` (JSON validado). La tabla se reconstruye conservando los datos.
- Esquema `setup` estricto: `start.program` (rutas relativas) y `saves` (rutas `~/…`); sin argumentos, comandos ni `prepare`.
- `tools/release-packages/build_packages.py` + `ports.json`: lee la última release, elige el archivo, obtiene el SHA-256 (digest de GitHub o calculado), toma la licencia de GitHub y
  escribe borradores en `seeds/release-packages/`. `--send` los envía como borrador; `--publish` los publica.
- Paquetes generados: **Zelda64Recomp** (majoras-mask) y **Starship** (star-fox-64). Pendientes por licencia: Shipwright y sm64coopdx.
- Pruebas: esquema, semillas y API (`tests/install-packages.test.ts`); 340 pruebas del backend en verde.
- **Falta desplegar:** aplicar la migración 0007 en D1 remoto y `npm run deploy`, y enviar los paquetes.

### Mario Kart World (Switch 2) — añadido 2026-11-23
La ficha `mario-kart-world` (Switch 2) ya existía en el catálogo con tres módulos. Revisados en GitHub:
- **`adriadam10/mkw-recomp`** (MIT, ~1.700 estrellas, activo): release v0.1.17 con **AppImage x86_64 (225 MB)** y aarch64; su pantalla de inicio prepara el juego desde tu volcado
  (versiones 1.0.0 y 1.8.0). **Incluido**: paquete `mkw-recomp` (SHA-256 del digest de GitHub), borrador en `seeds/release-packages/mkw-recomp.json`.
- **`MIXIDtheSilly/kart-recomp`** (GPL-3.0): release con tar.gz de Linux, pero su launcher **compila el juego en tu equipo** (~30 min, necesita compilador, Python y SDL3). Queda fuera por ahora
  (equivale a un paso de preparación); posible fase 4.
- **`STS78721/MKW-THWOMP`** (MIT): solo Windows → fuera (decisión «solo Linux»).
