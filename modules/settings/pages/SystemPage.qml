import ".."
import "../../../services/settings"
import "../../../services/polkit"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

SettingsPage {
    id: page

    // Polkit allows one agent per session: KDE's unit has to be masked before ours can register.
    property string kdeAgentState: ""
    Process {
        id: kdeAgentProbe
        running: true
        command: ["systemctl", "--user", "is-enabled", "plasma-polkit-agent.service"]
        stdout: StdioCollector {
            onStreamFinished: {
                var was = page.kdeAgentState;
                page.kdeAgentState = this.text.trim();
                // Our agent only registers at construction, and polkit allows one per session.
                // The guard matters: naming PolkitService builds it, and an unwanted agent
                // would take the slot KDE is meant to keep.
                if (was !== "" && was !== "masked" && page.kdeAgentState === "masked"
                    && ShellSettings.value("polkit.enabled", false) === true)
                    PolkitService.reregister();
            }
        }
    }
    // `mask --now` is detached, so the unit takes a moment to go; re-probe a few times.
    Timer {
        id: kdeAgentRefresh
        interval: 1500
        repeat: true
        property int left: 0
        onTriggered: {
            kdeAgentProbe.running = false;
            kdeAgentProbe.running = true;
            if (--kdeAgentRefresh.left <= 0)
                kdeAgentRefresh.stop();
        }
    }
    function kdeAgent(mask) {
        Quickshell.execDetached(["sh", "-c", mask
            ? "systemctl --user mask --now plasma-polkit-agent.service"
            : "systemctl --user unmask plasma-polkit-agent.service && systemctl --user start plasma-polkit-agent.service"]);
        kdeAgentRefresh.left = 4;
        kdeAgentRefresh.restart();
    }

    SettingsRow {
        host: page.host
        label: "Polkit agent"
        glyph: "\u{f0498}"
        desc: "This shell answers authentication prompts with its own dialog. Registers as "
            + "soon as it is on, provided KDE's agent below is masked"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("polkit.enabled", false) === true
            onToggled: v => ShellSettings.setValue("polkit.enabled", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "KDE's polkit agent"
        glyph: "\u{f0582}"
        desc: page.kdeAgentState === "masked"
            ? "Masked, so this shell's agent can register. Unmask to hand prompts back to KDE"
            : (page.kdeAgentState === "" ? "Checking the user unit…"
               : "Active (" + page.kdeAgentState + "). Polkit allows one agent per session, "
                 + "so mask it to let this shell's agent take over")
        RowLayout {
            spacing: page.host.s(8)
            SettingsBtn {
                host: page.host
                label: "Mask"
                enabled: page.kdeAgentState !== "masked"
                opacity: enabled ? 1 : 0.4
                onClicked: page.kdeAgent(true)
            }
            SettingsBtn {
                host: page.host
                label: "Unmask"
                enabled: page.kdeAgentState === "masked"
                opacity: enabled ? 1 : 0.4
                onClicked: page.kdeAgent(false)
            }
        }
    }
}
