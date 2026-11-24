pragma ComponentBehavior: Bound

import QtQuick

/**
 * Ajustes de Big Mode, navegables con mando, teclado y ratón. Cuatro categorías (LB/RB o Tab para cambiar):
 *   General · Sonido y bienvenida · Audio (salida y micrófono) · Mandos (iconos, zona muerta, vibración, apodo y prueba en vivo).
 * Filas: interruptor, selector (◀ ▶), deslizador (◀ ▶) y acción. ↑↓ mueve, ←→ ajusta, A/Enter activa, B/Esc vuelve.
 */
Item {
    id: set
    required property var host
    signal back()
    readonly property real s: set.host.s
    readonly property var api: set.host.api
    property string msg: ""
    property int tab: 0
    property int cur: 0
    property var audio: ({})
    property var pads: []
    property var discord: ({})
    property bool discordLoaded: false
    property bool padsLoaded: false
    property bool testOpen: false
    property string testId: ""
    property real backHeld: 0
    readonly property var tabNames: [qsTr("General"), qsTr("Sonido"), qsTr("Audio"), qsTr("Mandos"), qsTr("Discord")]
    readonly property var familyNames: [qsTr("Automático"), "Xbox", "PlayStation", "Nintendo Switch", "Steam Deck"]
    readonly property var familyIds: ["auto", "xbox", "ps", "switch", "deck"]

    function play(name) { if (set.host.sfx) set.host.sfx.play(name) }
    function note(text) { set.msg = text; msgTimer.restart() }
    function saved(status, body, ok) { set.note(status === 200 ? (ok || qsTr("Ajuste guardado.")) : ((body && body.error) || qsTr("No se pudo guardar el ajuste."))) }
    function pct(v) { return Math.round(v) + " %" }
    function padLabel(p) { return (p.nickname || p.name) + (p.battery && p.battery.level !== undefined ? "  ·  " + p.battery.level + " %" + (p.battery.charging ? " ⚡" : "") : "") }
    function indexOfId(list, key, value) { for (let i = 0; i < list.length; i++) if (list[i][key] === value) return i; return -1 }

    // ---------------- filas de cada categoría ----------------
    function buildRows() {
        const a = set.api, out = []
        const H = function(t) { out.push({ kind: "header", label: t }) }
        if (set.tab === 0) {
            H(qsTr("Aplicación"))
            out.push({ id: "lang", kind: "choice", label: qsTr("Idioma"), desc: qsTr("Los textos de Omnia se mostrarán en el idioma seleccionado."), text: a.language === "en" ? "English" : qsTr("Español") })
            out.push({ id: "anim", kind: "toggle", label: qsTr("Fondo animado"), desc: qsTr("Puntos y líneas con los colores del juego. Se detiene mientras juegas."), on: a.animatedBackground })
            out.push({ id: "upd", kind: "toggle", label: qsTr("Buscar actualizaciones de ports"), desc: qsTr("Avisa cuando un port instalado desde el catálogo tiene una versión nueva. Nunca se actualiza sin que lo confirmes."), on: a.updateCheck })
            out.push(a.mangohudInstalled || a.mangohud
                ? { id: "mango", kind: "toggle", label: qsTr("Monitor de rendimiento en los juegos"), desc: qsTr("Muestra FPS, GPU, CPU, VRAM y RAM en una sola línea, con el estilo de Omnia."), on: a.mangohud }
                : { id: "mangoinfo", kind: "info", label: qsTr("Monitor de rendimiento en los juegos"), desc: qsTr("Necesita MangoHud: instálalo desde el gestor de paquetes.") })
            H(qsTr("Biblioteca"))
            out.push({ id: "scan", kind: "action", label: qsTr("Sincronizar juegos"), desc: qsTr("El catálogo y las imágenes publicados se consultan desde Omnia Backend."), text: qsTr("Buscar juegos") })
        } else if (set.tab === 1) {
            H(qsTr("Sonidos de la interfaz"))
            out.push({ id: "snd", kind: "toggle", label: qsTr("Sonidos"), desc: qsTr("Al mover la selección, aceptar, volver, cambiar de página y avisos. Nunca suenan mientras juegas."), on: a.uiSounds })
            out.push({ id: "vol", kind: "slider", label: qsTr("Volumen de los sonidos"), desc: qsTr("Es independiente del volumen del sistema."), value: a.uiSoundVolume, min: 0, max: 100, step: 10 })
            const packs = a.uiSoundPacks || []
            const pk = packs.find(function(p) { return p.id === a.uiSoundPack })
            out.push({ id: "pack", kind: "choice", label: qsTr("Paquete de sonidos"), desc: qsTr("Cada paquete es un conjunto de sonidos distinto; se cambia al instante."), text: pk ? pk.label : a.uiSoundPack })
            out.push({ id: "sndtest", kind: "action", label: qsTr("Probar los sonidos"), desc: qsTr("Reproduce los de este paquete uno tras otro."), text: qsTr("Probar") })
            H(qsTr("Bienvenida"))
            out.push({ id: "myname", kind: "action", label: qsTr("Tu nombre en la bienvenida"), desc: a.displayName ? qsTr("Te saluda como «%1». Déjalo vacío para usar el nombre de tu usuario.").arg(a.displayName) : qsTr("Ahora te saluda con el nombre de tu usuario (%1).").arg(a.userName || "—"), text: qsTr("Cambiar") })
            out.push({ id: "intro", kind: "toggle", label: qsTr("Pantalla de bienvenida"), desc: qsTr("Animación con sonido al abrir Big Mode. Se salta pulsando cualquier tecla o botón."), on: a.introEnabled })
            out.push({ id: "introplay", kind: "action", label: qsTr("Ver la bienvenida otra vez"), desc: "", text: qsTr("Reproducir") })
        } else if (set.tab === 2) {
            const o = set.audio.output || {}, m = set.audio.input || {}
            if (!set.audio.output) { out.push({ id: "loading", kind: "info", label: qsTr("Leyendo los dispositivos de audio…"), desc: "" }); return out }
            H(qsTr("Salida de audio"))
            if (o.error) out.push({ id: "outinfo", kind: "info", label: qsTr("Salida de audio"), desc: o.error })
            else {
                const cur = (o.items || []).find(function(i) { return i.current })
                out.push({ id: "out", kind: "choice", label: qsTr("Dispositivo"), desc: qsTr("Lo que ya suena pasa al nuevo dispositivo."), text: cur ? cur.label : qsTr("(ninguno)") })
                out.push({ id: "outvol", kind: "slider", label: qsTr("Volumen"), desc: "", value: o.volume || 0, min: 0, max: 100, step: 5 })
                out.push({ id: "outmute", kind: "toggle", label: qsTr("Silenciar la salida"), desc: "", on: !!o.muted })
            }
            H(qsTr("Micrófono"))
            if (m.error) out.push({ id: "ininfo", kind: "info", label: qsTr("Micrófono"), desc: m.error })
            else if (!(m.items || []).length) out.push({ id: "ininfo", kind: "info", label: qsTr("Micrófono"), desc: qsTr("No hay ningún micrófono conectado.") })
            else {
                const cur = m.items.find(function(i) { return i.current })
                out.push({ id: "in", kind: "choice", label: qsTr("Dispositivo"), desc: qsTr("Lo que ya graba pasa al nuevo micrófono."), text: cur ? cur.label : qsTr("(ninguno)") })
                out.push({ id: "invol", kind: "slider", label: qsTr("Volumen de entrada"), desc: "", value: m.volume || 0, min: 0, max: 100, step: 5 })
                out.push({ id: "inmute", kind: "toggle", label: qsTr("Silenciar el micrófono"), desc: "", on: !!m.muted })
            }
        } else if (set.tab === 3) {
            if (!set.padsLoaded) out.push({ id: "loading", kind: "info", label: qsTr("Buscando mandos…"), desc: "" })
            else if (!set.pads.length) out.push({ id: "nopad", kind: "info", label: qsTr("No hay ningún mando conectado"), desc: qsTr("Conecta uno por USB o Bluetooth y aparecerá aquí.") })
            for (const p of set.pads) {
                H(set.padLabel(p))
                out.push({ id: "ptest", pad: p.id, kind: "action", label: qsTr("Probar botones y sticks"), desc: qsTr("Pantalla en vivo: cada botón, stick y gatillo se ilumina al usarlo."), text: qsTr("Abrir") })
                out.push({ id: "prum", pad: p.id, kind: "action", label: qsTr("Probar la vibración"), desc: qsTr("Si el mando no admite vibración, se avisa."), text: qsTr("Vibrar") })
                const overridden = p.family !== p.detectedFamily
                out.push({ id: "pfam", pad: p.id, kind: "choice", label: qsTr("Iconos de los botones"), desc: qsTr("Detectado: %1. «Automático» usa el del mando.").arg(set.familyNames[Math.max(1, set.familyIds.indexOf(p.detectedFamily))] || p.detectedFamily),
                             text: set.familyNames[overridden ? Math.max(0, set.familyIds.indexOf(p.family)) : 0] })
                out.push({ id: "pdz", pad: p.id, kind: "slider", label: qsTr("Zona muerta del stick"), desc: qsTr("Cuánto hay que inclinar el stick para que cuente. Súbela si el cursor se mueve solo."), value: Math.round(p.deadzone * 100), min: 5, max: 40, step: 5 })
                out.push({ id: "phap", pad: p.id, kind: "toggle", label: qsTr("Vibración al navegar"), desc: qsTr("Un toque suave al aceptar y al cambiar de página (si el mando lo admite)."), on: p.haptics })
                out.push({ id: "pname", pad: p.id, kind: "action", label: qsTr("Apodo del mando"), desc: p.nickname ? qsTr("Ahora: %1").arg(p.nickname) : qsTr("Sin apodo: se muestra el nombre del fabricante."), text: qsTr("Cambiar") })
            }
        } else {
            const d = set.discord
            if (!set.discordLoaded) { out.push({ id: "loading", kind: "info", label: qsTr("Consultando Discord…"), desc: "" }); return out }
            H(qsTr("Presencia"))
            out.push({ id: "dcon", kind: "toggle", label: qsTr("Mostrar a qué juego juego"), desc: qsTr("Tus amigos de Discord ven «Jugando a …» con el tiempo de partida mientras juegas desde Omnia. Es opcional y está apagado al instalar."), on: !!d.enabled })
            out.push({ id: "dcid", kind: "action", label: qsTr("Application ID"), desc: d.app_id ? qsTr("Guardado: %1").arg(d.app_id) : qsTr("Falta. Créalo gratis en discord.com/developers (Nueva aplicación, nómbrala «Omnia») y copia su Application ID."), text: d.app_id ? qsTr("Cambiar") : qsTr("Escribir") })
            const state = !d.enabled ? qsTr("Apagado.")
                : !d.app_id_set ? qsTr("Falta el Application ID.")
                : d.connected ? qsTr("Conectado como %1.").arg(d.user || "Discord")
                : d.socket ? qsTr("Discord está abierto pero no aceptó la conexión; revisa el Application ID.")
                : qsTr("Abre Discord en este equipo para conectar.")
            out.push({ id: "dcstate", kind: "info", label: qsTr("Estado"), desc: state })
        }
        return out
    }
    readonly property var rows: set.buildRows()
    function selectable(i) { return i >= 0 && i < set.rows.length && set.rows[i].kind !== "header" && set.rows[i].kind !== "info" }
    function firstSelectable() { for (let i = 0; i < set.rows.length; i++) if (set.selectable(i)) return i; return 0 }
    function move(d) {
        let i = set.cur
        for (let n = 0; n < set.rows.length; n++) {
            i += d
            if (i < 0 || i >= set.rows.length) return
            if (set.selectable(i)) { set.cur = i; set.play("move"); return }
        }
    }
    onRowsChanged: if (!set.selectable(set.cur)) set.cur = set.firstSelectable()
    function setTab(t) {
        set.tab = (t + set.tabNames.length) % set.tabNames.length
        set.cur = set.firstSelectable()
        set.play("page")
        if (set.tab === 2) set.refreshAudio()
        if (set.tab === 3) set.refreshPads()
        if (set.tab === 4) set.refreshDiscord()
    }
    function refreshAudio() { set.api.loadAudioDevices(function(status, body) { if (status === 200) set.audio = body }) }
    function refreshDiscord() { set.api.call("GET", "/discord", function(status, body) { if (status === 200) { set.discord = body; set.discordLoaded = true } }) }
    function refreshPads() { set.api.loadPads(function(status, body) { if (status === 200) { set.pads = body.pads || []; set.padsLoaded = true } }) }
    onVisibleChanged: if (visible) { set.msg = ""; set.testOpen = false; set.audio = ({}); set.padsLoaded = false; set.discordLoaded = false; set.setTabQuiet() }
    function setTabQuiet() { set.cur = set.firstSelectable(); if (set.tab === 2) set.refreshAudio(); if (set.tab === 3) set.refreshPads(); if (set.tab === 4) set.refreshDiscord() }

    // ---------------- acciones ----------------
    function clampStep(r, dir) { return Math.max(r.min, Math.min(r.max, r.value + dir * r.step)) }
    function adjust(r, dir) {
        if (r.kind === "slider") {
            const v = set.clampStep(r, dir)
            if (v === r.value) return
            set.applySlider(r, v)
        } else if (r.kind === "choice") set.cycle(r, dir)
        else if (r.kind === "toggle" && dir !== 0) set.activate(r)
    }
    function applySlider(r, v) {
        const a = set.api
        if (r.id === "vol") { a.uiSoundVolume = v; a.setSounds({ volume: v }, function(st, b) { if (st !== 200) set.saved(st, b) }); set.play("move") }
        else if (r.id === "outvol" || r.id === "invol") {
            const t = r.id === "outvol" ? "output" : "input"
            a.setAudioLevel(t, { volume: v }, function(st, b) { if (st === 200) { const au = Object.assign({}, set.audio); au[t] = Object.assign({}, au[t], { volume: b.volume, muted: b.muted }); set.audio = au } else set.saved(st, b) })
            set.play("move")
        } else if (r.id === "pdz") a.setPadSettings(r.pad, { deadzone: v / 100 }, function(st, b) { if (st === 200) set.refreshPads(); else set.saved(st, b) })
    }
    function cycle(r, dir) {
        const a = set.api
        if (r.id === "lang") a.setLanguage(a.language === "en" ? "es" : "en", function(st, b) { set.saved(st, b, qsTr("Idioma guardado.")) })
        else if (r.id === "pack") {
            const packs = a.uiSoundPacks || []
            if (packs.length < 2) { set.note(qsTr("No hay otros paquetes instalados.")); return }
            const i = Math.max(0, set.indexOfId(packs, "id", a.uiSoundPack))
            const next = packs[(i + dir + packs.length) % packs.length].id
            a.uiSoundPack = next
            a.setSounds({ pack: next }, function(st, b) { set.saved(st, b, qsTr("Paquete de sonidos cambiado.")); set.play("confirm") })
        } else if (r.id === "out" || r.id === "in") {
            const input = r.id === "in", d = set.audio[input ? "input" : "output"] || {}, items = d.items || []
            if (items.length < 2) return
            const i = Math.max(0, items.findIndex(function(x) { return x.current }))
            const nx = items[(i + dir + items.length) % items.length]
            const done = function(st, b) { if (st === 200 || (b && b.ok)) { set.refreshAudio(); set.play("confirm") } else set.saved(st, b) }
            if (input) a.setInputDevice(nx.source, done)
            else a.call("POST", "/audio/set?sink=" + encodeURIComponent(nx.sink) + "&port=" + encodeURIComponent(nx.port || ""), done)
        } else if (r.id === "pfam") {
            const p = set.pads.find(function(x) { return x.id === r.pad }); if (!p) return
            const cur = p.family === p.detectedFamily ? 0 : Math.max(0, set.familyIds.indexOf(p.family))
            const next = set.familyIds[(cur + dir + set.familyIds.length) % set.familyIds.length]
            a.setPadSettings(r.pad, { family: next }, function(st, b) { if (st === 200) { set.refreshPads(); set.play("confirm") } else set.saved(st, b) })
        }
    }
    function activate(r) {
        const a = set.api
        switch (r.id) {
        case "anim": a.setAnimatedBackground(!r.on, function(st, b) { set.saved(st, b) }); set.play("toggle"); break
        case "upd": a.setUpdateCheck(!r.on, function(st, b) { set.saved(st, b) }); set.play("toggle"); break
        case "mango": a.setMangohud(!r.on, function(st, b) { set.saved(st, b) }); set.play("toggle"); break
        case "scan": a.call("POST", "/library/refresh", function(st) { a.refresh(); a.notify(st === 200 ? qsTr("Biblioteca actualizada.") : qsTr("No se pudo actualizar la biblioteca.")) }); set.play("confirm"); break
        case "snd": a.uiSounds = !r.on; a.setSounds({ enabled: !r.on }, function(st, b) { set.saved(st, b); set.play("toggle") }); break
        case "pack": case "lang": case "out": case "in": case "pfam": set.cycle(r, 1); break
        case "sndtest": set.runSoundTest(); break
        case "myname": {
            let pending = a.displayName
            set.host.openKeyboardFor(pending, function(v) { pending = v }, function() { a.setDisplayName(pending, function(st, b) { set.saved(st, b, qsTr("Nombre guardado.")) }) })
            break
        }
        case "intro": a.setIntro(!r.on, function(st, b) { set.saved(st, b) }); set.play("toggle"); break
        case "introplay": set.play("confirm"); set.host.playIntro(); break
        case "outmute": case "inmute": {
            const t = r.id === "outmute" ? "output" : "input"
            a.setAudioLevel(t, { muted: !r.on }, function(st, b) { if (st === 200) { const au = Object.assign({}, set.audio); au[t] = Object.assign({}, au[t], { volume: b.volume, muted: b.muted }); set.audio = au } else set.saved(st, b) })
            set.play("toggle"); break
        }
        case "dcon": a.call("POST", "/settings/discord", function(st, b) { if (st === 200) { set.discord = b; set.discordLoaded = true } else set.saved(st, b) }, { enabled: !r.on }); set.play("toggle"); break
        case "dcid": {
            let pending = set.discord.app_id || ""
            set.host.openKeyboardFor(pending, function(v) { pending = v }, function() { a.call("POST", "/settings/discord", function(st, b) { if (st === 200) { set.discord = b; set.note(qsTr("Application ID guardado.")) } else set.saved(st, b) }, { app_id: pending }) })
            break
        }
        case "phap": a.setPadSettings(r.pad, { haptics: !r.on }, function(st, b) { if (st === 200) set.refreshPads(); else set.saved(st, b) }); set.play("toggle"); break
        case "prum": a.rumblePad(r.pad, function(st, b) { set.note(st === 200 ? qsTr("Vibrando…") : ((b && b.error) || qsTr("No se pudo hacer vibrar el mando."))) }); break
        case "ptest": set.testId = r.pad; set.testOpen = true; set.backHeld = 0; set.play("open"); break
        case "pname": {
            const p = set.pads.find(function(x) { return x.id === r.pad }); if (!p) break
            let pending = p.nickname || ""
            set.host.openKeyboardFor(pending, function(v) { pending = v }, function() { a.setPadSettings(r.pad, { nickname: pending }, function(st, b) { if (st === 200) set.refreshPads(); else set.saved(st, b) }) })
            break
        }
        }
    }
    property var soundSeq: []
    function runSoundTest() { set.soundSeq = ["move", "confirm", "back", "menu", "page", "toggle", "done", "pad-on", "pad-off", "error"]; soundTimer.start() }
    Timer { id: soundTimer; interval: 520; repeat: true; onTriggered: { if (!set.soundSeq.length) { stop(); return } set.play(set.soundSeq[0]); set.soundSeq = set.soundSeq.slice(1) } }
    Timer { id: msgTimer; interval: 3500; onTriggered: set.msg = "" }
    Timer { interval: 1500; repeat: true; running: set.visible && !set.testOpen && set.tab === 3; onTriggered: set.refreshPads() }
    Timer { interval: 2500; repeat: true; running: set.visible && set.tab === 2; onTriggered: set.refreshAudio() }
    Timer { interval: 3000; repeat: true; running: set.visible && set.tab === 4; onTriggered: set.refreshDiscord() }

    // ---------------- entrada ----------------
    function pad(k) {
        if (set.testOpen) return
        const r = set.rows[set.cur]
        if (k === "u") set.move(-1)
        else if (k === "d") set.move(1)
        else if (k === "l" && r) set.adjust(r, -1)
        else if (k === "r" && r) set.adjust(r, 1)
        else if (k === "A" && r) { if (r.kind === "slider") set.adjust(r, 1); else set.activate(r) }
        else if (k === "B") { set.play("back"); set.back() }
        else if (k === "LB") set.setTab(set.tab - 1)
        else if (k === "RB") set.setTab(set.tab + 1)
    }
    focus: visible
    Keys.onPressed: function(e) {
        const r = set.rows[set.cur]
        if (set.testOpen) { if (e.key === Qt.Key_Escape) { set.testOpen = false; set.play("close") } e.accepted = true; return }
        if (e.key === Qt.Key_Up) set.move(-1)
        else if (e.key === Qt.Key_Down) set.move(1)
        else if (e.key === Qt.Key_Left && r) set.adjust(r, -1)
        else if (e.key === Qt.Key_Right && r) set.adjust(r, 1)
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) && r) { if (r.kind === "slider") set.adjust(r, 1); else set.activate(r) }
        else if (e.key === Qt.Key_Tab) set.setTab(set.tab + 1)
        else if (e.key === Qt.Key_Backtab) set.setTab(set.tab - 1)
        else if (e.key === Qt.Key_Escape) { set.play("back"); set.back() }
        else { e.accepted = false; return }
        e.accepted = true
    }

    // ---------------- interfaz ----------------
    Rectangle { anchors.fill: parent; color: set.host.base }
    Rectangle {
        id: backB
        x: set.s * 48; y: set.s * 30
        width: bRow.implicitWidth + set.s * 44; height: set.s * 54; radius: height / 2
        color: Qt.rgba(0.05, 0.08, 0.12, 0.70); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.26)
        Row {
            id: bRow; anchors.centerIn: parent; spacing: set.s * 10
            LucideIcon { width: set.s * 26; height: set.s * 26; name: "chevron-left"; color: set.host.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: qsTr("Volver"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 24; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { set.play("back"); set.back() } }
    }
    PadBattery {
        api: set.api; uiScale: set.s; uiFont: set.host.uiFont; ink: set.host.ink; muted: set.host.ink2
        anchors { right: parent.right; rightMargin: set.s * 48; verticalCenter: backB.verticalCenter }
    }
    Text { id: title; anchors { left: backB.right; leftMargin: set.s * 22; verticalCenter: backB.verticalCenter } text: qsTr("Ajustes"); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 34; font.weight: Font.DemiBold }

    Row {   // categorías
        id: tabsRow
        anchors { left: parent.left; leftMargin: set.s * 48; top: backB.bottom; topMargin: set.s * 26 }
        spacing: set.s * 12
        Repeater {
            model: set.tabNames
            delegate: Rectangle {
                id: chip
                required property string modelData
                required property int index
                readonly property bool on: set.tab === index
                width: chipText.implicitWidth + set.s * 44; height: set.s * 48; radius: height / 2
                color: on ? set.host.accent : Qt.rgba(1, 1, 1, 0.07)
                border.width: 1; border.color: on ? set.host.ring : Qt.rgba(1, 1, 1, 0.14)
                Text { id: chipText; anchors.centerIn: parent; text: chip.modelData; color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 22; font.weight: chip.on ? Font.DemiBold : Font.Normal }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: set.setTab(chip.index) }
            }
        }
    }
    Row {   // guía de LB / RB junto a las categorías
        anchors { left: tabsRow.right; leftMargin: set.s * 18; verticalCenter: tabsRow.verticalCenter }
        spacing: set.s * 6
        visible: set.host.padOn
        PadGlyph { size: set.s * 36; family: set.api.padFamily || "xbox"; key: "LB" }
        PadGlyph { size: set.s * 36; family: set.api.padFamily || "xbox"; key: "RB" }
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: tabsRow.bottom; bottom: parent.bottom; leftMargin: set.s * 48; rightMargin: set.s * 48; topMargin: set.s * 20; bottomMargin: set.s * 70 }
        clip: true
        spacing: set.s * 12
        model: set.rows
        currentIndex: set.cur
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool header: modelData.kind === "header"
            readonly property bool focusRow: index === set.cur && !header && modelData.kind !== "info"
            width: list.width
            height: header ? set.s * 44 : (modelData.desc ? set.s * 108 : set.s * 84)
            Text {
                visible: row.header
                anchors { left: parent.left; bottom: parent.bottom; bottomMargin: set.s * 4 }
                text: row.modelData.label; color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 22; font.weight: Font.DemiBold
            }
            Rectangle {
                visible: !row.header
                anchors.fill: parent
                radius: set.s * 22
                color: Qt.rgba(0.082, 0.114, 0.153, row.focusRow ? 0.98 : 0.88)
                border.width: row.focusRow ? Math.max(2, set.s * 3) : 1
                border.color: row.focusRow ? set.host.ring : Qt.rgba(1, 1, 1, 0.10)
                Column {
                    anchors { left: parent.left; right: ctrl.left; verticalCenter: parent.verticalCenter; leftMargin: set.s * 24; rightMargin: set.s * 16 }
                    spacing: set.s * 2
                    Text { width: parent.width; text: row.modelData.label; elide: Text.ElideRight; color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 26; font.weight: Font.DemiBold }
                    Text { visible: !!row.modelData.desc; width: parent.width; text: row.modelData.desc || ""; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; color: set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 19 }
                }
                Item {
                    id: ctrl
                    anchors { right: parent.right; rightMargin: set.s * 26; verticalCenter: parent.verticalCenter }
                    width: row.modelData.kind === "slider" ? set.s * 420 : (row.modelData.kind === "toggle" ? set.s * 86 : choiceBox.implicitWidth)
                    height: set.s * 52
                    // interruptor
                    Rectangle {
                        visible: row.modelData.kind === "toggle"
                        anchors.fill: parent; radius: height / 2
                        color: row.modelData.on ? set.host.accent : Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                        Rectangle { width: parent.height - set.s * 10; height: width; radius: width / 2; y: set.s * 5; x: row.modelData.on ? parent.width - width - set.s * 5 : set.s * 5; color: set.host.ink; Behavior on x { NumberAnimation { duration: 120 } } }
                    }
                    // selector ◀ valor ▶ o botón de acción
                    Rectangle {
                        id: choiceBox
                        visible: row.modelData.kind === "choice" || row.modelData.kind === "action"
                        implicitWidth: Math.min(set.s * 460, choiceRow.implicitWidth + set.s * 44)
                        width: implicitWidth; height: parent.height; radius: height / 2
                        color: row.modelData.kind === "action" ? set.host.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
                        Row {
                            id: choiceRow; anchors.centerIn: parent; spacing: set.s * 14
                            Text { visible: row.modelData.kind === "choice"; text: "◀"; color: row.focusRow ? set.host.ink : set.host.ink2; font.pixelSize: set.s * 18; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: row.modelData.text || ""; color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 22; elide: Text.ElideRight; width: Math.min(implicitWidth, set.s * 370); anchors.verticalCenter: parent.verticalCenter }
                            Text { visible: row.modelData.kind === "choice"; text: "▶"; color: row.focusRow ? set.host.ink : set.host.ink2; font.pixelSize: set.s * 18; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    // deslizador
                    Item {
                        visible: row.modelData.kind === "slider"
                        anchors.fill: parent
                        Rectangle { id: track; anchors { left: parent.left; right: valText.left; rightMargin: set.s * 18; verticalCenter: parent.verticalCenter } height: set.s * 10; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.16)
                            Rectangle { width: parent.width * Math.max(0, Math.min(1, ((row.modelData.value || 0) - (row.modelData.min || 0)) / Math.max(1, (row.modelData.max || 1) - (row.modelData.min || 0)))); height: parent.height; radius: height / 2; color: set.host.ring }
                        }
                        Text { id: valText; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: set.s * 74; horizontalAlignment: Text.AlignRight; text: set.pct(row.modelData.value || 0); color: set.host.ink; font.family: set.host.uiFont; font.pixelSize: set.s * 22 }
                        MouseArea {
                            anchors { left: track.left; right: track.right; verticalCenter: parent.verticalCenter } height: set.s * 40
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(m) { const r = row.modelData; set.cur = row.index; const v = r.min + Math.round(((m.x / width) * (r.max - r.min)) / r.step) * r.step; set.applySlider(r, Math.max(r.min, Math.min(r.max, v))) }
                        }
                    }
                }
                MouseArea {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: ctrl.left }
                    enabled: row.modelData.kind !== "info"
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { set.cur = row.index; if (row.modelData.kind === "slider") set.adjust(row.modelData, 1); else set.activate(row.modelData) }
                }
                MouseArea {
                    anchors.fill: ctrl
                    enabled: row.modelData.kind === "toggle" || row.modelData.kind === "choice" || row.modelData.kind === "action"
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { set.cur = row.index; set.activate(row.modelData) }
                }
            }
        }
    }

    Text {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: set.s * 48; rightMargin: set.s * 48; bottomMargin: set.s * 26 }
        text: set.msg || qsTr("↑↓ mover · ◀ ▶ ajustar · A elegir · LB / RB cambiar de categoría · B volver")
        color: set.msg ? set.host.ink : set.host.ink2; font.family: set.host.uiFont; font.pixelSize: set.s * 20
        horizontalAlignment: Text.AlignHCenter
    }

    // ---------------- prueba en vivo de un mando ----------------
    Loader { anchors.fill: parent; active: set.testOpen; z: 20; sourceComponent: padTest }
    Component {
        id: padTest
        OmniaPadTest {
            host: set.host
            padId: set.testId
            onClosed: { set.testOpen = false; set.play("close") }
        }
    }
}
