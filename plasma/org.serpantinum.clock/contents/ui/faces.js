.pragma library

// One entry per face: id is what main.xml stores, file is relative to this directory, note is shown under the picker.
var faces = [
    { id: "digital", name: "Digital", file: "faces/Digital.qml" },
    { id: "analog", name: "Analog", file: "faces/Analog.qml" },
    { id: "minimal", name: "Minimal", file: "faces/Minimal.qml" },
    { id: "material", name: "Material", file: "faces/Material.qml" },
    { id: "materialAnalog", name: "Material Analog", file: "faces/MaterialAnalog.qml" },
    { id: "lumen", name: "Lumen", file: "faces/MaterialLumen.qml" },
    { id: "lumenNoDial", name: "Lumen, no dial", file: "faces/LumenNoDial.qml" }
];

function file(id) {
    for (var i = 0; i < faces.length; i++)
        if (faces[i].id === id)
            return faces[i].file;
    return faces[0].file;
}
