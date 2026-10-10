// Shim, not a port: upstream's member names over Quickshell.env + the same avatar/chassis
// probes. SystemPanel keeps its own in-component probe; a shim cannot read a popup's state.
pragma Singleton

import "../caching"
import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    Caching { id: caching }

    property string username: Quickshell.env("USER") ? Quickshell.env("USER") : (Quickshell.env("LOGNAME") ? Quickshell.env("LOGNAME") : "user")
    property string desktopEnv: Quickshell.env("XDG_CURRENT_DESKTOP") ? Quickshell.env("XDG_CURRENT_DESKTOP") : (Quickshell.env("DESKTOP_SESSION") ? Quickshell.env("DESKTOP_SESSION") : "Unknown")
    property string shell: Quickshell.env("SHELL") ? Quickshell.env("SHELL") : "Unknown"

    property string hostname: ""
    property string avatarPath: ""
    property string osName: ""
    property string kernelVersion: ""
    property string uptime: ""
    property int uptimeSeconds: 0

    property string cpuModel: ""
    property int cpuCores: 0
    property real totalRamGb: 0.0

    property string gpuModel: ""
    property string diskModel: ""
    property real diskTotalGb: 0.0
    property real diskUsedGb: 0.0
    property int diskPercent: 0

    property bool isDesktop: true

    function fetch() {
        hostnameFile.reload();
        chassisFile.reload();

        hwProc.running = false;
        hwProc.running = true;

        return {
            "username": root.username,
            "hostname": root.hostname,
            "avatarPath": root.avatarPath,
            "desktopEnv": root.desktopEnv,
            "shell": root.shell,
            "isDesktop": root.isDesktop
        };
    }

    Component.onCompleted: {
        root.fetch();
    }

    FileView {
        id: chassisFile
        path: "/sys/class/dmi/id/chassis_type"
        onLoaded: {
            let txt = text();
            if (txt) {
                let code = parseInt(txt.trim());
                let laptopCodes = [8, 9, 10, 11, 14, 30, 31, 32];
                if (laptopCodes.indexOf(code) !== -1) {
                    root.isDesktop = false;
                }
            }
        }
    }

    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        onLoaded: {
            let txt = text();
            if (txt) root.hostname = txt.trim();
        }
    }

    Process {
        id: hwProc
        running: false
        command: [
            "bash",
            "-c",
            "cropped_avatar=\"" + caching.getCacheDir("avatar") + "/avatar_cropped.png\"; " +
            "cfg_avatar=\"" + (ShellSettings.value("general.avatarPath", "") || "") + "\"; " +
            "avatar=\"\"; " +
            "if [ -f \"$cropped_avatar\" ]; then avatar=\"$cropped_avatar\"; " +
            "elif [ -n \"$cfg_avatar\" ] && [ -f \"$cfg_avatar\" ]; then avatar=\"$cfg_avatar\"; " +
            "else " +
            "for a in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do " +
                "if [ -f \"$a\" ]; then avatar=\"$a\"; break; fi; " +
            "done; fi; " +
            "has_battery=0; " +
            "for p in /sys/class/power_supply/*; do " +
                "if [ -f \"$p/type\" ] && grep -qi 'Battery' \"$p/type\" 2>/dev/null; then " +
                    "if [ -f \"$p/scope\" ] && grep -qi 'Device' \"$p/scope\" 2>/dev/null; then continue; fi; " +
                    "has_battery=1; break; " +
                "fi; " +
            "done; " +
            "echo \"$avatar|$has_battery\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text ? this.text.trim() : "";
                if (!txt) return;
                let p = txt.split("|");
                if (p.length >= 2) {
                    root.avatarPath = p[0];
                    if (p[1] === "1") {
                        root.isDesktop = false;
                    }
                }
            }
        }
    }
}
