var out = [];
workspace.windowList().forEach(function (w) { if (w.normalWindow) out.push(w.caption + "|" + w.resourceClass + "|min=" + w.minimized + "|qt=" + w.quickTileMode + "|tileSig=" + (w.quickTileModeChanged !== undefined)); });
callDBus("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify", "dbg", 0, "", "dbg", out.join("\n"), [], {}, 20000);
