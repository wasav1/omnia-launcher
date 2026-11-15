import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    // Colores de cada anillo
    readonly property color colorCpu:  "#7F77DD"
    readonly property color colorGpu:  "#5DCAA5"
    readonly property color colorRam:  "#F0A040"
    readonly property color colorVram: "#85B7EB"
    readonly property int refreshMs: 1000

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: fullRepresentation

    // Detecta cuál GPU es la NVIDIA (gpu0 o gpu1)
    Sensors.Sensor { id: gpu0Name; sensorId: "gpu/gpu0/name" }
    readonly property string gpuId: /nvidia|geforce|gtx|rtx/i.test(String(gpu0Name.value)) ? "gpu0" : "gpu1"

    Sensors.Sensor { id: cpuUsage;  sensorId: "cpu/all/usage";                updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: cpuTemp;   sensorId: "cpu/all/averageTemperature";   updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: gpuUsage;  sensorId: "gpu/" + root.gpuId + "/usage";       updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: gpuTemp;   sensorId: "gpu/" + root.gpuId + "/temperature"; updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: ramPct;    sensorId: "memory/physical/usedPercent";  updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: ramUsed;   sensorId: "memory/physical/used";         updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: vramPct;   sensorId: "gpu/" + root.gpuId + "/usedPercent"; updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: vramUsed;  sensorId: "gpu/" + root.gpuId + "/usedVram";    updateRateLimit: root.refreshMs }

    function num(v) { var n = Number(v); return isNaN(n) ? 0 : n }
    function temp(v) { return Math.round(num(v)) + " °C" }
    function gib(v) { return (num(v) / 1073741824).toFixed(1) + " GiB" }

    component Ring: Item {
        id: ring
        property string label: ""
        property real value: 0
        property string sub: ""
        property color ringColor: "white"
        implicitWidth: 88
        implicitHeight: col.implicitHeight

        ColumnLayout {
            id: col
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3

            Item {
                Layout.preferredWidth: 76
                Layout.preferredHeight: 76
                Layout.alignment: Qt.AlignHCenter

                Canvas {
                    id: canvas
                    anchors.fill: parent
                    property real v: Math.max(0, Math.min(100, ring.value))
                    onVChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var c = width / 2, r = width / 2 - 5
                        ctx.lineWidth = 6
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12)
                        ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                        if (v > 0) {
                            ctx.strokeStyle = ring.ringColor.toString()
                            ctx.beginPath()
                            ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * v / 100)
                            ctx.stroke()
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: Math.round(ring.value) + "%"
                    color: Kirigami.Theme.textColor
                    font.pixelSize: 16
                    font.bold: true
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: ring.label
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: 11
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: ring.sub
                color: Kirigami.Theme.textColor
                font.pixelSize: 12
            }
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: row.implicitWidth + 28
        Layout.preferredHeight: row.implicitHeight + 24
        Layout.minimumWidth: row.implicitWidth + 28
        Layout.minimumHeight: row.implicitHeight + 24

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 18
            Ring { label: "CPU";  value: root.num(cpuUsage.value); sub: root.temp(cpuTemp.value); ringColor: root.colorCpu }
            Ring { label: "GPU";  value: root.num(gpuUsage.value); sub: root.temp(gpuTemp.value); ringColor: root.colorGpu }
            Ring { label: "RAM";  value: root.num(ramPct.value);   sub: root.gib(ramUsed.value);  ringColor: root.colorRam }
            Ring { label: "VRAM"; value: root.num(vramPct.value);  sub: root.gib(vramUsed.value); ringColor: root.colorVram }
        }
    }
}
