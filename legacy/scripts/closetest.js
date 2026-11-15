var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) { var w = ws[i]; var c = String(w.caption); if (c.indexOf("Carpeta personal") >= 0 && c.indexOf("Dolphin") >= 0) w.closeWindow(); }
