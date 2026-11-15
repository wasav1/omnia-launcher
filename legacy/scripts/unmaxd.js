var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) { var w = ws[i]; if (String(w.caption).indexOf("Dolphin") >= 0) { w.setMaximize(false, false); } }
