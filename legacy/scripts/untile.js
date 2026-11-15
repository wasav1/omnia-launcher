workspace.windowList().forEach(function (w) { if (w.normalWindow) { w.minimized = false; try { w.tile = null; } catch (e) {} } });
workspace.windowList().forEach(function (w) { if (String(w.caption).indexOf("Dolphin") >= 0) workspace.activeWindow = w; });
