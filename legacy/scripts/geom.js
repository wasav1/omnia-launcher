var ws = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < ws.length; i++) {
    var w = ws[i];
    if (String(w.caption).indexOf("Estantería de juegos") >= 0) {
        print("EST_GEOM " + w.x + "," + w.y + " " + w.width + "x" + w.height + " noBorder=" + w.noBorder + " keepBelow=" + w.keepBelow + " skipTaskbar=" + w.skipTaskbar + " screen=" + w.output.name);
    }
}
