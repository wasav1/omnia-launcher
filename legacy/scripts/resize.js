var ws = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < ws.length; i++) {
    var w = ws[i];
    if (String(w.caption).indexOf("Prueba estantería") >= 0) {
        w.frameGeometry = { x: 60, y: 60, width: 1600, height: 960 };
    }
}
