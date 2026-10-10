// Shim, not a port: upstream Location's member names over no data. The rice has no
// location source (weather.sh is keyed by an OpenWeather city id), so every member
// carries upstream's empty-locationData default.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var locationData: ({})
    property bool isDetecting: false

    readonly property string ip: locationData.ip || ""
    readonly property real latitude: locationData.latitude !== undefined ? Number(locationData.latitude) : 0.0
    readonly property real longitude: locationData.longitude !== undefined ? Number(locationData.longitude) : 0.0
    readonly property string city: locationData.city || ""
    readonly property string region: locationData.region || "Unknown"
    readonly property string regionCode: locationData.region_code || ""
    readonly property string countryName: locationData.country_name || locationData.country || "Unknown"
    readonly property string countryCode: locationData.country_code || ""
    readonly property string postal: locationData.postal || locationData.zip || ""
    readonly property string timezone: locationData.timezone || "UTC"
    readonly property string utcOffset: locationData.utc_offset || ""
    readonly property string currency: locationData.currency || ""
    readonly property string languages: locationData.languages || ""
    readonly property string asn: locationData.asn || ""
    readonly property string org: locationData.org || ""
    readonly property string source: locationData.source || "unknown"
    readonly property var updatedAt: locationData.updated_at !== undefined ? locationData.updated_at : 0

    signal locationUpdated()
}
