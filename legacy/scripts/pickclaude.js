workspace.windowList().forEach(function (w) { if (String(w.caption).indexOf("Claude") >= 0 && w.normalWindow) workspace.activeWindow = w; });
