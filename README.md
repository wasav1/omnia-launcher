# Omnia

Una sola biblioteca para los juegos de Steam, Heroic (Epic/GOG), Lutris, Hydra, GeForce NOW y emuladores,
con un escritorio pensado para jugar en CachyOS + KDE Plasma 6.

Estado: reescritura en curso a partir del prototipo «Estantería» (Bazzite). Ver `docs/MIGRACION.md`.

```
core/        núcleo en Python (servicio de usuario, detectores, API local)
plasmoid/    widget y barra de Plasma 6 (QML)
kwin/        efectos y scripts de KWin (opcionales)
packaging/   PKGBUILD para Arch/CachyOS
tests/       pruebas con datos de ejemplo
legacy/      código original del prototipo, solo referencia
```
