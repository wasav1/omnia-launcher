# Omnia

Lee `AGENTS.md` (reglas), `docs/HANDOFF.md` (arranque y pendientes) y `docs/CONTEXTO.md` (estado y registro) al empezar.

**Regla:** con cada cambio que hagas (código, empaquetado, decisiones, pendientes), actualiza `docs/CONTEXTO.md`:
línea nueva en el «Registro de cambios» (más reciente primero) y corrige las secciones 4–5 si algo cambió; ajusta los pendientes de `docs/HANDOFF.md`.

Tests: `PYTHONPATH=core python -m unittest discover -s tests`.
