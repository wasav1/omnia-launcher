// Reaplica únicamente la superficie de Omnia tras iniciar Plasma; conserva el resto de widgets.
var applet = "org.omnia.desktop";
var emptyDesktopUrl = "__OMNIA_EMPTY_DESKTOP_URL__";
var installed = knownWidgetTypes;
function hasWidgetType(type) { return installed.indexOf(type) >= 0; }
var all = desktops();
for (var di = 0; di < all.length; ++di) {
    var desktop = all[di];
    var screen = screenGeometry(desktop.screen);
    desktop.currentConfigGroup = Array("General");
    desktop.writeConfig("url", emptyDesktopUrl);
    desktop.currentConfigGroup = Array();
    desktop.wallpaperPlugin = "org.omnia.launcher";
    if (!hasWidgetType(applet)) continue;
    var widget = null;
    for (var wi = desktop.widgetIds.length - 1; wi >= 0; --wi) {
        var existing = desktop.widgetById(desktop.widgetIds[wi]);
        if (existing && existing.type === applet) {
            if (!widget) widget = existing;
            else existing.remove();
        }
    }
    if (!widget) widget = desktop.addWidget(applet, 0.01, 0, screen.width, screen.height);
    if (widget) widget.geometry = {x: 0.01, y: 0, width: screen.width, height: screen.height};
}
print("Omnia: escritorio restaurado en " + all.length + " escritorio(s)");
