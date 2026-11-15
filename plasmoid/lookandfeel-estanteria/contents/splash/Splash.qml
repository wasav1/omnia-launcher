import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

// Bienvenida "Estantería": wallpaper1 a pantalla completa + placa de cristal translúcido (blur real del fondo)
// con el anillo de progreso y las cinco secciones animadas. Tipografía de Bazzite/Plasma (Noto Sans).
// Ajustes aprobados: cristal (desenfoque) = 15, tinte = 25.
Rectangle {
    id: root
    color: "#05100c"
    width: 1280; height: 800
    property int stage: 0                                  // lo rellena ksplashqml (1..6)

    readonly property real sc: width / 100                  // 1 unidad = 1% del ancho (equivale a 1cqw del boceto)
    readonly property bool reduced: Kirigami.Units.longDuration < 1
    readonly property color gold: "#e6d9a0"
    readonly property string fnt: "Noto Sans"
    readonly property int glassBlur: 15                     // "Cristal" del boceto
    readonly property real tint: 0.25                       // "Tinte" del boceto
    readonly property var stepNames: ["Escritorio", "Cristal y efectos", "Ayudante de la estantería", "Mando", "Biblioteca"]

    // ---- línea de tiempo: el splash de KDE se cierra en cuanto Plasma termina de arrancar (~3,5 s), así que el flujo completo
    //      cabe en ~2,8 s y, si el arranque va por delante, se acelera con las etapas reales (stage) ----
    property real elapsed: 0
    readonly property int t0: 450          // primera sección
    readonly property int dt: 450          // separación entre secciones
    readonly property int tDone: 300       // lo que tarda cada una en completarse
    readonly property int tEnd: t0 + 4 * dt + tDone + 250
    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: { root.elapsed += 40; if (root.stage >= 3) root.elapsed = Math.max(root.elapsed, root.t0 + 3 * root.dt); if (root.stage >= 4) root.elapsed = Math.max(root.elapsed, root.tEnd); }
    }
    function stepState(i) { var a = t0 + i * dt; return elapsed >= a + tDone ? 2 : (elapsed >= a ? 1 : 0); }
    readonly property int doneCount: { var n = 0; for (var i = 0; i < 5; i++) if (elapsed >= t0 + i * dt + tDone) n++; return n; }
    property real prog: doneCount / 5
    Behavior on prog { NumberAnimation { duration: reduced ? 0 : 400; easing.type: Easing.OutCubic } }

    // ================= escena: todo lo que queda DETRÁS de la placa =================
    Item {
        id: bgGroup
        anchors.fill: parent

        Image {
            id: bg
            x: -parent.width * 0.04; y: -parent.height * 0.04
            width: parent.width * 1.08; height: parent.height * 1.08
            source: "images/wallpaper1.jpeg"
            fillMode: Image.PreserveAspectCrop
            smooth: true; mipmap: true                      // resolución completa del archivo, sin reducir
            transformOrigin: Item.Center
            scale: 1.02
            SequentialAnimation on scale {
                running: !root.reduced; loops: Animation.Infinite
                NumberAnimation { to: 1.1; duration: 90000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.02; duration: 90000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on x {
                running: !root.reduced; loops: Animation.Infinite
                NumberAnimation { to: bgGroup.width * -0.048; duration: 90000; easing.type: Easing.InOutSine }
                NumberAnimation { to: bgGroup.width * -0.032; duration: 90000; easing.type: Easing.InOutSine }
            }
        }

        // niebla
        Repeater {
            model: 2
            Rectangle {
                required property int index
                width: bgGroup.width * 1.6; height: bgGroup.height * 0.3
                x: -bgGroup.width * 0.3
                y: bgGroup.height * (index === 0 ? 0.62 : 0.46)
                opacity: index === 0 ? 1 : 0.6
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "#00bee6d7" }
                    GradientStop { position: 0.5; color: "#1fbee6d7" }
                    GradientStop { position: 1.0; color: "#00bee6d7" }
                }
                SequentialAnimation on x {
                    running: !root.reduced; loops: Animation.Infinite
                    NumberAnimation { to: bgGroup.width * -0.3 + bgGroup.width * 0.22; duration: index === 0 ? 60000 : 85000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: bgGroup.width * -0.3; duration: index === 0 ? 60000 : 85000; easing.type: Easing.InOutSine }
                }
            }
        }

        // luciérnagas doradas
        Canvas {
            id: motes
            anchors.fill: parent
            renderTarget: Canvas.Image
            property real tt: 0
            property var list: []
            Component.onCompleted: {
                var a = [];
                for (var i = 0; i < 34; i++) a.push({ x: Math.random(), y: 0.2 + Math.random() * 0.75, r: 0.7 + Math.random() * 1.5, ph: Math.random() * 6.28, sp: 0.4 + Math.random() * 0.8 });
                list = a;
            }
            Timer {
                interval: 33; running: !root.reduced; repeat: true
                onTriggered: {
                    motes.tt += 0.033;
                    for (var i = 0; i < motes.list.length; i++) {
                        var p = motes.list[i];
                        p.x += Math.sin(motes.tt * 0.4 * p.sp + p.ph) * 0.0004;
                        p.y += Math.cos(motes.tt * 0.3 * p.sp + p.ph * 2) * 0.0003;
                    }
                    motes.requestPaint();
                }
            }
            onPaint: {
                var c = getContext("2d"); c.reset(); c.globalCompositeOperation = "lighter";
                for (var i = 0; i < list.length; i++) {
                    var p = list[i];
                    var a = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(tt * p.sp + p.ph));
                    var r = p.r * width * 0.0016, x = p.x * width, y = p.y * height;
                    var g = c.createRadialGradient(x, y, 0, x, y, r * 4);
                    g.addColorStop(0, "rgba(255,244,205," + (0.9 * a) + ")");
                    g.addColorStop(0.3, "rgba(255,214,120," + (0.4 * a) + ")");
                    g.addColorStop(1, "rgba(255,214,120,0)");
                    c.fillStyle = g; c.beginPath(); c.arc(x, y, r * 4, 0, 6.2832); c.fill();
                }
            }
        }

        // velo (viñeta + degradado vertical)
        RadialGradient {
            anchors.fill: parent
            horizontalRadius: width * 0.75; verticalRadius: height * 0.75
            gradient: Gradient {
                GradientStop { position: 0.3; color: "#0d040e0a" }
                GradientStop { position: 1.0; color: "#9e020806" }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#40030c09" }
                GradientStop { position: 0.4; color: "#1a030c09" }
                GradientStop { position: 1.0; color: "#73030c09" }
            }
        }
    }

    // ================= placa de cristal =================
    Item {
        id: plate
        width: root.sc * 31
        height: col.implicitHeight + root.sc * 6.4
        x: (root.width - width) / 2
        y: (root.height - height) / 2 + (1 - enter) * root.sc * 3
        property real enter: 0
        opacity: enter
        NumberAnimation on enter { from: 0; to: 1; duration: root.reduced ? 0 : 800; easing.type: Easing.OutCubic; running: true }

        RectangularGlow {   // sombra exterior
            anchors.fill: parent; anchors.topMargin: root.sc * 1.2
            glowRadius: root.sc * 4; spread: 0.0; color: "#8c000000"; cornerRadius: root.sc * 2.4 + glowRadius
        }

        Rectangle { id: plateMask; anchors.fill: parent; radius: root.sc * 2.4; visible: false }

        Item {
            id: glassBody
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OpacityMask { maskSource: plateMask }

            // 1) desenfoque REAL de lo que hay detrás (cristal 15), +saturación, -brillo
            ShaderEffectSource {
                id: snap
                sourceItem: bgGroup
                sourceRect: Qt.rect(plate.x, plate.y, plate.width, plate.height)
                live: true
                visible: false
            }
            FastBlur { id: blurred; anchors.fill: parent; source: snap; radius: root.glassBlur * root.width / 1920; visible: false }
            HueSaturation { anchors.fill: parent; source: blurred; saturation: 0.5; lightness: -0.1 }

            // 2) tinte verde (25 %)
            LinearGradient {
                anchors.fill: parent
                start: Qt.point(0, 0); end: Qt.point(width, height)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(210 / 255, 245 / 255, 232 / 255, 0.06 + root.tint * 0.22) }
                    GradientStop { position: 0.38; color: Qt.rgba(20 / 255, 48 / 255, 38 / 255, 0.15 + root.tint * 0.4) }
                    GradientStop { position: 1.0; color: Qt.rgba(6 / 255, 20 / 255, 15 / 255, 0.25 + root.tint * 0.5) }
                }
            }
            // 3) facetas de cristal
            Canvas {
                anchors.fill: parent
                onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                function css(c, w, h, deg, stops) {
                    var a = deg * Math.PI / 180, dx = Math.sin(a), dy = -Math.cos(a);
                    var L = Math.abs(w * dx) + Math.abs(h * dy), cx = w / 2, cy = h / 2;
                    var g = c.createLinearGradient(cx - dx * L / 2, cy - dy * L / 2, cx + dx * L / 2, cy + dy * L / 2);
                    for (var i = 0; i < stops.length; i++) g.addColorStop(stops[i][0], stops[i][1]);
                    c.fillStyle = g; c.fillRect(0, 0, w, h);
                }
                onPaint: {
                    var c = getContext("2d"); c.reset();
                    css(c, width, height, 115, [[0, "rgba(255,255,255,0)"], [0.12, "rgba(255,255,255,0)"], [0.124, "rgba(255,255,255,0.10)"], [0.30, "rgba(255,255,255,0.02)"], [0.303, "rgba(255,255,255,0)"], [1, "rgba(255,255,255,0)"]]);
                    css(c, width, height, 65, [[0, "rgba(255,255,255,0)"], [0.58, "rgba(255,255,255,0)"], [0.583, "rgba(255,255,255,0.07)"], [0.82, "rgba(255,255,255,0)"], [1, "rgba(255,255,255,0)"]]);
                }
            }
            // 4) luz interior suave
            Rectangle {
                anchors.fill: parent; anchors.margins: 1; radius: root.sc * 2.3; color: "transparent"
                border.color: "#47a0e6cd"; border.width: 1; opacity: 0.18
            }
            // 5) brillo superior
            Rectangle {
                x: parent.width * 0.08; width: parent.width * 0.84; height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00fff6c8" }
                    GradientStop { position: 0.5; color: "#d9fff6c8" }
                    GradientStop { position: 1.0; color: "#00fff6c8" }
                }
            }
        }
        // borde dorado
        Rectangle { anchors.fill: parent; radius: root.sc * 2.4; color: "transparent"; border.color: "#57e6d9a0"; border.width: 1 }

        // ---- contenido ----
        Column {
            id: col
            anchors { top: parent.top; topMargin: root.sc * 3.4; horizontalCenter: parent.horizontalCenter }
            width: parent.width - root.sc * 6
            spacing: 0

            // anillo + inicial
            Item {
                width: root.sc * 11; height: width
                anchors.horizontalCenter: parent.horizontalCenter
                Canvas {
                    id: ring
                    anchors.fill: parent
                    property real p: root.prog
                    onPChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.reset();
                        var r = width / 2 * 0.92, lw = Math.max(2, width * 0.022);
                        c.lineWidth = lw * 0.75; c.strokeStyle = "rgba(230,217,160,0.2)";
                        c.beginPath(); c.arc(width / 2, height / 2, r, 0, 6.2832); c.stroke();
                        if (p > 0) {
                            c.lineWidth = lw; c.lineCap = "round"; c.strokeStyle = "#e6d9a0";
                            c.shadowColor = "rgba(230,217,160,0.7)"; c.shadowBlur = lw * 1.5;
                            c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 6.2832 * p); c.stroke();
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent; width: parent.width - root.sc * 3.2; height: width; radius: width / 2
                    border.color: "#38e6d9a0"; border.width: 1
                    gradient: Gradient { GradientStop { position: 0; color: "#33ffffff" } GradientStop { position: 0.7; color: "#8c06140f" } GradientStop { position: 1; color: "#8c06140f" } }
                    Text {
                        anchors.centerIn: parent; text: "W"; color: root.gold
                        font.family: root.fnt; font.weight: Font.Light; font.pixelSize: root.sc * 4.4
                    }
                }
            }
            Item { width: 1; height: root.sc * 2.2 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "BIENVENIDO DE VUELTA"; color: root.gold
                font.family: root.fnt; font.weight: Font.Medium; font.pixelSize: root.sc * 1.05; font.letterSpacing: root.sc * 0.44
            }
            Item { width: 1; height: root.sc * 0.8 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                Text { text: "Hola, "; color: "#ffffff"; font.family: root.fnt; font.weight: Font.Light; font.pixelSize: root.sc * 3.6 }
                Text { text: "wsaenz"; color: root.gold; font.family: root.fnt; font.weight: Font.Light; font.pixelSize: root.sc * 3.6 }
            }
            // separador con rombo
            Item {
                width: root.sc * 14; height: root.sc * 1.2
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: "#73e6d9a0" }
                Rectangle { anchors.centerIn: parent; width: root.sc * 0.9; height: width; rotation: 45; color: "#e608160e"; border.color: root.gold; border.width: 1 }
            }
            Item { width: 1; height: root.sc * 1.8 }
            // secciones
            Column {
                id: stepsCol
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.sc * 22
                spacing: root.sc * 0.75
                Repeater {
                    model: root.stepNames
                    Row {
                        id: row
                        required property int index
                        required property string modelData
                        readonly property int st: root.stepState(index)     // 0 pendiente · 1 en curso · 2 listo
                        spacing: root.sc * 0.9
                        Item {
                            width: root.sc * 1.4; height: width
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {   // listo
                                anchors.fill: parent; radius: width / 2; color: root.gold; border.color: root.gold
                                opacity: row.st === 2 ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: root.reduced ? 0 : 250 } }
                                Text { anchors.centerIn: parent; text: "✓"; color: "#14211a"; font.pixelSize: root.sc * 0.85; font.family: root.fnt }
                            }
                            Rectangle {   // pendiente
                                anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: "#61e9e6d6"; border.width: 1
                                opacity: row.st === 0 ? 1 : 0
                            }
                            Canvas {      // en curso: círculo discontinuo giratorio
                                anchors.fill: parent
                                opacity: row.st === 1 ? 1 : 0
                                onWidthChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.reset();
                                    c.strokeStyle = "#e9e6d6"; c.lineWidth = Math.max(1, width * 0.07);
                                    c.setLineDash([width * 0.18, width * 0.14]);
                                    c.beginPath(); c.arc(width / 2, height / 2, width / 2 - c.lineWidth, 0, 6.2832); c.stroke();
                                }
                                RotationAnimator on rotation { from: 0; to: 360; duration: 2000; loops: Animation.Infinite; running: row.st === 1 && !root.reduced }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.toUpperCase()
                            color: row.st === 2 ? root.gold : (row.st === 1 ? "#e9e6d6" : "#61e9e6d6")
                            font.family: root.fnt; font.weight: Font.Medium; font.pixelSize: root.sc * 1.05; font.letterSpacing: root.sc * 0.12
                            Behavior on color { ColorAnimation { duration: root.reduced ? 0 : 400 } }
                        }
                    }
                }
            }
        }
    }

    // esquina y pie
    Text {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: root.sc * 2.6; bottomMargin: root.sc * 2.4 }
        text: "BAZZITE · PLASMA 6.8"; color: "#80e9e6d6"
        font.family: root.fnt; font.weight: Font.Medium; font.pixelSize: root.sc * 0.95; font.letterSpacing: root.sc * 0.24
    }
    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.sc * 2.6 }
        text: "ABRIENDO TU ESTANTERÍA"; color: "#99e9e6d6"
        opacity: root.elapsed >= root.tEnd ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.reduced ? 0 : 600 } }
        font.family: root.fnt; font.weight: Font.Medium; font.pixelSize: root.sc * 1.0; font.letterSpacing: root.sc * 0.34
    }
}
