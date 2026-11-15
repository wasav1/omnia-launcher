#!/bin/bash
# Carga Glass en la sesión (no persistente). Descarga blur y better_blur_dx.
for e in blur better_blur_dx; do gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.unloadEffect $e >/dev/null 2>&1; done
gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.loadEffect glass
sleep 1; gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.isEffectLoaded glass
