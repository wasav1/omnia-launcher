var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) {
    var w = ws[i];
    if (!w.normalWindow) continue;
    if (String(w.caption).indexOf("Dolphin") >= 0) {
        w.minimized = false;
        w.setMaximize(false, false);
        w.frameGeometry = { x: 640, y: 260, width: 1000, height: 620 };
        workspace.activeWindow = w;
    } else if (!w.minimized) {
        w.minimized = true;
    }
}
