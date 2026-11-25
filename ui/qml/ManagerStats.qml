import QtQuick
import QtQuick.Controls

// Estadísticas de juego de la app de escritorio: tiempo total, partidas, racha, actividad de los últimos días y los juegos más jugados.
Item {
    id: st
    property var manager
    property var api
    property int days: 14
    property bool allTime: false
    property var info: ({ totalSecs: 0, sessions: 0, gamesPlayed: 0, avgSessionSecs: 0, longest: null, streakDays: 0, days: [], recentSecs: 0, topAll: [], topRecent: [], historyComplete: true })
    property bool loaded: false
    readonly property real s: manager ? manager.s : 1
    readonly property var rows: allTime ? info.topAll : info.topRecent
    readonly property real maxRow: rows.length ? rows[0].secs : 1
    readonly property real maxDay: Math.max(1, Math.max.apply(null, (info.days || []).map(function(d) { return d.secs }).concat([1])))

    function open() { load() }
    function load() {
        api.call("GET", "/stats?days=" + st.days, function(code, body) {
            if (code === 200) { st.info = body; st.loaded = true }
        })
    }
    onDaysChanged: load()
    Timer { interval: 15000; repeat: true; running: st.visible; onTriggered: st.load() }

    function fmt(secs) {
        secs = Math.round(secs || 0)
        const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        if (h > 0) return qsTr("%1 h %2 min").arg(h).arg(m)
        if (m > 0) return qsTr("%1 min").arg(m)
        return secs > 0 ? qsTr("%1 s").arg(secs) : qsTr("0 min")
    }
    function gameOf(id) { return (api.games || []).find(function(g) { return g.id === id }) || null }
    function dayLabel(ts) { return Qt.locale().dayName(new Date(ts * 1000).getDay(), Locale.ShortFormat) }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + st.s * 60
        clip: true
        ScrollBar.vertical: ScrollBar {}
        Column {
            id: col
            x: st.s * 32; y: st.s * 24
            width: parent.width - st.s * 64
            spacing: st.s * 18

            Text { text: qsTr("Estadísticas"); color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 28; font.weight: Font.Bold }
            Text { text: qsTr("Tu actividad de juego, resumida."); color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13 }

            Row {
                spacing: st.s * 10
                Repeater {
                    model: [{ d: 7, l: qsTr("7 días") }, { d: 14, l: qsTr("14 días") }, { d: 30, l: qsTr("30 días") }]
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: st.days === modelData.d
                        width: chipText.implicitWidth + st.s * 34; height: st.s * 38; radius: height / 2
                        color: on ? "#45CFC9" : (ma.containsMouse ? st.manager.surface2 : st.manager.surface)
                        Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.l; color: chip.on ? "#0B0F14" : st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14; font.weight: Font.DemiBold }
                        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: st.days = chip.modelData.d }
                    }
                }
            }

            // tarjetas
            Row {
                spacing: st.s * 14
                Repeater {
                    model: [{ l: qsTr("Tiempo jugado"), v: st.fmt(st.info.totalSecs), n: qsTr("en total") },
                            { l: qsTr("Partidas"), v: String(st.info.sessions), n: st.info.sessions ? qsTr("media de %1").arg(st.fmt(st.info.avgSessionSecs)) : "" },
                            { l: qsTr("Juegos jugados"), v: String(st.info.gamesPlayed), n: "" },
                            { l: qsTr("Racha"), v: st.info.streakDays === 1 ? qsTr("1 día") : qsTr("%1 días").arg(st.info.streakDays), n: qsTr("seguidos jugando") }]
                    delegate: Rectangle {
                        required property var modelData
                        width: (col.width - st.s * 42) / 4; height: st.s * 96; radius: st.s * 14; color: st.manager.surface
                        Column {
                            anchors { left: parent.left; leftMargin: st.s * 16; verticalCenter: parent.verticalCenter } spacing: st.s * 4
                            Text { text: modelData.l; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13 }
                            Text { text: modelData.v; color: st.manager.ink; font.family: "Rajdhani"; font.pixelSize: st.s * 30; font.weight: Font.DemiBold }
                            Text { visible: modelData.n !== ""; text: modelData.n; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 12 }
                        }
                    }
                }
            }

            // actividad por día
            Rectangle {
                width: col.width; height: st.s * 230; radius: st.s * 14; color: st.manager.surface
                Text { x: st.s * 18; y: st.s * 14; text: qsTr("Actividad · %1 en los últimos %2 días").arg(st.fmt(st.info.recentSecs)).arg(st.days); color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 15; font.weight: Font.DemiBold }
                Row {
                    id: bars
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: st.s * 18; rightMargin: st.s * 18; bottomMargin: st.s * 30 }
                    height: st.s * 140
                    spacing: st.s * (st.days > 14 ? 4 : 8)
                    Repeater {
                        model: st.info.days || []
                        delegate: Item {
                            id: bar
                            required property var modelData
                            required property int index
                            width: (bars.width - bars.spacing * ((st.info.days || []).length - 1)) / Math.max(1, (st.info.days || []).length); height: bars.height
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: Math.max(bar.modelData.secs > 0 ? st.s * 4 : st.s * 2, bars.height * bar.modelData.secs / st.maxDay)
                                radius: st.s * 4
                                color: bar.modelData.secs <= 0 ? "#26FFFFFF" : (bar.index === (st.info.days || []).length - 1 ? "#45CFC9" : "#178C96")
                            }
                            Text { anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: st.s * 6 } visible: st.days <= 14
                                   text: st.dayLabel(bar.modelData.start); color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 11 }
                            MouseArea { id: barMa; anchors.fill: parent; hoverEnabled: true }
                            ToolTip.visible: barMa.containsMouse; ToolTip.text: new Date(bar.modelData.start * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " · " + st.fmt(bar.modelData.secs)
                        }
                    }
                }
            }

            // más jugados
            Rectangle {
                width: col.width; height: topCol.implicitHeight + st.s * 70; radius: st.s * 14; color: st.manager.surface
                Row {
                    x: st.s * 18; y: st.s * 14; spacing: st.s * 14
                    Text { text: qsTr("Más jugados"); color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 15; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: [{ a: false, l: qsTr("Últimos %1 días").arg(st.days) }, { a: true, l: qsTr("Todo el tiempo") }]
                        delegate: Text {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.l; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13; font.underline: st.allTime === modelData.a
                            color: st.allTime === modelData.a ? "#45CFC9" : st.manager.muted
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: st.allTime = modelData.a }
                        }
                    }
                }
                Column {
                    id: topCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: st.s * 18; rightMargin: st.s * 18; topMargin: st.s * 52 }
                    spacing: st.s * 8
                    Text { visible: st.rows.length === 0; text: st.loaded ? qsTr("Todavía no hay partidas en este periodo. Juega algo y vuelve.") : qsTr("Cargando…"); color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14 }
                    Repeater {
                        model: st.rows
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            width: topCol.width; height: st.s * 44
                            readonly property var game: st.gameOf(modelData.id)
                            Text { id: rank; width: st.s * 24; anchors.verticalCenter: parent.verticalCenter; text: String(row.index + 1); color: st.manager.muted; font.family: "Rajdhani"; font.pixelSize: st.s * 18 }
                            Rectangle { id: thumb; x: st.s * 28; width: st.s * 30; height: st.s * 40; radius: st.s * 5; color: st.manager.surface2; anchors.verticalCenter: parent.verticalCenter; clip: true
                                Image { anchors.fill: parent; source: row.game && row.game.portada ? row.game.portada : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.height: 120 } }
                            Text { x: st.s * 68; width: parent.width * 0.3; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: row.modelData.name; color: st.manager.ink; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 14 }
                            Rectangle {
                                x: parent.width * 0.36 + st.s * 40; anchors.verticalCenter: parent.verticalCenter
                                width: (parent.width * 0.64 - st.s * 190) * row.modelData.secs / st.maxRow; height: st.s * 10; radius: height / 2; color: "#178C96"
                            }
                            Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: st.fmt(row.modelData.secs) + "  ·  " + qsTr("%1 partidas").arg(row.modelData.plays); color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 13 }
                        }
                    }
                }
            }

            Text {
                width: col.width; wrapMode: Text.Wrap; color: st.manager.muted; font.family: "Hanken Grotesk"; font.pixelSize: st.s * 12
                text: (st.info.longest ? qsTr("Partida más larga: %1 en «%2». ").arg(st.fmt(st.info.longest.secs)).arg(st.info.longest.name) : "")
                      + qsTr("Solo cuentan las partidas lanzadas desde Omnia y de más de 10 segundos. Los datos se quedan en este equipo.")
                      + (st.info.historyComplete ? "" : " " + qsTr("El detalle por días usa las últimas 1000 partidas."))
            }
        }
    }
}
