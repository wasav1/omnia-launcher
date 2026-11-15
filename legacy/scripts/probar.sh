#!/bin/bash
# Copia el widget como "Prueba estantería" (sin reglas de KWin), lo abre en ventana grande, captura y cierra.
S=${1:-10}
T=/var/home/wsaenz/.local/share/plasma/plasmoids/org.wsaenz.estanteria.prueba
rm -rf $T; cp -r /var/home/wsaenz/.local/share/plasma/plasmoids/org.wsaenz.estanteria $T
sed -i 's/"org.wsaenz.estanteria"/"org.wsaenz.estanteria.prueba"/; s/"Estantería de juegos"/"Prueba estantería"/' $T/metadata.json
rm -f /tmp/estanteria-shot.png
(plasmawindowed org.wsaenz.estanteria.prueba > /tmp/estanteria-qml.log 2>&1 &)
sleep 4
gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.loadScript /var/home/wsaenz/.local/share/estanteria/resize.js est-resize >/dev/null 2>&1
gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.start >/dev/null 2>&1
sleep "$S"
[ -n "$MENU" ] && { curl -s -m 5 127.0.0.1:47831/menu >/dev/null; sleep 4; }
spectacle -b -n ${MENU:+-m} ${MENU:--a} -o /tmp/estanteria-shot.png >/tmp/spectacle.log 2>&1
sleep 1
pkill -f "plasmawindowed org.wsaenz.estanteria.prueba"
gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.unloadScript est-resize >/dev/null 2>&1
rm -rf $T
cp /tmp/estanteria-shot.png /var/home/wsaenz/.local/share/estanteria/shot.png 2>/dev/null
echo "--- log"; grep -v '^$' /tmp/estanteria-qml.log | head -30
