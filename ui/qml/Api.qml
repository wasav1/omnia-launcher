import QtQuick

// Cliente de omnia-core: HTTP en loopback con el token de sesión (se lee del archivo, nunca va en el código).
QtObject {
    id: api

    property int port: 47831
    property string tokenPath: ""
    property string token: ""
    // Plasma wallpaper plugins run inside plasmashell and cannot read the bearer token through QML XHR.
    // A native QML singleton may provide it; the standalone UI keeps using its private token file.
    property string providedToken: ""
    property bool controlsEnabled: true
    property bool _started: false
    property bool _pollingPad: false
    onControlsEnabledChanged: {
        if (!controlsEnabled) retry.stop()
        else if (_started) pollPad()
    }
    property bool systemEnabled: false
    property bool autoStart: true
    property bool ok: false
    property string error: ""
    property var games: []
    property string toast: ""
    property string notificationPosition: "bottom-right"
    property string theme: "blue"
    property color themeAccent: "#336599"
    property string language: "es"
    property string installRoot: ""
    property string catalogBaseUrl: ""
    property real toastLevel: 0           // opacidad del aviso: 1 al mostrarlo, 3 s después se desvanece en 2 s
    function notify(text) { toast = ""; toast = text }
    onToastChanged: {
        toastFade.stop()
        if (toast === "") { toastLevel = 0; return }
        toastLevel = 1
        toastHold.restart()
    }
    property Timer toastHold: Timer { interval: 3000; onTriggered: toastFade.start() }
    property NumberAnimation toastFade: NumberAnimation { target: api; property: "toastLevel"; to: 0; duration: 2000; easing.type: Easing.InOutQuad
        onFinished: api.toast = "" }
    property bool covered: false          // una ventana maximizada o a pantalla completa tapa el escritorio
    property bool shelfActive: true       // el mando es de la estantería (ninguna ventana normal tiene el foco)
    property var apps: []
    property var appGroups: []
    property bool gameMode: false         // modo juego activo (descargas congeladas y perfil de energía alto)
    readonly property bool gameRunning: {
        for (let i = 0; i < api.games.length; i++) if (api.games[i].running) return true
        return false
    }                                      // estado inmediato para la interfaz; el modo de energía usa su propia histéresis
    property bool padOn: false
    property bool menuOpen: false         // Big Menu abierto (la UI lo informa; pausa el sondeo del espectro)
    property string padName: ""
    property bool mangohud: false           // monitor de rendimiento (MangoHud con el estilo de Omnia) en los juegos lanzados
    property bool mangohudInstalled: true
    property bool uiSounds: true            // sonidos de la interfaz de Big Mode
    property int uiSoundVolume: 70
    property string uiSoundPack: "omnia"
    property var uiSoundPacks: []
    property bool introEnabled: true        // animación de bienvenida de Big Mode
    property string userName: ""          // a quién saluda la bienvenida (elegido o el del sistema)
    property string displayName: ""        // el elegido en Ajustes (vacío = el del sistema)
    property bool prefsLoaded: false        // ya se leyeron los ajustes del núcleo
    property bool updateCheck: true         // avisar de «Actualización disponible» de los ports instalados (Ajustes)
    property bool animatedBackground: true  // fondo de constelación de BigMode (Ajustes)
    property bool glassEffect: true         // efecto cristal del rediseño D (Ajustes → Apariencia)
    property var padBattery: null          // {level, charging} si el sistema expone la batería del mando; si no, null
    property string padFamily: ""          // tipo de mando para los iconos: xbox | ps | switch | deck
    property int padSeq: -1
    property int padRevision: -1
    property int gameRevision: -1
    property int revision: -1
    property bool audioActive: false
    property bool audioAvailable: false
    property var audioBands: []
    property var system: ({})             // /system: procesador, discos, batería, perfil energético y ventiladores
    signal padKey(string key)
    property string _last: ""

    function arg(name, fallback) {
        let a = Qt.application.arguments, i = a.indexOf(name)
        return (i >= 0 && i + 1 < a.length) ? a[i + 1] : fallback
    }

    function readToken() {
        if (providedToken) return providedToken
        if (!tokenPath) return ""
        try {
            let x = new XMLHttpRequest()
            x.open("GET", "file://" + tokenPath, false)       // archivo local pequeño: síncrono
            x.send()
            return x.responseText.trim()
        } catch (e) { return "" }
    }

    function call(method, path, done, body) {
        if (!api.token) api.token = api.readToken()
        let x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== 4) return
            let body = {}
            try { body = JSON.parse(x.responseText) } catch (e) { }
            if (api.language === "en" && x.status >= 400 && body && typeof body.error === "string")
                body.error = api.localizeError(body.error, x.status)
            if (x.status === 401) api.token = ""                  // el servicio se reinició: token nuevo
            done(x.status, body)
        }
        x.open(method, "http://127.0.0.1:" + api.port + path)
        x.setRequestHeader("Authorization", "Bearer " + api.token)
        if (method === "POST") x.setRequestHeader("Content-Type", "application/json")
        x.send(method === "POST" ? (body ? JSON.stringify(body) : "{}") : null)
    }

    function localizeError(message, status) {
        const text = String(message || "")
        const known = {
            "No se pudo conectar con el catálogo de Omnia.": "Could not connect to the Omnia catalog.",
            "El catálogo devolvió una respuesta inválida.": "The catalog returned an invalid response.",
            "El catálogo no pudo atender la solicitud.": "The catalog could not process the request.",
            "omnia-core no responde (¿está en marcha el servicio?)": "omnia-core is not responding (is the service running?)",
            "token no válido: reiniciando conexión": "Invalid token: reconnecting.",
            "host no permitido": "Host not allowed.",
            "ruta desconocida": "Unknown route.",
            "método no permitido": "Method not allowed.",
            "token inválido": "Invalid token.",
            "Content-Length no válido": "Invalid Content-Length.",
            "cuerpo demasiado grande": "The request body is too large.",
            "se requiere application/json": "The request must use application/json.",
            "revisión o espera no válida": "Invalid revision or wait interval.",
            "juego desconocido": "Unknown game.",
            "juego no válido": "Invalid game.",
            "acción de energía no válida": "Invalid power action.",
            "no se pudo ejecutar la acción": "Could not complete the action.",
            "Actualiza Omnia para instalar los ajustes generales.": "Update Omnia to install the system integration.",
            "Falta systemd-run para abrir los ajustes fuera del núcleo de Omnia.": "systemd-run is required to open settings outside the Omnia service.",
            "No se pudo iniciar la unidad de ajustes de Omnia.": "Could not start the Omnia settings service.",
            "KDE no pudo iniciar los ajustes. Consulta el registro de usuario de systemd.": "KDE could not open settings. Check the user systemd log.",
            "El idioma debe ser es o en.": "The language must be es or en.",
            "Elige una carpeta existente para instalar los juegos.": "Choose an existing folder for game installations.",
            "La carpeta de instalación debe estar dentro de una ubicación permitida.": "The installation folder must be inside an allowed location.",
            "Parámetros de catálogo no válidos": "Invalid catalog parameters.",
            "faltan datos del paquete o carpeta de destino": "Package details or destination folder are missing.",
            "la instalación no está activa": "The installation is not active.",
            "la instalación no se puede pausar en este momento": "The installation cannot be paused right now.",
            "la instalación no está pausada": "The installation is not paused.",
            "Cierra el juego antes de desinstalarlo.": "Close the game before uninstalling it.",
            "Cierra Steam antes de desinstalar el juego.": "Close Steam before uninstalling the game.",
            "Cierra Heroic antes de desinstalar el juego.": "Close Heroic before uninstalling the game.",
            "No se pudo verificar el registro de instalación.": "Could not verify the installation record.",
            "El registro de instalación es demasiado grande.": "The installation record is too large.",
            "No se pudo verificar el App ID de Steam.": "Could not verify the Steam App ID.",
            "No se pudo verificar una única instalación de Steam.": "Could not verify a single Steam installation.",
            "Termina la descarga o actualización de Steam antes de desinstalar.": "Finish the Steam download or update before uninstalling.",
            "La instalación cambió. Actualiza la biblioteca y vuelve a intentarlo.": "The installation changed. Refresh the library and try again.",
            "La carpeta de instalación se comparte con otro juego.": "Another game shares the installation folder.",
            "Omnia no pudo verificar qué archivos pertenecen a este juego.": "Omnia could not verify which files belong to this game.",
            "La carpeta de instalación contiene un punto de montaje.": "The installation folder contains a mount point.",
            "No se pudieron verificar los puntos de montaje.": "Could not verify the mount points.",
            "Omnia no pudo retirar todos los archivos de instalación.": "Omnia could not remove all installation files.",
            "Usa Quitar de la biblioteca para conservar los archivos.": "Use Remove from library to keep the files.",
            "El archivo no es un ejecutable de Windows válido.": "The file is not a valid Windows executable.",
            "El archivo no es un ejecutable de Linux válido.": "The file is not a valid Linux executable.",
            "No se pudo leer el ejecutable del juego.": "Could not read the game executable.",
            "Elige el ejecutable del juego, en lugar del instalador o desinstalador.": "Choose the game executable instead of the installer or uninstaller.",
            "la instalación de Omnia no existe": "The Omnia installation record does not exist.",
            "MangoHud no está instalado. Instálalo desde el gestor de paquetes y vuelve a intentarlo.": "MangoHud is not installed. Install it with your package manager and try again.",
            "juego o port desconocido": "Unknown game or port.",
            "La carpeta de este juego se retiró de las rutas de Omnia.": "This game's folder was removed from Omnia's allowed locations.",
            "no está instalado": "The game is not installed.",
            "ya está en ejecución": "The game is already running.",
            "aplicación desconocida": "Unknown application.",
            "acción o ruta de biblioteca no válida": "Invalid library action or location.",
            "elige una carpeta existente": "Choose an existing folder.",
            "la carpeta debe estar dentro de tu carpeta personal o una unidad montada": "The folder must be inside your home directory or a mounted drive.",
            "ruta fuera de las carpetas permitidas": "The path is outside the allowed folders.",
            "«ids» debe ser una lista": "“ids” must be a list.",
            "ruta, nombre, plataforma o emulador no válidos": "Invalid path, name, platform, or emulator.",
            "identificador de catálogo no válido": "Invalid catalog identifier.",
            "la ROM ya no es válida o no se reconoce su formato": "The ROM is no longer valid or its format is not recognized.",
            "la plataforma de la ROM cambió; vuelve a analizar la carpeta": "The ROM platform changed. Scan the folder again.",
            "ruta no permitida en el respaldo": "The save backup contains a path that is not allowed.",
            "archivo no válido": "Invalid file.",
            "ese respaldo no existe": "That backup does not exist.",
            "no hay carpeta de partidas": "No save folder is configured.",
            "tipo de arte no válido": "Invalid artwork type.",
            "Este juego no tiene artwork publicado en el catálogo Omnia.": "This game has no artwork published in the Omnia catalog.",
            "opción de arte fuera de rango": "The artwork option is out of range.",
            "edición, página u opción de arte no válida": "Invalid artwork edition, page, or option.",
            "dirección no válida": "Invalid direction.",
            "Este juego no tiene otras opciones de arte descargadas": "No other artwork options have been downloaded for this game.",
            "página o edición no válida": "Invalid page or edition.",
            "parámetros no válidos": "Invalid parameters.",
            "tecla no válida": "Invalid key.",
            "Pon un nombre al juego (hasta 80 letras).": "Enter a game name (up to 80 characters).",
            "Tipo de juego no válido.": "Invalid game type.",
            "Ese archivo está fuera de las carpetas permitidas.": "That file is outside the allowed folders.",
            "El lanzador asociado está fuera de las carpetas permitidas.": "The associated launcher is outside the allowed folders.",
            "Elige el ejecutable del juego.": "Choose the game's executable.",
            "Falta umu-launcher para ejecutar juegos de Windows.": "umu-launcher is required to run Windows games.",
            "El archivo elegido no es ejecutable.": "The selected file is not executable.",
            "Plataforma no válida.": "Invalid platform.",
            "Nombre, ROM, plataforma o emulador no válidos.": "Invalid name, ROM, platform, or emulator.",
            "La ROM ya no es válida o cambió de plataforma.": "The ROM is no longer valid or its platform changed.",
            "La URL del paquete no es válida.": "Invalid package URL.",
            "El paquete debe usar una URL HTTPS pública.": "The package must use a public HTTPS URL.",
            "La fuente del paquete no es pública.": "The package source is not public.",
            "No se pudo resolver la fuente del paquete.": "Could not resolve the package source.",
            "La fuente del paquete debe resolver a direcciones públicas.": "The package source must resolve to public IP addresses.",
            "La fuente del paquete resolvió una dirección no válida.": "The package source resolved to an invalid address.",
            "No se permiten proxies ni túneles para instalar paquetes.": "Proxies and tunnels are not allowed when installing packages.",
            "No se pudo conectar con la fuente del paquete.": "Could not connect to the package source.",
            "El paquete contiene una ruta insegura.": "The package contains an unsafe path.",
            "El paquete contiene una ruta fuera de su carpeta.": "The package contains a path outside its folder.",
            "El paquete intenta salir de su carpeta de instalación.": "The package attempts to write outside its installation folder.",
            "El paquete contiene demasiados archivos.": "The package contains too many files.",
            "El tamaño expandido supera el límite de Omnia.": "The expanded package exceeds Omnia's size limit.",
            "El paquete ZIP incluye enlaces o archivos especiales.": "The ZIP package contains links or special files.",
            "El tamaño expandido no coincide con el ZIP o supera el límite.": "The expanded size does not match the ZIP or exceeds the limit.",
            "Un archivo del paquete ZIP quedó incompleto.": "A file in the ZIP package is incomplete.",
            "No se pudo leer un archivo del paquete.": "Could not read a file in the package.",
            "El tamaño expandido no coincide con TAR o supera el límite.": "The expanded size does not match the TAR archive or exceeds the limit.",
            "Un archivo del paquete TAR quedó incompleto.": "A file in the TAR package is incomplete.",
            "El paquete TAR incluye enlaces o archivos especiales.": "The TAR package contains links or special files.",
            "Ya existe una carpeta con ese nombre; elige otro destino.": "A folder with that name already exists. Choose another destination.",
            "La carpeta de instalación no supera la validación de seguridad.": "The installation folder did not pass the security checks.",
            "La carpeta de instalación ya no existe o no es segura.": "The installation folder no longer exists or is not safe.",
            "Omnia no pudo retirar el juego de la biblioteca.": "Omnia could not remove the game from the library.",
            "El manifiesto contiene información de identificación no válida.": "The manifest contains invalid identification data.",
            "El tamaño declarado del paquete no es válido.": "The declared package size is invalid.",
            "El tamaño o SHA-256 declarado no es válido.": "The declared size or SHA-256 is invalid.",
            "El paquete debe declarar su fuente y licencia.": "The package must specify its source and license.",
            "El paquete no declara el ejecutable de inicio.": "The package does not specify a launch executable.",
            "Instalación cancelada.": "Installation cancelled.",
            "La descarga redirigió a una conexión no segura.": "The download redirected to an insecure connection.",
            "El tamaño recibido no coincide con el manifiesto.": "The received size does not match the manifest.",
            "La descarga superó el tamaño publicado.": "The download exceeded its published size.",
            "El manifiesto publicado está incompleto o usa un formato no admitido.": "The published manifest is incomplete or uses an unsupported format.",
            "El paquete no aparece publicado en el catálogo.": "This package is not published in the catalog.",
            "El punto de entrada declarado no está dentro del paquete.": "The declared entry point is not present in the package.",
            "La descarga quedó incompleta.": "The download is incomplete.",
            "El SHA-256 descargado no coincide; se descartó el paquete.": "The downloaded SHA-256 did not match; the package was discarded.",
            "No se pudo comprobar el espacio libre en la carpeta elegida.": "Could not check available space in the selected folder.",
            "No hay suficiente espacio libre para descargar y extraer este paquete.": "There is not enough free space to download and extract this package.",
            "La instalación cambió de volumen durante la descarga.": "The installation volume changed during the download.",
            "Por ahora la instalación directa solo admite paquetes de PC.": "Direct installation currently supports PC packages only.",
            "El emulador elegido ya no está disponible o no corresponde a esta ROM.": "The selected emulator is unavailable or does not support this ROM.",
            "No se encontró el núcleo de RetroArch para esta plataforma.": "No RetroArch core was found for this platform.",
            "Elige una carpeta permitida que exista.": "Choose an existing folder within an allowed location.",
            "No se encontraron ROMs compatibles en esta carpeta.": "No compatible ROMs were found in this folder.",
            "No se pudo analizar la carpeta.": "Could not scan the folder.",
            "No se pudo añadir la ROM.": "Could not add the ROM."
        }
        if (known[text]) return known[text]
        const duplicateRom = text.match(/^Esta ROM ya está en la biblioteca como (.+)\.$/)
        if (duplicateRom) return "This ROM is already in your library as " + duplicateRom[1] + "."
        const outsideRoot = text.match(/^carpeta fuera de las permitidas: (.+)$/)
        if (outsideRoot) return "Folder is outside the allowed locations: " + outsideRoot[1]
        const alreadyEnglish = /^(Could not|The |This |Invalid |Unknown |Request failed|Installation |Download )/i.test(text)
        if (alreadyEnglish) return text
        if (/\b(la|el|los|las|no se|falta|elige|debe|paquete|carpeta|juego|instalación|ROM)\b/i.test(text) || /[áéíóúñ¿¡]/i.test(text))
            return "Request failed (HTTP %1).".replace("%1", status)
        return text || "Request failed (HTTP %1).".replace("%1", status)
    }

    function localizeNotice(message) {
        const text = String(message || "")
        const known = {
            "Este backend todavía no publica manifiestos de instalación.": "This backend has not published install packages yet.",
            "Juego no válido.": "Invalid game.",
            "No se pudo conectar con el catálogo de Omnia.": "Could not connect to the Omnia catalog."
        }
        if (known[text]) return known[text]
        if (/\b(backend|catálogo|conexión|conectar|no se pudo|respuesta|juego no válido)\b/i.test(text) || /[áéíóúñ¿¡]/i.test(text))
            return "The Omnia catalog is offline or returned incomplete data."
        return text
    }

    function loadPreferences() {
        call("GET", "/settings", function(status, body) {
            if (status === 200) {
                api.notificationPosition = body.notification_position || "bottom-right"
                api.theme = body.theme || "blue"
                api.themeAccent = body.theme_accent || "#336599"
                api.installRoot = body.install_root || ""
                api.animatedBackground = body.animated_background !== false
                api.glassEffect = body.glass_effect !== false
                api.updateCheck = body.update_check !== false
                api.mangohud = body.mangohud === true
                api.mangohudInstalled = body.mangohud_installed !== false
                api.uiSounds = body.ui_sounds !== false
                api.uiSoundVolume = body.ui_sound_volume === undefined ? 70 : body.ui_sound_volume
                api.uiSoundPack = body.ui_sound_pack || "omnia"
                api.uiSoundPacks = body.ui_sound_packs || []
                api.introEnabled = body.intro_enabled !== false
                api.userName = body.user_name || ""
                api.displayName = body.display_name || ""
                api.prefsLoaded = true
                Qt.uiLanguage = body.language === "en" ? "en_US" : "es"
                api.language = body.language === "en" ? "en" : "es"
            }
        })
    }

    function refresh() {
        call("GET", "/library?since=" + api.revision, function (status, body) {
            if (status === 200) {
                api.ok = true; api.error = ""
                if (body.revision !== undefined && body.revision !== api.revision && body.games)
                    api.games = body.games
                if (body.revision !== undefined) api.revision = body.revision
            }
            else {
                api.ok = false
                const message = status === 0 ? "omnia-core no responde (¿está en marcha el servicio?)"
                    : status === 401 ? "token no válido: reiniciando conexión" : "error " + status
                api.error = api.language === "en" ? api.localizeError(message, status) : message
            }
        })
    }

    // Catálogo público Omnia Backend. El servicio loopback gestiona caché/offline y evita CORS en QML.
    function catalogGames(options, done) {
        options = options || {}
        let params = []
        for (let key of ["page", "pageSize", "q", "platform", "compatibility", "sort", "order"]) {
            if (options[key] !== undefined && options[key] !== null && String(options[key]) !== "")
                params.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(options[key])))
        }
        call("GET", "/catalog/games" + (params.length ? "?" + params.join("&") : ""), function (status, body) {
            if (body && body.baseUrl) api.catalogBaseUrl = body.baseUrl
            if (done) done(status, body)
        })
    }
    function catalogGame(slug, done) {
        call("GET", "/catalog/game?slug=" + encodeURIComponent(slug || ""), function (status, body) {
            if (body && body.baseUrl) api.catalogBaseUrl = body.baseUrl
            if (done) done(status, body)
        })
    }
    function catalogPlatforms(done) {
        call("GET", "/catalog/platforms", function (status, body) {
            if (body && body.baseUrl) api.catalogBaseUrl = body.baseUrl
            if (done) done(status, body)
        })
    }
    function catalogRomIdentifiers(platform, done) {
        call("GET", "/catalog/rom-identifiers?platform=" + encodeURIComponent(platform || ""), function (status, body) {
            if (body && body.baseUrl) api.catalogBaseUrl = body.baseUrl
            if (done) done(status, body)
        })
    }
    function catalogInstallPackages(slug, done) {
        call("GET", "/catalog/install-packages?slug=" + encodeURIComponent(slug || ""), function (status, body) {
            if (body && body.baseUrl) api.catalogBaseUrl = body.baseUrl
            if (done) done(status, body)
        })
    }
    function installationSnapshot(done) { call("GET", "/installations", done) }
    function startInstallation(slug, packageId, destination, done) {
        call("POST", "/installations/start", done, {slug: slug, packageId: packageId, destination: destination})
    }
    function dismissInstallations(target, done) { call("POST", "/installations/dismiss", done, target === true ? {all: true} : {jobId: target}) }
    function retryInstallation(jobId, done) { call("POST", "/installations/retry", done, {jobId: jobId}) }
    function updateInstallation(gameId, done) { call("POST", "/installations/update", done, {gameId: gameId}) }
    function cancelInstallation(jobId, done) { call("POST", "/installations/cancel", done, {jobId: jobId}) }
    function pauseInstallation(jobId, done) { call("POST", "/installations/pause", done, {jobId: jobId}) }
    function resumeInstallation(jobId, done) { call("POST", "/installations/resume", done, {jobId: jobId}) }
    signal storeInstallationRemoved(string store, string product)
    function removalPreview(gameId, done) { call("GET", "/installations/removal-preview?id=" + encodeURIComponent(gameId), done) }
    function removeInstallation(gameId, path, done) {
        call("POST", "/installations/remove", (status, body) => {
            if (status === 200 && body.store && body.product) storeInstallationRemoved(body.store, body.product)
            done(status, body)
        }, {gameId: gameId, removeFiles: true, expectedPath: path})
    }

    function selectGame(id, done, filterKey) {
        call("POST", "/selection/set", function (status, body) {
            if (status !== 200) console.warn("Omnia: no se pudo sincronizar el juego seleccionado", status)
            if (done) done(status, body)
        }, { id: id || "", filterKey: filterKey || "all" })
    }
    function setView(filterKey, searchText, done) {
        call("POST", "/view/set", function (status, body) {
            if (status !== 200) console.warn("Omnia: no se pudo sincronizar la vista", status)
            if (done) done(status, body)
        },
             { filterKey: filterKey || "all", searchText: searchText || "" })
    }

    // Al cerrar/minimizar un juego a pantalla completa, KWin libera el escritorio. Refresca la biblioteca
    // enseguida para retirar la capa «EN EJECUCIÓN» sin esperar al siguiente sondeo periódico.
    onCoveredChanged: if (!covered) Qt.callLater(refresh)

    function pollSystem() {
        call("GET", "/system", function (status, body) { if (status === 200 && body) api.system = body })
    }

    function pollAudio() {
        call("GET", "/audio", function (status, body) {
            if (status === 200 && body) {
                api.audioAvailable = body.available === true
                api.audioActive = body.active === true
                api.audioBands = body.bands || []
            }
        })
    }

    function launch(g, portId) {
        if (!g || !g.ports.length) return
        api.toast = qsTr("Lanzando %1…").arg(g.name)
        call("POST", "/launch?id=" + encodeURIComponent(g.id) + "&port=" + encodeURIComponent(portId || g.ports[0].id), function (status, body) {
            api.toast = status === 200 ? "" : (body.error || qsTr("Error %1").arg(status))
            api.refresh()
        })
    }

    // --- aplicaciones (Big Menu)
    function loadApps() {
        call("GET", "/apps", function (status, body) {
            if (status === 200) { api.apps = body.apps; api.appGroups = body.groups }
        })
    }
    // --- salida de audio (botón del altavoz)
    function loadAudioOutputs(done) {
        call("GET", "/audio/outputs", function (status, body) {
            if (status !== 200 || !body || !body.ok || !body.items.length) { done([], (body && body.error) || ""); return }
            done(body.items, "")
        })
    }
    function setAudioOutput(item, done) {
        call("POST", "/audio/set?sink=" + encodeURIComponent(item.sink) + "&port=" + encodeURIComponent(item.port || ""),
             function (status) { if (done) done(status === 200) })
    }
    function launchApp(a, done) {
        call("POST", "/app/launch?id=" + encodeURIComponent(a.id), function (status, body) {
            if (status !== 200) api.toast = body.error || qsTr("Error %1").arg(status)
            if (done) done(status === 200)
        })
    }
    // --- partidas, explorador de carpetas y juegos manuales (cada función avisa con done(status, cuerpo))
    function fsList(path, files, exts, done) {
        call("GET", "/fs/list?path=" + encodeURIComponent(path || "") + "&files=" + (files ? "1" : "0") + "&ext=" + encodeURIComponent((exts || []).join(",")), done)
    }
    function _q(g, portId) { return "id=" + encodeURIComponent(g.id) + "&port=" + encodeURIComponent(portId || (g.ports && g.ports.length ? g.ports[0].id : "")) }
    function savesInfo(g, done, portId) { call("GET", "/saves?" + _q(g, portId), done) }
    function savesSuggest(g, done, portId) { call("GET", "/saves/suggest?" + _q(g, portId), done) }
    function savesConfig(g, body, done, portId) { call("POST", "/saves/config?" + _q(g, portId), done, body) }
    function savesBackup(g, done, portId) { call("POST", "/saves/backup?" + _q(g, portId), done) }
    function savesRestore(g, file, done, portId) { call("POST", "/saves/restore?" + _q(g, portId) + "&file=" + encodeURIComponent(file), done) }
    function openInstallationFolder(gameId, done) { call("POST", "/folders/open", done, {gameId: gameId, installation: true}) }
    function openFolder(gameId, folder, done) { call("POST", "/folders/open", done, {gameId: gameId, folder: folder}) }
    function savesOpen(g, done, portId) { call("POST", "/saves/open?" + _q(g, portId), done) }
    property var suiteUpdate: ({phase: "idle", current: "", available: "", progress: 0, error: ""})
    function pollSuiteUpdate(surface, shown) {
        call("GET", "/suite-update?surface=" + encodeURIComponent(surface) + "&visible=" + (shown ? "1" : "0"), function(status, body) {
            if (status === 200 && body) api.suiteUpdate = body
        })
    }
    function suiteUpdateAction(action, done) {
        call("POST", "/suite-update/" + action, function(status, body) {
            if (status === 200 && body) api.suiteUpdate = body
            if (done) done(status, body)
        })
    }
    function artMatches(g, title, done) {
        call("GET", "/art/matches?id=" + encodeURIComponent(g.id) + "&title=" + encodeURIComponent(title), done)
    }
    function artBrowse(g, kind, page, sgid, done, match) {
        call("GET", "/art/browse?id=" + encodeURIComponent(g.id) + "&kind=" + encodeURIComponent(kind)
             + "&page=" + page + "&sgid=" + sgid + "&match=" + encodeURIComponent(match || ""), done)
    }
    function artPick(g, kind, page, sgid, index, done) {
        call("POST", "/art/pick?id=" + encodeURIComponent(g.id) + "&kind=" + encodeURIComponent(kind) + "&page=" + page + "&sgid=" + sgid + "&index=" + index, done)
    }
    function artChoose(g, kind, url, done) { call("POST", "/art/choose", done, {id: g.id, kind: kind, url: url}) }
    function artTmp(done) { call("GET", "/art/tmp", done) }
    function artLocal(g, kind, path, done) { call("POST", "/art/local", done, {id: g.id, kind: kind, path: path}) }
    function artReset(g, kind, done) { call("POST", "/art/reset", done, kind ? {id: g.id, kind: kind} : {id: g.id}) }
    function artCycle(g, kind, direction, done) {
        call("POST", "/art/cycle?id=" + encodeURIComponent(g.id) + "&kind=" + encodeURIComponent(kind) + "&dir=" + direction, done)
    }
    function importFind(done) { call("GET", "/import/find", done) }
    function importPreview(path, done) { call("GET", "/import/preview?path=" + encodeURIComponent(path), done) }
    function importApply(path, done) { call("POST", "/import/apply?path=" + encodeURIComponent(path), function (st, b) { if (st === 200) api.refresh(); done(st, b) }) }
    function templates(done) { call("GET", "/templates", done) }
    function addGame(body, done) { call("POST", "/game/add", function (st, b) { if (st === 200) api.refresh(); done(st, b) }, body) }
    function suggestGame(path, done) { call("GET", "/game/suggest?path=" + encodeURIComponent(path), done) }
    function scanGameFolder(path, done) { call("GET", "/game/scan-folder?path=" + encodeURIComponent(path), done) }
    function manualMatches(name, done) {
        catalogGames({q: name.trim(), page: 1, pageSize: 12}, function(status, body) {
            done(status === 200 ? (body.items || []).filter(item => item.slug && item.name) : null)
        })
    }
    function identityLabel(identity) {
        const stores = {steam: "Steam", epic: "Epic", gog: "GOG", amazon: "Amazon"}
        return identity && stores[identity.store] && identity.id ? qsTr("%1 · ID %2").arg(stores[identity.store]).arg(identity.id) : ""
    }
    function manualMatchLabel(item) {
        return [item.releaseYear, (item.platforms || []).map(p => p.name || p.slug).join(", ")].filter(Boolean).join(" · ")
    }
    function libraryRoots(done) { call("GET", "/library/roots", done) }
    function setLibraryRoot(action, path, done) {
        call("POST", "/library/roots/set", function(status, body) {
            if (status === 200) api.refresh()
            if (done) done(status, body)
        }, {action: action, path: path})
    }
    function setInstallRoot(path, done) {
        call("POST", "/settings/install-root", function(status, body) {
            if (status === 200) api.installRoot = body.install_root || ""
            if (done) done(status, body)
        }, {path: path})
    }
    function setAnimatedBackground(enabled, done) {
        call("POST", "/settings/animated-background", function(status, body) {
            if (status === 200) api.animatedBackground = body.animated_background !== false
            if (done) done(status, body)
        }, {enabled: enabled})
    }
    function setGlassEffect(enabled, done) {
        call("POST", "/settings/glass", function(status, body) {
            if (status === 200) api.glassEffect = body.glass_effect !== false
            if (done) done(status, body)
        }, {enabled: enabled})
    }
    function setSounds(changes, done) {
        call("POST", "/settings/sounds", function(status, body) {
            if (status === 200) {
                api.uiSounds = body.ui_sounds !== false
                api.uiSoundVolume = body.ui_sound_volume
                api.uiSoundPack = body.ui_sound_pack
            }
            if (done) done(status, body)
        }, changes)
    }
    function setDisplayName(name, done) {
        call("POST", "/settings/profile", function(status, body) {
            if (status === 200) { api.userName = body.user_name || ""; api.displayName = body.display_name || "" }
            if (done) done(status, body)
        }, {display_name: name})
    }
    function setIntro(enabled, done) {
        call("POST", "/settings/intro", function(status, body) {
            if (status === 200) api.introEnabled = body.intro_enabled !== false
            if (done) done(status, body)
        }, {enabled: enabled})
    }
    // Audio y mandos (ajustes de Big Mode)
    function loadAudioDevices(done) { call("GET", "/audio/devices", done) }
    function setInputDevice(source, done) { call("POST", "/audio/input/set", done, {source: source}) }
    function setAudioLevel(target, changes, done) { call("POST", "/audio/level", done, Object.assign({target: target}, changes)) }
    function loadStores(done) { call("GET", "/stores", done) }
    function storeLoginUrl(store, done) { call("GET", "/stores/login-url?store=" + encodeURIComponent(store), done) }
    function storeLogin(store, code, done) { call("POST", "/stores/login", done, {store: store, code: code}) }
    function storeLogout(store, done) { call("POST", "/stores/logout", done, {store: store}) }
    function storeInstall(store, id, title, destination, done) { call("POST", "/stores/install", done, {store: store, id: id, title: title, destination: destination}) }
    function clearStoresWebSession(done) { call("POST", "/stores/web-session/clear", done, {}) }
    function storeLibrary(store, done) { call("GET", "/stores/library?store=" + encodeURIComponent(store), done) }
    function loadPads(done) { call("GET", "/pads", done) }
    function setPadSettings(id, changes, done) { call("POST", "/pads/settings", done, Object.assign({id: id}, changes)) }
    function rumblePad(id, done) { call("POST", "/pads/rumble", done, {id: id, strong: 0.7, weak: 0.7, ms: 350}) }
    function setMangohud(enabled, done) {
        call("POST", "/settings/mangohud", function(status, body) {
            if (status === 200) api.mangohud = body.mangohud === true
            if (done) done(status, body)
        }, {enabled: enabled})
    }
    function setUpdateCheck(enabled, done) {
        call("POST", "/settings/update-check", function(status, body) {
            if (status === 200) api.updateCheck = body.update_check !== false
            if (done) done(status, body)
        }, {enabled: enabled})
    }
    function setLanguage(language, done) {
        const changed = api.language !== language
        call("POST", "/settings/language", function(status, body) {
            if (status === 200) {
                Qt.uiLanguage = language === "en" ? "en_US" : "es"
                api.language = language
                api.loadPreferences()
            }
            if (done) done(status, body)
            if (status === 200 && changed) Qt.callLater(function() { Qt.exit(42) })
        }, {language: language})
    }
    function scanRoms(path, done) { call("GET", "/rom/scan?path=" + encodeURIComponent(path || ""), done) }
    function addRom(path, name, system, emulator, catalogSlug, done) {
        call("POST", "/rom/add", function(status, body) {
            if (status === 200) api.refresh()
            if (done) done(status, body)
        }, {path: path, name: name, system: system, emulator: emulator, catalogSlug: catalogSlug || ""})
    }
    function removeGame(g, done) { call("POST", "/game/remove?id=" + encodeURIComponent(g.id), function (st, b) { if (st === 200) api.refresh(); done(st, b) }) }

    function reportMenu(open) { api.menuOpen = open; call("POST", "/menu/state?open=" + (open ? "1" : "0"), function () { }) }
    function power(action) {
        call("POST", "/power?a=" + encodeURIComponent(action), function (status, body) {
            if (status !== 200) api.toast = (body && body.error) || qsTr("No se pudo ejecutar la acción")
        })
    }
    function toggleAppFav(a) {
        call("POST", "/app/fav?id=" + encodeURIComponent(a.id), function () { api.loadApps() })
    }

    function toggleFav(g) {
        if (!g) return
        call("POST", "/game/fav?id=" + encodeURIComponent(g.id), function () { api.refresh() })
    }

    // Mando: petición larga a /events (el servidor responde en cuanto hay un botón nuevo o a los 20 s)
    function pollPad() {
        if (!controlsEnabled || _pollingPad) return
        _pollingPad = true
        call("GET", "/events?since=" + padSeq + "&gameSince=" + gameRevision + "&padSince=" + padRevision + "&wait=20", function (status, body) {
            api._pollingPad = false
            if (!api.controlsEnabled) return
            if (status === 200) {
                const first = api.padSeq < 0
                api.padSeq = body.seq
                if (!first && api.gameRevision >= 0 && body.gameRevision !== api.gameRevision) api.refresh()
                api.gameRevision = body.gameRevision === undefined ? api.gameRevision : body.gameRevision
                api.padRevision = body.padRevision ?? -1
                api.padOn = body.padOn
                api.padName = body.padName
                api.padFamily = body.padFamily || body.padLayout || ""
                api.padBattery = body.padBattery || null
                api.covered = body.covered === true
                api.gameMode = body.gameMode ? body.gameMode.active === true : false
                api.shelfActive = body.shelfActive !== false
                if (!first) for (let i = 0; i < body.events.length; i++) api.padKey(body.events[i].key)
                Qt.callLater(function() { api.pollPad() })
            } else {
                retry.start()            // omnia-core no responde o el token cambió: reintenta sin saturar
            }
        })
    }
    property Timer retry: Timer { interval: 2000; onTriggered: { api.padSeq = -1; api.pollPad() } }
    // Si Desktop abre mientras systemd aún inicia/reinicia omnia-core, vuelve a comprobar
    // la conexión cada 2 s y recupera también un token regenerado tras un reinicio.
    property Timer serviceRetry: Timer {
        interval: 2000; repeat: true
        running: api.autoStart && !api.ok
        onTriggered: { if (!api.ok) api.refresh() }
    }
    property Timer audioPoll: Timer { interval: api.audioActive ? 42 : 1000; repeat: true; running: api.controlsEnabled && api.ok && !api.covered && !api.gameRunning && !api.menuOpen; triggeredOnStart: true; onTriggered: api.pollAudio() }

    property Timer systemPoll: Timer { interval: 3000; repeat: true; running: api.systemEnabled && api.ok && !api.gameRunning; triggeredOnStart: true; onTriggered: api.pollSystem() }
    property Timer preferencesPoll: Timer { interval: 5000; repeat: true; running: api.controlsEnabled && api.ok; triggeredOnStart: true; onTriggered: api.loadPreferences() }

    Component.onCompleted: {
        if (!autoStart) return
        port = parseInt(arg("--port", "47831"))
        tokenPath = arg("--token", "")
        loadPreferences()
        refresh()
        _started = true
        if (controlsEnabled) pollPad()
    }
}
