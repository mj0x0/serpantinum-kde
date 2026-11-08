import QtQuick
import org.kde.ksysguard.sensors as Sensors

// The numbers upstream's SysData singleton handed the faces, fed by ksystemstats; only the shown metric's sensors poll.
QtObject {
    id: root

    property string metric: "cpu"
    property string tempSensor: "cpu/all/averageTemperature"

    readonly property Sensors.Sensor cpuSensor: Sensors.Sensor {
        sensorId: "cpu/all/usage"
        enabled: root.metric === "cpu"
        updateRateLimit: 2000
    }
    readonly property Sensors.Sensor ramPercentSensor: Sensors.Sensor {
        sensorId: "memory/physical/usedPercent"
        enabled: root.metric === "ram"
        updateRateLimit: 2000
    }
    readonly property Sensors.Sensor ramUsedSensor: Sensors.Sensor {
        sensorId: "memory/physical/used"
        enabled: root.metric === "ram"
        updateRateLimit: 2000
    }
    readonly property Sensors.Sensor tempSensorItem: Sensors.Sensor {
        sensorId: root.tempSensor
        enabled: root.metric === "temp"
        updateRateLimit: 2000
    }
    readonly property Sensors.Sensor diskPercentSensor: Sensors.Sensor {
        sensorId: "disk/all/usedPercent"
        enabled: root.metric === "disk"
        updateRateLimit: 2000
    }
    readonly property Sensors.Sensor diskUsedSensor: Sensors.Sensor {
        sensorId: "disk/all/used"
        enabled: root.metric === "disk"
        updateRateLimit: 2000
    }
    readonly property Sensors.Sensor diskTotalSensor: Sensors.Sensor {
        sensorId: "disk/all/total"
        enabled: root.metric === "disk"
        updateRateLimit: 2000
    }

    readonly property real cpu: Number(cpuSensor.value) || 0
    readonly property real ramPercent: Number(ramPercentSensor.value) || 0
    readonly property real ramGb: (Number(ramUsedSensor.value) || 0) / 1073741824
    readonly property real temp: Number(tempSensorItem.value) || 0
    readonly property real diskPercent: Number(diskPercentSensor.value) || 0
    readonly property real diskGb: (Number(diskUsedSensor.value) || 0) / 1073741824
    readonly property real diskTotalGb: (Number(diskTotalSensor.value) || 0) / 1073741824
}
