var ws = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < ws.length; i++) { var w = ws[i]; if (String(w.caption).indexOf("Estantería de juegos") >= 0) { w.keepBelow = false; workspace.activeWindow = w; } }
