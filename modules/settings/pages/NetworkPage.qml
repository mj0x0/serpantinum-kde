import ".."
import "../../../services/settings"
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: page

    // "user:foo.service" / "system:bar.service"; the Servers tab merges these with the
    // containers and the listening ports it recognises on its own.
    readonly property var serverUnits: {
        var v = ShellSettings.value("servers.units", null);
        // Strings only, as the helper reads them: a row it would skip must not be listed.
        return Array.isArray(v) ? v.filter(e => typeof e === "string") : [];
    }
    readonly property var serverPorts: {
        var v = ShellSettings.value("servers.ports", null);
        return (v && typeof v === "object" && !Array.isArray(v)) ? v : ({});
    }
    // As the helper reads them: only a user: prefix is a user unit, a bare name is a system one.
    function serverKind(entry) { return ("" + entry).indexOf("user:") === 0 ? "user" : "system" }
    function serverUnit(entry) {
        var i = ("" + entry).indexOf(":");
        return i < 0 ? "" + entry : ("" + entry).substring(i + 1);
    }
    // Every form the helper accepts: a number, a string, a list of either, under the full
    // unit name or its bare base. A hand-edited override has to be visible to be editable.
    function serverPort(unit) {
        var v = serverPorts[unit];
        if (v === undefined)
            v = serverPorts[serverBase(unit)];
        var list = Array.isArray(v) ? v : [v];
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var n = parseInt(list[i], 10);
            if (isFinite(n) && n > 0 && n < 65536 && out.indexOf(n) === -1)
                out.push(n);
        }
        return out.join(" ");
    }
    function serverBase(unit) { return ("" + unit).replace(/\.[a-z]+$/, "") }
    function addServer(kind, name) {
        var n = ("" + name).trim();
        if (n === "") return;
        if (n.indexOf(".") < 0) n += ".service";
        var entry = kind + ":" + n;
        var arr = serverUnits.slice();
        if (arr.indexOf(entry) !== -1) return;
        arr.push(entry);
        ShellSettings.setValue("servers.units", arr);
    }
    function dropServer(entry) {
        var arr = serverUnits.filter(e => e !== entry);
        ShellSettings.setValue("servers.units", arr);
        // A port left behind has no row to clear it from.
        var unit = serverUnit(entry);
        var held = serverPorts[unit] !== undefined || serverPorts[serverBase(unit)] !== undefined;
        if (held && !arr.some(e => serverUnit(e) === unit))
            setServerPort(unit, "");
    }
    // Unit names carry dots, so the map is rewritten whole: a dotted setValue path
    // would nest "jellyfin" above "service". Returns what was stored, so a field holding a
    // value this threw away can clear itself instead of lying.
    function setServerPort(unit, port) {
        var base = serverBase(unit);
        var next = ({});
        for (var k in serverPorts)
            if (k !== unit && k !== base) next[k] = serverPorts[k];
        var ports = [];
        var bits = ("" + port).split(/[^0-9]+/);
        for (var i = 0; i < bits.length; i++) {
            var n = parseInt(bits[i], 10);
            if (isFinite(n) && n > 0 && n < 65536 && ports.indexOf(n) === -1)
                ports.push(n);
        }
        if (ports.length === 1) next[unit] = ports[0];
        else if (ports.length > 1) next[unit] = ports;
        ShellSettings.setValue("servers.ports", next);
        return ports.join(" ");
    }

    SettingsRow {
        host: page.host
        label: "Docker containers"
        glyph: "\u{f0868}"
        desc: "Shown in the Servers tab with the ports they publish. Off skips Docker altogether"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("servers.docker", true) !== false
            onToggled: v => ShellSettings.setValue("servers.docker", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Services"
        glyph: "\u{f048b}"
        desc: "systemd units the Servers tab watches and can stop. A port is only "
            + "needed when it cannot be read off the listening socket"
    }

    Repeater {
        model: page.serverUnits
        delegate: SettingsRow {
            id: unitRow
            host: page.host
            required property string modelData
            readonly property string unit: page.serverUnit(modelData)
            readonly property bool privileged: page.serverKind(modelData) === "system"
            label: unitRow.unit
            glyph: unitRow.privileged ? "\u{f099d}" : "\u{f0004}"
            desc: unitRow.privileged
                ? "system unit  •  stopping it asks for authentication"
                : "user unit"

            RowLayout {
                spacing: page.host.s(10)
                SettingsPathField {
                    id: portField
                    host: page.host
                    implicitWidth: page.host.s(96)
                    placeholder: "port"
                    value: page.serverPort(unitRow.unit)
                    onCommitted: v => portField.reset(page.setServerPort(unitRow.unit, v))
                }
                SettingsBtn {
                    host: page.host
                    label: "Remove"
                    onClicked: page.dropServer(unitRow.modelData)
                }
            }
        }
    }

    SettingsRow {
        id: addUnit
        host: page.host
        property string kind: "user"
        label: "Add a service"
        glyph: "\u{f0415}"
        desc: "Name it as systemd does; .service is assumed. A user unit stops without "
            + "a prompt, a system one asks polkit"
        RowLayout {
            spacing: page.host.s(10)
            SettingsChips {
                host: page.host
                options: ["user", "system"]
                current: addUnit.kind
                onPicked: v => addUnit.kind = v
            }
            SettingsPathField {
                id: unitDraft
                host: page.host
                implicitWidth: page.host.s(200)
                placeholder: "jellyfin.service"
                // Enter or a click away adds it; the field clears either way.
                onCommitted: v => {
                    page.addServer(addUnit.kind, v);
                    unitDraft.reset("");
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        text: "Stored in settings.json. Containers and the listening ports the shell "
            + "recognises need no entry here."
        font.family: page.host.fontFamily
        font.pixelSize: page.host.s(9)
        color: page.host.overlay0
        wrapMode: Text.Wrap
    }
}
