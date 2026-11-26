#!/usr/bin/env bash
# Abre o cierra el panel de Omnia (el popout del botón de la barra de Dux). Pensado para un atajo de teclado, p. ej. Super+Shift+O.
exec dms ipc call omniaPanel toggle
