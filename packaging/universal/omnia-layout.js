// Omnia mantiene el wallpaper pasivo y una sola interfaz interactiva por escritorio.
var applet = "org.omnia.desktop";
var emptyDesktopUrl = "__OMNIA_EMPTY_DESKTOP_URL__";
var installed = knownWidgetTypes;
function hasWidgetType(type) { return installed.indexOf(type) >= 0; }
var all = desktops();
for (var di = 0; di < all.length; ++di) {
    var desktop = all[di];
    var screen = screenGeometry(desktop.screen);
    for (var wi = desktop.widgetIds.length - 1; wi >= 0; --wi) {
        var old = desktop.widgetById(desktop.widgetIds[wi]);
        if (!old) continue;
        // Omnia owns the desktop surface. Keep its single applet and remove
        // other desktop widgets that can cover its cards or capture input.
        if (old.type !== applet) old.remove();
    }
    desktop.currentConfigGroup = Array("General");
    desktop.writeConfig("url", emptyDesktopUrl);
    desktop.currentConfigGroup = Array();
    desktop.wallpaperPlugin = "org.omnia.launcher";
    if (!hasWidgetType(applet)) { print("Omnia: falta el widget " + applet); continue; }
    // Plasma only applies QSize from geometryHint when x or y is > 0. A 0.01px
    // x offset triggers that path while remaining visually at the origin.
    var widget = desktop.addWidget(applet, 0.01, 0, screen.width, screen.height);
    if (!widget) print("Omnia: no se pudo crear " + applet);
    else {
        var geometry = widget.geometry;
        print("Omnia: widget en " + geometry.x + "," + geometry.y + " con " + geometry.width + "x" + geometry.height + " en pantalla " + screen.width + "x" + screen.height);
    }
}
print("Omnia: wallpaper y widget único aplicados a " + all.length + " escritorio(s)");
