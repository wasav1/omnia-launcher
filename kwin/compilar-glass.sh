#!/bin/bash
# Compila Glass (4v3ngR) contra kwin-devel del contenedor nx2navi e instala SOLO en ~/.local.
#   distrobox enter nx2navi -- bash ~/.local/share/estanteria/blur-build/compilar-glass.sh
set -e
echo "kwin-devel: $(rpm -q kwin-devel)"
cd "$HOME/.local/share/estanteria/blur-build/glass/kwin-effects-glass-main"
rm -rf build && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DKDE_INSTALL_LIBDIR=lib64 -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF
make -j3
make install
find "$HOME/.local/lib64" -path "*kwin*" -name "*.so" 2>/dev/null
echo FIN-OK
