import ".."
import "../../../services/settings"
import "../../../services/dnd"
import QtQuick
import QtQuick.Layouts
import Quickshell

SettingsPage {
    id: page

    SettingsRow {
        host: page.host
        label: "Position"
        glyph: "\u{f009a}"
        desc: "Where toasts stack, clear of the bar; bottom presets grow upward"
        SettingsChips {
            host: page.host
            width: page.host.s(430)
            options: ["top left", "top center", "top right",
                      "bottom left", "bottom center", "bottom right", "custom"]
            current: "" + ShellSettings.value("notifications.position", "top right")
            onPicked: v => ShellSettings.setValue("notifications.position", v)
        }
    }
    SettingsRow {
        host: page.host
        visible: ShellSettings.value("notifications.position", "top right") === "custom"
        label: "Custom position"
        glyph: "\u{f01a3}"
        desc: "Percent across, then down the screen"
        RowLayout {
            spacing: page.host.s(12)
            SettingsSlider {
                host: page.host
                from: 0; to: 100; step: 1
                value: Number(ShellSettings.value("notifications.horizontalPosition", 95))
                onCommitted: v => ShellSettings.setValue("notifications.horizontalPosition", v)
            }
            SettingsSlider {
                host: page.host
                from: 0; to: 100; step: 1
                value: Number(ShellSettings.value("notifications.verticalPosition", 5))
                onCommitted: v => ShellSettings.setValue("notifications.verticalPosition", v)
            }
        }
    }
    SettingsRow {
        host: page.host
        label: "Do not disturb"
        glyph: "\u{f009c}"
        desc: DndState.enabled && DndState.until > 0
            ? "Silenced for " + DndState.remainingLabel() + " more"
            : "Toasts stay quiet, critical ones still show. Kept out of settings.json"
        SettingsToggle {
            host: page.host
            checked: DndState.enabled
            onToggled: v => { if (v) DndState.enable(); else DndState.disable(); }
        }
    }
    SettingsRow {
        host: page.host
        label: "Empty graphic"
        glyph: "\u{f02e9}"
        desc: "Animated mascot in the panel when there is nothing to show"
        SettingsToggle {
            host: page.host
            checked: ShellSettings.value("notifications.showEmptyGraphic", true) !== false
            onToggled: v => ShellSettings.setValue("notifications.showEmptyGraphic", v)
        }
    }
    SettingsRow {
        host: page.host
        label: "Test"
        glyph: "\u{f048a}"
        desc: "Sent over the bus like any app's. The action one lingers until dismissed"
        RowLayout {
            spacing: page.host.s(8)
            SettingsBtn {
                host: page.host
                label: "Send test"
                onClicked: Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "dialog-information",
                                                    "Test notification", "Lands at the chosen preset."])
            }
            SettingsBtn {
                host: page.host
                label: "With action"
                onClicked: Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "dialog-information",
                                                    "-A", "open=Open", "Test with action", "Expand the card for the button."])
            }
            SettingsBtn {
                host: page.host
                label: "Critical"
                onClicked: Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-u", "critical", "-i", "dialog-warning",
                                                    "Critical test", "Stays until dismissed, even under Do not disturb."])
            }
        }
    }
}
