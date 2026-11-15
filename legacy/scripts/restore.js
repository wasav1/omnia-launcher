workspace.windowList().forEach(function (w) { if (w.normalWindow) { try { w.tile = null; } catch (e) {} if (String(w.caption).indexOf("Claude") >= 0) w.setMaximize(true, true); } });
