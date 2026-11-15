"""Servicio D-Bus de Omnia en el bus de la sesión del usuario.

El script de KWin `omnia-watch` no puede hacer HTTP, pero sí llamar a D-Bus: avisa aquí de si el escritorio de Omnia
está a la vista. Es opcional: si PyGObject no está instalado, omnia-core funciona igual (el mando solo se silencia con
un juego abierto).
"""
import logging
import threading

log = logging.getLogger("omnia")
NAME, PATH, IFACE = "org.omnia.Core", "/org/omnia/Core", "org.omnia.Core"
XML = """<node><interface name="org.omnia.Core">
  <method name="SetDesktop"><arg type="b" name="active" direction="in"/><arg type="b" name="covered" direction="in"/></method>
</interface></node>"""


class DesktopService:
    def __init__(self, on_state, name: str = NAME):
        self.on_state, self.name = on_state, name
        self.loop = self.owner = self.thread = self.conn = self.reg = None
        self.ready = threading.Event()
        self.ok = False

    def start(self) -> bool:
        try:
            import gi
            gi.require_version("Gio", "2.0")
            from gi.repository import Gio, GLib
        except (ImportError, ValueError) as e:
            log.warning("sin D-Bus (PyGObject no disponible: %s): el mando no sabrá si hay ventanas encima", e)
            return False
        node = Gio.DBusNodeInfo.new_for_xml(XML)

        def on_call(conn, sender, path, iface, method, params, invocation):
            if method == "SetDesktop":
                active, covered = params.unpack()
                self.on_state(bool(active), bool(covered))
                invocation.return_value(None)
            else:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

        def on_acquired(conn, name):
            # el objeto se registra solo cuando el nombre es nuestro (la conexión de sesión se comparte en el proceso)
            self.conn = conn
            self.reg = conn.register_object(PATH, node.interfaces[0], on_call, None, None)
            self.ok = True
            self.ready.set()

        def on_lost(conn, name):
            self.ready.set()
            if not self.ok:
                log.warning("no se pudo registrar %s en D-Bus (¿ya hay otra instancia de omnia-core?)", name)

        def run():
            ctx = GLib.MainContext.new()
            ctx.push_thread_default()
            self.loop = GLib.MainLoop(ctx)
            self.owner = Gio.bus_own_name(Gio.BusType.SESSION, self.name, Gio.BusNameOwnerFlags.NONE,
                                          None, on_acquired, on_lost)
            self.loop.run()
            if self.conn is not None and self.reg:
                self.conn.unregister_object(self.reg)       # sin esto, un servicio nuevo en el mismo proceso no recibe llamadas
            Gio.bus_unown_name(self.owner)

        self.thread = threading.Thread(target=run, daemon=True, name="omnia-dbus")
        self.thread.start()
        self.ready.wait(5)
        return self.ok

    def stop(self):
        if self.loop:
            self.loop.quit()
        if self.thread:
            self.thread.join(3)         # espera a soltar el nombre en el bus
