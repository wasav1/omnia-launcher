import QtQuick
import org.kde.ksysguard.sensors as Sensors

// Sensores reales del sistema (los mismos del widget "Anillos").
Item {
    id: src
    readonly property int rate: 1000
    Sensors.Sensor { id: gpu0Name; sensorId: "gpu/gpu0/name" }
    Sensors.Sensor { id: gpu1Name; sensorId: "gpu/gpu1/name" }
    readonly property string gpu0Label: String(gpu0Name.value || "")
    readonly property string gpu1Label: String(gpu1Name.value || "")
    readonly property string gpuId: /nvidia|geforce|gtx|rtx|radeon rx|arc a\d/i.test(gpu0Label) ? "gpu0" : (/nvidia|geforce|gtx|rtx|radeon rx|arc a\d/i.test(gpu1Label) ? "gpu1" : (gpu0Label ? "gpu0" : "gpu1"))
    readonly property string gpuName: String(gpuId === "gpu0" ? gpu0Label : gpu1Label).replace(/^NVIDIA GeForce /i, "").replace(/^AMD Radeon /i, "")
    Sensors.Sensor { id: cpuU;  sensorId: "cpu/all/usage";              updateRateLimit: src.rate }
    Sensors.Sensor { id: cpuT;  sensorId: "cpu/all/averageTemperature"; updateRateLimit: src.rate }
    Sensors.Sensor { id: gpuU;  sensorId: "gpu/" + src.gpuId + "/usage";       updateRateLimit: src.rate }
    Sensors.Sensor { id: gpuT;  sensorId: "gpu/" + src.gpuId + "/temperature"; updateRateLimit: src.rate }
    Sensors.Sensor { id: ramU;  sensorId: "memory/physical/used";  updateRateLimit: src.rate }
    Sensors.Sensor { id: ramTt; sensorId: "memory/physical/total"; updateRateLimit: src.rate }
    Sensors.Sensor { id: vrU;   sensorId: "gpu/" + src.gpuId + "/usedVram";  updateRateLimit: src.rate }
    Sensors.Sensor { id: vrT;   sensorId: "gpu/" + src.gpuId + "/totalVram"; updateRateLimit: src.rate }
    function n(v) { var x = Number(v); return isNaN(x) ? 0 : x }
    readonly property real cpu: n(cpuU.value)
    readonly property real cpuTemp: n(cpuT.value)
    readonly property real gpu: n(gpuU.value)
    readonly property real gpuTemp: n(gpuT.value)
    readonly property real ramUsed: n(ramU.value)
    readonly property real ramTotal: n(ramTt.value)
    readonly property real vramUsed: n(vrU.value)
    readonly property real vramTotal: n(vrT.value)
}
