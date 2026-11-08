.pragma library

// One entry per face: id is what main.xml stores, file is relative to this directory, note is shown under the picker.
var faces = [
    { id: "cpu", name: "CPU", file: "faces/CpuFace.qml" },
    { id: "ram", name: "RAM", file: "faces/RamFace.qml" },
    { id: "disk", name: "Disk", file: "faces/DiskFace.qml" },
    { id: "temp", name: "Temperature", file: "faces/TempFace.qml" }
];

function id(x) {
    for (var i = 0; i < faces.length; i++)
        if (faces[i].id === x)
            return x;
    return faces[0].id;
}

function file(id) {
    for (var i = 0; i < faces.length; i++)
        if (faces[i].id === id)
            return faces[i].file;
    return faces[0].file;
}
