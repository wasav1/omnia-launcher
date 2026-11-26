pragma ComponentBehavior: Bound

import QtQuick

/** Encabezado de Big Mode: navegación principal, búsqueda, estado del sistema y cierre. */
Item {
    id: head
    required property var host
    readonly property var api: head.host.api
    property alias searchField: searchInput
    height: head.host.s * 54
    z: 2
    visible: head.host.mainNavVisible

    Row {
        id: brand
        anchors.verticalCenter: parent.verticalCenter
        spacing: head.host.s * 14
        Image {
            width: head.host.s * 44; height: head.host.s * 44
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("images/omnia-mark.svg")
            fillMode: Image.PreserveAspectFit
            sourceSize.height: 128
            smooth: true
            visible: status === Image.Ready
        }
        Text { text: qsTranslate("OmniaLibrary", "Omnia"); anchors.verticalCenter: parent.verticalCenter; color: head.host.ink; font.family: head.host.uiFont; font.pixelSize: head.host.s * 38; font.weight: Font.Medium }
    }
    Rectangle { id: sep1; anchors { left: brand.right; leftMargin: head.host.s * 30; verticalCenter: parent.verticalCenter } width: 1; height: head.host.s * 36; color: Qt.rgba(1, 1, 1, 0.16) }

    Row {
        id: mainNav
        anchors { left: sep1.right; leftMargin: head.host.s * 22; verticalCenter: parent.verticalCenter }
        spacing: head.host.s * 6
        Repeater {
            model: head.host.mainNavTabs
            delegate: Rectangle {
                    id: navItem
                required property var modelData
                required property int index
                    readonly property bool active: head.host.page === navItem.modelData.key
                height: head.host.s * 38
                width: navLabel.implicitWidth + head.host.s * 28
                radius: height / 2
                color: active ? head.host.accent : navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                border.width: head.host.mainNavIndex === index ? 3 : 0; border.color: head.host.ring
                    Text { id: navLabel; anchors.centerIn: parent; text: navItem.modelData.label; color: head.host.ink; font.family: head.host.uiFont; font.pixelSize: head.host.s * 17; font.weight: navItem.active ? Font.DemiBold : Font.Medium }
                    MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: head.host.activateMainNav(navItem.index) }
            }
        }
    }

    PlatformPicker {
        id: chips
        visible: head.host.page === "library"
        anchors { left: mainNav.right; leftMargin: head.host.s * 18; verticalCenter: parent.verticalCenter }
        width: head.host.page === "library" ? implicitWidth : 0
        options: head.host.filterOptions
        current: head.host.filterKey
        games: head.host.api.games
        padMode: head.host.api.padOn
        padFamily: head.host.api.padFamily || "xbox"
        uiScale: head.host.s; ink: head.host.ink; ink2: head.host.ink2; accent: head.host.accent; uiFont: head.host.uiFont
        colorOf: function(key) { return head.host.platformColor(key) }
        onPicked: function(key) { head.host.setFilter(key) }
    }
    Rectangle { id: sep2; visible: head.host.page === "library"; anchors { left: chips.right; leftMargin: head.host.s * 18; verticalCenter: parent.verticalCenter } width: visible ? 1 : 0; height: head.host.s * 36; color: Qt.rgba(1, 1, 1, 0.16) }

    // búsqueda (no se muestra en el Inicio)
    Rectangle {
        id: searchBox
        visible: head.host.page === "library" || head.host.page === "all"
        anchors { left: sep2.right; leftMargin: head.host.page === "library" ? head.host.s * 18 : head.host.s * 12; verticalCenter: parent.verticalCenter }
        height: head.host.s * 42
        width: head.host.searchOpen || head.host.searchText ? head.host.s * 300 : head.host.s * 46
        radius: height / 2
        color: Qt.rgba(0.05, 0.08, 0.12, 0.65)
        border.color: head.host.searchOpen || head.host.searchFocus ? head.host.ring : Qt.rgba(1, 1, 1, 0.26)
        border.width: head.host.searchFocus ? 3 : 1
        clip: true
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        LucideIcon { id: sIcon; x: head.host.s * 13; anchors.verticalCenter: parent.verticalCenter; width: head.host.s * 20; height: head.host.s * 20; name: "search"; color: head.host.ink }
        TextInput {
            id: searchInput
            anchors { left: sIcon.right; leftMargin: head.host.s * 10; right: parent.right; rightMargin: head.host.s * 14; verticalCenter: parent.verticalCenter }
            visible: head.host.searchOpen || head.host.searchText !== ""
            color: head.host.ink
            selectionColor: head.host.accent
            font.family: head.host.uiFont
            font.pixelSize: head.host.s * 18
            clip: true
            text: head.host.searchText
            onTextChanged: if (text !== head.host.searchText) { head.host.searchText = text; Qt.callLater(function() { head.host.select(0) }) }
            Keys.onEscapePressed: { head.host.searchOpen = false; head.host.searchText = ""; text = ""; head.host.forceActiveFocus() }
            Keys.onReturnPressed: { head.host.searchOpen = false; head.host.forceActiveFocus() }
            Text { visible: !parent.text; text: qsTranslate("OmniaLibrary", "Buscar juego…"); color: head.host.ink2; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            anchors.fill: parent
            enabled: !head.host.searchOpen
            cursorShape: Qt.PointingHandCursor
            onClicked: { head.host.searchOpen = true; searchInput.forceActiveFocus() }
        }
    }

    Rectangle {
        visible: head.host.page === "library"
        anchors { left: searchBox.right; leftMargin: head.host.s * 8; verticalCenter: parent.verticalCenter }
        width: head.host.s * 42; height: width; radius: width / 2
        color: addMouse.containsMouse ? head.host.surface : "#b30b0f14"
        border.width: head.host.mainNavIndex === 3 ? 3 : 1
        border.color: head.host.mainNavIndex === 3 ? head.host.ring : head.host.surfaceBorder
        Accessible.name: qsTranslate("OmniaLibrary", "Añadir juego")
        Accessible.role: Accessible.Button
        LucideIcon { anchors.centerIn: parent; width: head.host.s * 20; height: width; name: "plus"; color: head.host.ink }
        MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: head.host.openAddGame() }
    }

    Rectangle {
        visible: head.host.suiteUpdateNotice.available
        anchors { right: padBatteryChip.visible ? padBatteryChip.left : sysPill.left
            rightMargin: head.host.s * 10; verticalCenter: parent.verticalCenter }
        width: updateText.implicitWidth + head.host.s * 26
        height: head.host.s * 42
        radius: height / 2
        color: "#214B67"
        border.color: head.host.mainNavIndex === head.host.updateIndex ? head.host.ring : "#5A7F9D"
        border.width: head.host.mainNavIndex === head.host.updateIndex ? 3 : 1
        Text {
            id: updateText
            anchors.centerIn: parent
            text: head.host.suiteUpdateNotice.label
            color: head.host.ink
            font.family: head.host.uiFont
            font.pixelSize: head.host.s * 17
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: head.host.suiteUpdateNotice.activate() }
    }

    // ajustes de BigMode
    Rectangle {
        id: gearBtn
        anchors { right: powerBtn.left; rightMargin: head.host.s * 10; verticalCenter: parent.verticalCenter }
        width: head.host.s * 42; height: head.host.s * 42; radius: width / 2
        color: gearMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0.05, 0.08, 0.12, 0.72)
        border.width: head.host.mainNavIndex === head.host.gearIndex ? 3 : 1
        border.color: head.host.mainNavIndex === head.host.gearIndex ? head.host.ring : Qt.rgba(1, 1, 1, 0.20)
        LucideIcon { anchors.centerIn: parent; width: head.host.s * 20; height: head.host.s * 20; name: "settings"; color: head.host.ink }
        MouseArea { id: gearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: head.host.openSettings() }
    }

    Rectangle {
        id: powerBtn
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: head.host.s * 42; height: width; radius: width / 2
        color: powerMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0.05, 0.08, 0.12, 0.72)
        border.width: head.host.mainNavIndex === head.host.powerIndex || head.host.exitConfirmOpen ? 3 : 1
        border.color: head.host.mainNavIndex === head.host.powerIndex || head.host.exitConfirmOpen ? head.host.ring : head.host.surfaceBorder
        Accessible.name: qsTranslate("OmniaLibrary", "Cerrar Big Mode")
        Accessible.role: Accessible.Button
        LucideIcon { anchors.centerIn: parent; width: head.host.s * 20; height: width; name: "power"; color: head.host.ink }
        MouseArea { id: powerMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: head.host.requestExit() }
    }

    Rectangle {
        id: clockPill
        anchors { right: gearBtn.left; rightMargin: head.host.s * 12; verticalCenter: parent.verticalCenter }
        width: timeLabel.implicitWidth + head.host.s * 28
        height: head.host.s * 42
        radius: height / 2
        color: "#b30b0f14"
        Text {
            id: timeLabel
            anchors.centerIn: parent
            text: head.host.clockLabel
            color: head.host.ink
            font.family: head.host.uiFont
            font.pixelSize: head.host.s * 17
        }
    }
    PadBattery {         // visible en todas las pantallas de BigMode junto con el reloj
        id: padBatteryChip
        api: head.host.api; uiScale: head.host.s; uiFont: head.host.uiFont; ink: head.host.ink; muted: head.host.ink2
        compact: head.host.page === "library"
        anchors { right: sysPill.left; rightMargin: head.host.s * 10; verticalCenter: parent.verticalCenter }
    }
    Rectangle {          // descargas e instalaciones en curso o fallidas (START en el mando)
        id: dlPill
        visible: head.host.dlBusy + head.host.dlFailed > 0
        anchors { right: padBatteryChip.left; rightMargin: head.host.s * 10; verticalCenter: parent.verticalCenter }
        width: dlLabel.implicitWidth + head.host.s * 60; height: head.host.s * 42; radius: height / 2
        color: dlMouse.containsMouse ? head.host.surface : "#b30b0f14"
        border.color: head.host.dlFailed > 0 ? "#80E8B86D" : "#30ffffff"
        Row {
            anchors.centerIn: parent; spacing: head.host.s * 9
            LucideIcon { width: head.host.s * 19; height: width; name: head.host.dlBusy > 0 ? "download" : "info"; color: head.host.dlFailed > 0 ? "#E8B86D" : head.host.ink2 }
            Text {
                id: dlLabel; color: head.host.ink; font.family: head.host.uiFont; font.pixelSize: head.host.s * 17
                text: head.host.dlBusy > 0 ? qsTranslate("OmniaLibrary", "Descargas %1%").arg(head.host.dlProgress) + (head.host.dlFailed > 0 ? "  ⚠ " + head.host.dlFailed : "") : qsTranslate("OmniaLibrary", "%1 fallida(s)").arg(head.host.dlFailed)
            }
        }
        MouseArea { id: dlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: head.host.openDownloads() }
    }
    Rectangle {
        id: sysPill
        anchors { right: clockPill.left; rightMargin: head.host.s * 10; verticalCenter: parent.verticalCenter }
        width: systemLabel.implicitWidth + head.host.s * 60
        height: head.host.s * 42
        radius: height / 2
        color: head.host.showSystem || sysMouse.containsMouse ? head.host.surface : "#b30b0f14"
        border.color: "#30ffffff"
        Row {
            anchors.centerIn: parent
            spacing: head.host.s * 9
            LucideIcon { width: head.host.s * 19; height: width; name: head.host.runningGame ? "gamepad-2" : "activity"; color: head.host.ink2 }
            Text {
                id: systemLabel
                text: head.host.runningGame ? qsTranslate("OmniaLibrary", "Jugando") : qsTranslate("OmniaLibrary", "Sistema")
                color: head.host.ink
                font.family: head.host.uiFont
                font.pixelSize: head.host.s * 17
            }
        }
        MouseArea {
            id: sysMouse
            anchors.fill: parent
            enabled: head.api.ok && !head.api.gameRunning
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: head.host.showSystem = !head.host.showSystem
        }
    }

    Rectangle {      // panel Sistema: tres anillos (CPU, GPU, RAM) con temperaturas, y energía, perfil y disco debajo
        id: sysCard
        visible: head.host.showSystem && head.api.ok && !head.api.gameRunning
        anchors { right: clockPill.right; top: sysPill.bottom; topMargin: head.host.s * 10 }
        width: Math.max(head.host.s * 340, clockPill.x + clockPill.width - sysPill.x)       // al menos tan ancho como los botones Sistema y reloj
        height: sysCol.implicitHeight + head.host.s * 36
        radius: head.host.s * 20
        color: "#141D27"
        border.color: head.host.surfaceBorder
            readonly property var sys: head.api.system || ({})
        function tempColor(t) { return t === undefined ? head.host.ink2 : (t <= 70 ? "#7fd69f" : (t <= 85 ? "#E8B86D" : "#E86D6D")) }
        function tempText(t) { return t === undefined ? "" : Math.round(t) + " °C" }
        Column {
            id: sysCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: head.host.s * 18 }
            spacing: head.host.s * 14
            Row {
                width: parent.width
                readonly property real cell: width / 3
                SystemGauge {
                    width: parent.cell; s: head.host.s; ink: head.host.ink; ink2: head.host.ink2; uiFont: head.host.uiFont
                    value: head.host.live.cpu_pct === undefined ? -1 : head.host.live.cpu_pct / 100
                    centerText: head.host.live.cpu_pct === undefined ? "–" : Math.round(head.host.live.cpu_pct) + "%"
                    label: "CPU"; detail: sysCard.tempText(head.host.live.cpu_temp); detailColor: sysCard.tempColor(head.host.live.cpu_temp)
                    ringColor: head.host.live.cpu_pct > 90 ? "#E8B86D" : "#5B9BE0"
                }
                SystemGauge {
                    width: parent.cell; s: head.host.s; ink: head.host.ink; ink2: head.host.ink2; uiFont: head.host.uiFont
                    value: head.host.live.gpu_pct === undefined ? -1 : head.host.live.gpu_pct / 100
                    centerText: head.host.live.gpu_pct === undefined ? "–" : Math.round(head.host.live.gpu_pct) + "%"
                    label: "GPU"; detail: sysCard.tempText(head.host.live.gpu_temp); detailColor: sysCard.tempColor(head.host.live.gpu_temp)
                    ringColor: head.host.live.gpu_pct > 90 ? "#E8B86D" : "#5B9BE0"
                }
                SystemGauge {
                    width: parent.cell; s: head.host.s; ink: head.host.ink; ink2: head.host.ink2; uiFont: head.host.uiFont
                    value: head.host.live.ram_total ? head.host.live.ram_used / head.host.live.ram_total : -1
                    centerText: head.host.live.ram_total ? Math.round(100 * head.host.live.ram_used / head.host.live.ram_total) + "%" : "–"
                    label: "RAM"
                    detail: head.host.live.ram_total ? (head.host.live.ram_used / 1073741824).toFixed(1) + " / " + (head.host.live.ram_total / 1073741824).toFixed(1) + " GB" : ""
                    ringColor: head.host.live.ram_total && head.host.live.ram_used / head.host.live.ram_total > 0.9 ? "#E8B86D" : "#5B9BE0"
                }
            }
            Flow {
                width: parent.width; spacing: head.host.s * 8
                layoutDirection: Qt.LeftToRight
                Repeater {
                    model: {
                        const out = [], sys = sysCard.sys
                        if (sys.bat && sys.bat.pct !== undefined) out.push({ icon: "activity", text: sys.bat.pct + " %" + (sys.ac ? "  ·  " + qsTranslate("OmniaLibrary", "conectado") : "") })
                        if (sys.profile) out.push({ icon: "activity", text: sys.profile })
                        if (sys.disk && sys.disk.total) out.push({ icon: "folder-open", text: Math.round(sys.disk.used / 1073741824) + " / " + Math.round(sys.disk.total / 1073741824) + " GB" })
                        return out
                    }
                    delegate: Rectangle {
                            id: statusChip
                        required property var modelData
                        width: chipText.implicitWidth + head.host.s * 24; height: head.host.s * 32; radius: height / 2
                        color: "#b30b0f14"; border.color: "#30ffffff"
                            Text { id: chipText; anchors.centerIn: parent; text: statusChip.modelData.text; color: head.host.ink; font.family: head.host.uiFont; font.pixelSize: head.host.s * 15 }
                    }
                }
            }
            Text {
                visible: !!sysCard.sys.cpu && !!sysCard.sys.cpu.model
                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                color: head.host.ink2; font.family: head.host.uiFont; font.pixelSize: head.host.s * 14
                text: sysCard.sys.cpu ? sysCard.sys.cpu.model + (sysCard.sys.cpu.ghz ? "  ·  " + sysCard.sys.cpu.ghz + " GHz" : "") : ""
            }
            Text { visible: head.host.live.cpu_pct === undefined && head.host.live.gpu_pct === undefined && head.host.live.ram_total === undefined; text: qsTranslate("OmniaLibrary", "Sin datos de telemetría"); color: head.host.ink2
                   font.family: head.host.uiFont; font.pixelSize: head.host.s * 18 }
        }
    }
}

