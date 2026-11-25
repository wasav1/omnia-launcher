# Omnia — guía de traspaso (para continuar con otra persona o IA)

Actualizada: 2026-11-25. Léela entera, luego `AGENTS.md` (reglas) y la sección 5 de `docs/CONTEXTO.md` (estado). El historial detallado está al final de CONTEXTO.md.

## 1. Cómo trabaja el dueño del proyecto
- Idioma: español. Explicaciones cortas, sin jerga innecesaria.
- Flujo: la IA implementa, prueba y **hace commits locales**; el usuario hace `git push`, ejecuta `sudo` y teclea las claves. Se le guía con **«Paso N»** y cada comando en su propio bloque ```bash.
- Su shell es **fish** (no usar sintaxis bash en comandos que debe pegar: `set -x`, no `export`).
- Pide aprobación antes de cambios grandes de diseño («espera mi aprobación»); le gustan los prototipos (3–5) para elegir.
- Nunca pedir ni imprimir contraseñas o claves. `ADMIN_API_KEY` se carga con `omnia-admin` (secret-tool) en su terminal.
- Descargas de terceros: pedir permiso. Capturas de pantalla: solo de ventanas propias (hyprctl + grim por región), nunca todo el escritorio.

## 2. Arranque rápido
```bash
cd ~/Proyectos/omnia-launcher        # rama work/standalone-application
PYTHONPATH=core python3 -m unittest discover -s tests   # 674 pruebas
/usr/lib/qt6/bin/qmllint ui/qml/<archivo>.qml
env OMNIA_PKGREL=N packaging/arch/build-local.sh         # → /tmp/omnia-pkg/*.pkg.tar.zst (4 paquetes)
```
Instalar (lo hace el usuario): `sudo pacman -U /tmp/omnia-pkg/*.pkg.tar.zst` y luego `systemctl --user restart omnia.service`. Últimos paquetes locales preparados: 0.3.0-106 en `/tmp/omnia-pkg-106` (recuperación de arte manual).
Backend (`~/Proyectos/omnia-backend`): `npx vitest run` (346), `python3 -m unittest discover -s tools/release-packages`, `npx wrangler deploy`, `npm run db:migrate`.

## 3. Cómo verificar
- **Servicio aislado** (no tocar el real): carpetas XDG propias, `PULSE_SERVER=unix:/run/user/1000/pulse/native`, `python3 -c "from omnia.service import main; main(['--port','47990'])"` con `PYTHONPATH=core`.
- **QML fuera de pantalla**: `MANGOHUD=0 DISABLE_MANGOHUD=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="qml=true" qml6 <Main.qml> -- --token <archivo> --port <N>`. Truco: carpeta temporal con enlaces `qml → ui/qml` y `assets → assets` del repo.
- **Dux**: `dms restart` para plugins nuevos; `dms ipc call omniaPanel toggle`.
- Trampas conocidas: `pkill -f` mata el propio comando (usar `ss -ltnp` y el PID); `MediaPlayer` en QML se cae con MangoHud global (usar `SoundEffect`); los `Repeater` necesitan delegados `Item` (usar `Instantiator` para objetos no visuales); QML `clip` no redondea imágenes (`ClippingRectangle` de Quickshell.Widgets).

## 4. Mapa de módulos clave
- `core/omnia/service.py` arranque; `api.py` todas las rutas; `config`/`store` estado; `games/*` detectores; `package_installs.py` instalador; `online_catalog.py` catálogo y arte; `mangohud.py`; `audio_out.py`; `pad.py` (evdev, vibración); `sounds.py`.
- `ui/qml/Api.qml` cliente único; `OmniaLibrary.qml` (Big Mode: estantería, intro, ajustes, sonidos); `OmniaManager.qml` (app de escritorio); `ui/omnia-ui` lanzador (desactiva MangoHud para la UI).
- `integrations/dux/omnia-panel/` plugin de Dux; `integrations/hyprland/ii/` panel de Hyprland.
- Backend: `src/` (Hono), `migrations/`, `seeds/`, `tools/release-packages/{build_packages,discover}.py + ports.json`, `tools/game-metadata/apply.py`.

## 5. Pendientes por prioridad
1. **Acciones del usuario**: instalar 0.3.0-106 y confirmar la recuperación de portada y fondo de LIMBO y Tomb Raider: The Last Revelation. Revisar acceso con SELECT, navegación y acciones de la ficha de Tienda con mando físico. Comprobar si Epic responde desde la sesión del usuario; `git push` de ambos repos; publicar tanda 5 (`omnia-admin`, luego `python3 tools/release-packages/build_packages.py --send-only --publish` y `python3 tools/game-metadata/apply.py --send`).
2. **Discord** (solo Big Mode): nivel A presencia HECHO (`core/omnia/discord.py`, pestaña Discord de los ajustes de BM; falta probarlo con el Application ID del usuario), nivel B voz (Client Secret tecleado por el usuario en su terminal). Discord Flatpak: socket `$XDG_RUNTIME_DIR/app/com.discordapp.Discord/discord-ipc-0` requiere un `flatpak override`.
3. **Tiendas**: app de escritorio integra en Explorar el catálogo de Omnia y los juegos de Steam/Epic/GOG/Amazon en una cuadrícula unificada; cuentas y compras conservan sus flujos existentes. Carátulas de las tiendas se cachean localmente en `~/.cache/omnia/catalog-art`. Probar con cuentas reales donde quede pendiente (Steam y Amazon); Ubisoft/EA quedan para más adelante vía Lutris/Wine. Inicio de sesión por OAuth en el navegador; tokens en el llavero o archivo 0600; **Omnia nunca ve contraseñas**. La reorganización visual de escritorio aún requiere revisión gráfica.
4. **19 mejoras acordadas** (en bloques pequeños). Big Mode: perfiles, mando como ratón/gestos, estadísticas, colecciones/etiquetas, capturas/grabación, modo nocturno/pantalla, tutorial de mando, suspender/apagar, salvapantallas, notificaciones propias. Escritorio: copias de partidas, gestor de ports, importar arrastrando, estadísticas/calendario, editor de colecciones, filtros de Explorar, salud del sistema, registros/diagnóstico, ajustes de sonido/bienvenida.
5. AUR (cuando reabran registros; tarea programada `aur-registration-watch`, guía `docs/PUBLICAR-AUR.md`); clave `VT_API_KEY` de VirusTotal; ~150 fichas sin arte; más candidatos en `discovery.json`; prueba real de vibración/gatillos con mando; cambios sin commit en MangoHud-Gerudo (sus reglas: no commitear sin permiso).

## 6. Mantener este contexto
Con **cada cambio**: línea nueva arriba del «Registro de cambios» de `docs/CONTEXTO.md` (fecha, qué, por qué, pruebas) y, si cambia el estado, secciones 4–5 de ese archivo y los pendientes de aquí. `tools/check-context.sh` avisa si hay cambios de código sin tocar CONTEXTO.md; se activa con `git config core.hooksPath .githooks` (solo avisa, no bloquea).
