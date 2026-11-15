import QtQuick
import org.kde.ksysguard.sensors as Sensors

// Sensores reales del sistema (los mismos del widget "Anillos").
Item {
    id: src
    readonly property int rate: 1000
    Sensors.Sensor { id: gpu0Name; sensorId: "gpu/gpu0/name" }
    readonly property string gpuId: /nvidia|geforce|gtx|rtx/i.test(String(gpu0Name.value)) ? "gpu0" : "gpu1"
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
