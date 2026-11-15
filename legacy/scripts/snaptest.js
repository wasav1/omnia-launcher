var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) { var w = ws[i]; if (w.normalWindow) { w.minimized = false; print("snaptest:", w.caption, w.quickTileMode); } }
for (var i = 0; i < ws.length; i++) { if (String(ws[i].caption).indexOf("Dolphin") >= 0) workspace.activeWindow = ws[i]; }
