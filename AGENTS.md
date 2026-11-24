# Omnia — reglas para agentes (Claude, Codex, Gemini…)

Biblioteca de juegos para Linux: `omnia-core` (Python, solo stdlib) + QML (app de escritorio y Big Mode) + integraciones (Hyprland, Dux) + backend en Cloudflare (`~/Proyectos/omnia-backend`).

1. **Empieza por** `docs/HANDOFF.md`, luego `docs/CONTEXTO.md` (secciones 1–6 y el registro al final).
2. **Con cada cambio** actualiza `docs/CONTEXTO.md` (línea nueva en «Registro de cambios», más reciente primero; corrige secciones 4–5 si cambian) y los pendientes de `docs/HANDOFF.md`.
3. Pruebas antes de commitear: `PYTHONPATH=core python3 -m unittest discover -s tests` (y `qmllint` en los QML tocados).
4. **Commits locales sí; `git push` nunca** (lo hace el usuario). `sudo` solo lo ejecuta el usuario. No imprimir ni pedir contraseñas/claves; `ADMIN_API_KEY` la carga el usuario con `omnia-admin`.
5. Núcleo sin dependencias externas. Omnia jamás maneja contraseñas de tiendas de terceros. Descargas de terceros: pedir permiso.
6. Responde en español; guía al usuario con «Paso N» y cada comando en su bloque ```bash (su shell es fish).
7. Sonidos en QML: `SoundEffect`, nunca `MediaPlayer` (se cae con la capa global de MangoHud).
