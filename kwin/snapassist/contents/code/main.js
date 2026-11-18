// Snap Assist: al fijar una ventana a la mitad izquierda/derecha, abre "Presentar ventanas"
// y la ventana elegida se fija en la mitad contraria.
var pending = null;   // {side:"L"|"R", src, t}

function sideOf(w) {
    try { if (!w || !w.tile) return null; } catch (e) { return null; }
    var g = w.tile.absoluteGeometry, a = workspace.clientArea(KWin.MaximizeArea, w.output, workspace.currentDesktop);
    if (!g || !a) return null;
    var half = a.width / 2;
    if (Math.abs(g.width - half) > a.width * 0.1) return null;       // no es media pantalla
    if (Math.abs(g.height - a.height) > a.height * 0.1) return null; // no ocupa todo el alto
    if (Math.abs(g.x - a.x) < 10) return "L";
    if (Math.abs((g.x + g.width) - (a.x + a.width)) < 10) return "R";
    return null;
}
function sameArea(a, b) {
    return a.output === b.output && (a.desktops.length === 0 || b.desktops.length === 0 || a.desktops.some(function (d) { return b.desktops.indexOf(d) >= 0; }));
}
function allWindows() {
    try { return workspace.windowList(); } catch (e) { return workspace.stackingOrder || []; }
}
function others(src) {
    return allWindows().filter(function (w) {
        return w !== src && w.normalWindow && !w.minimized && !w.skipTaskbar && sameArea(w, src);
    });
}
function invoke(name) {
    callDBus("org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", name);
}
function hook(w) {
    if (!w || !w.normalWindow || w.snapHooked) return;
    w.snapHooked = true;
    w.tileChanged.connect(function () {
        var s = sideOf(w);
        if (!s) return;
        var other = s === "L" ? "R" : "L";
        var o = others(w);
        if (o.some(function (x) { return sideOf(x) === other; })) return;      // el otro lado ya esta ocupado
        if (o.filter(function (x) { return !x.tile; }).length === 0) return;   // nada que ofrecer
        pending = { side: other, src: w, t: Date.now() };
        invoke("Expose");
    });
}
allWindows().forEach(hook);
workspace.windowAdded.connect(hook);

workspace.windowActivated.connect(function (w) {
    if (!pending || !w) return;
    var dt = Date.now() - pending.t;
    if (dt > 20000) { pending = null; return; }
    if (dt < 900 || w === pending.src || !w.normalWindow) return;
    var side = pending.side; pending = null;
    invoke(side === "L" ? "Window Quick Tile Left" : "Window Quick Tile Right");
});
