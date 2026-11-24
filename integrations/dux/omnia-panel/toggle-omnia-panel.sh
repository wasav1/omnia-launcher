#!/usr/bin/env bash
# Abre o cierra el panel de Omnia (la pestaña «Omnia» del dashboard de Dux). Pensado para un atajo de teclado, p. ej. Super+Shift+O.
exec dms ipc call dash toggle plugin_omniaPanel
