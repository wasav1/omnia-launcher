// Vigilante de ventanas de Omnia. Calcula dos cosas y las envía a omnia-core por D-Bus (un script de KWin no puede hacer HTTP):
//   active  = el mando es de la estantería: tiene el foco (la pulsaste) o no hay ninguna ventana normal visible a la vista
//   covered = una ventana maximizada o a pantalla completa tapa el escritorio -> la UI puede pausar animaciones
// Las ventanas con skipTaskbar (la capa de fondo de Omnia, paneles, ventanas emergentes) no cuentan como «ventana normal».
var SERVICE = "org.omnia.Core", PATH = "/org/omnia/Core", IFACE = "org.omnia.Core";
var last = "";

function isReal(w) { return w && w.normalWindow && !w.skipTaskbar; }

function onThisDesktop(w) {
    if (w.onAllDesktops || !w.desktops || w.desktops.length === 0) return true;
    for (var i = 0; i < w.desktops.length; i++) if (w.desktops[i] === workspace.currentDesktop) return true;
    return false;
}

function visibleHere(w) { return isReal(w) && !w.minimized && onThisDesktop(w); }

function covers(w, ow, mode) {
    if (!isReal(w) || w.minimized || !onThisDesktop(w)) return false;
    var m = (w === ow) ? mode : w.maximizeMode;           // maximizedAboutToChange avisa antes de que cambie el valor
    return w.fullScreen || m === 3;
}

function compute(ow, mode) {
    var aw = workspace.activeWindow;
    var L = workspace.stackingOrder;
    var anyVisible = false, covered = false;
    for (var i = 0; i < L.length; i++) {
        if (visibleHere(L[i])) anyVisible = true;
        if (covers(L[i], ow, mode)) covered = true;
    }
    // las ventanas de Omnia (estantería y Big Menu) son superficies de capa: sin título, clase «qml» (o «omnia-ui» empaquetado)
    var shelfFocused = !!aw && !isReal(aw) && (aw.resourceClass === "qml" || aw.resourceClass === "omnia-ui");
    // El wallpaper nativo no es una ventana normal. Si el escritorio/Plasma tiene el foco, la estantería
    // vuelve a recibir teclado y mando aunque haya ventanas inactivas detrás; nunca mientras una app normal
    // siga enfocada. También cubre el caso de que KWin conserve como activa una ventana ya minimizada.
    var active = shelfFocused || !isReal(aw) || !anyVisible;
    var key = active + "/" + covered;
    if (key === last) return;
    last = key;
    callDBus(SERVICE, PATH, IFACE, "SetDesktop", active, covered);
}

function watch(w) {
    if (!w || w.omniaWatched) return;
    w.omniaWatched = true;
    w.minimizedChanged.connect(function () { compute(); });
    w.fullScreenChanged.connect(function () { compute(); });
    w.maximizedAboutToChange.connect(function (mode) { compute(w, mode); });
    w.desktopsChanged.connect(function () { compute(); });
}

workspace.windowAdded.connect(function (w) { watch(w); compute(); });
workspace.windowRemoved.connect(function () { compute(); });
workspace.windowActivated.connect(function () { compute(); });
workspace.currentDesktopChanged.connect(function () { compute(); });

workspace.stackingOrder.forEach(watch);
compute();
