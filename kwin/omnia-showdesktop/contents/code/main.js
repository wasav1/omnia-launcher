// "Mostrar escritorio" de KWin oculta también las superficies layer-shell de otras apps (la estantería de Omnia).
// Este atajo hace lo mismo pero minimizando/restaurando las ventanas normales, sin tocar las que tienen
// skipTaskbar (como la capa de fondo de Omnia).
var stash = [];

function realWindows() {
    return workspace.stackingOrder.filter(function (w) {
        return w.normalWindow && !w.skipTaskbar && !w.minimized && w.minimizable;
    });
}

function track(w) {
    w.minimizedChanged.connect(function () {        // si el usuario saca una ventana a mano, deja de estar "guardada"
        if (!w.minimized) stash = stash.filter(function (x) { return x !== w; });
    });
}

function toggle() {
    if (stash.length) {
        var back = stash;
        stash = [];
        back.forEach(function (w) { try { w.minimized = false; } catch (e) { } });
        try { workspace.activeWindow = back[back.length - 1]; } catch (e) { }     // la de arriba recupera el foco (y el mando deja la estantería)
    } else {
        stash = realWindows();
        stash.forEach(function (w) { track(w); w.minimized = true; });
    }
}

registerShortcut("OmniaShowDesktop", "Omnia: mostrar escritorio", "Meta+D", toggle);
