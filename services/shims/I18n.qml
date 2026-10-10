// Shim, not a port: provides the keys the ported files ask for (polkit, widgets) and
// falls back to the key itself, so those files stay byte-identical to upstream.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property var strings: ({
        "polkit.default_message":      "Authentication required",
        "polkit.default_description":  "An application is attempting to perform an action that requires privileges.",
        "polkit.password_placeholder": "Password",
        "polkit.error_failed":         "Authentication failed. Please try again.",
        "widgets.redactor.no_widgets_active":"No widgets active",
        "widgets.redactor.click_to_add":     "Click a widget icon in the bottom toolbar to add it",
        "widgets.redactor.done":             "Done",
        "widgets.redactor.widget_singular":  "widget",
        "widgets.redactor.widgets_plural":   "widgets",
        "widgets.redactor.widgets_short":    "w",
        "widgets.types.clock":               "Clock",
        "widgets.types.music":               "Music",
        "widgets.types.weather":             "Weather",
        "widgets.types.image":               "Image",
        "widgets.types.visualizer":          "Visualizer",
        "widgets.types.user":                "User",
        "widgets.types.usage":               "Usage",
        "widgets.types.battery":             "Battery",
        "widgets.types.github":              "Github",
        "widgets.types.time":                "Time",
        "widgets.variants.digital":          "Digital",
        "widgets.variants.analog":           "Analog",
        "widgets.variants.full":             "Full",
        "widgets.variants.minimal":          "Minimal",
        "widgets.variants.round":            "Round",
        "widgets.variants.compact":          "Compact",
        "widgets.variants.rect":             "Rect",
        "widgets.variants.rounded":          "Rounded",
        "widgets.variants.bars":             "Bars",
        "widgets.variants.continuous":       "Continuous",
        "widgets.variants.default":          "Default",
        "widgets.variants.material":         "Material",
        "widgets.variants.materialAnalog":   "Material Analog",
        "widgets.variants.lumen":            "Lumen",
        "widgets.variants.lyrics":           "Lyrics",
        "widgets.variants.simpleLyrics":     "Simple Lyrics",
        "widgets.presets.minimal.name":      "Minimal",
        "widgets.presets.media_station.name":"Media station",
        "widgets.presets.dashboard.name":    "Dashboard",
        "widgets.github.set_user":           "Set user",
        "widgets.github.error":              "Error",
        "widgets.github.commit":             "commit",
        "widgets.github.commits":            "commits",
        "widgets.github.no_day_selected":    "No day selected",
        "widgets.github.fetching":           "Fetching GitHub contributions...",
        "widgets.github.fetch_error":        "Could not fetch user @{user}",
        "widgets.github.enter_username":     "Enter a GitHub username",
        "widgets.github.no_contributions":   "No contributions found",
        "widgets.settings.lyricsLines":      "Lines",
        "widgets.settings.lyricsAlignment":  "Alignment",
        "widgets.align.left":                "Left",
        "widgets.align.center":              "Center",
        "widgets.align.right":               "Right",
        "quickactions.systemusage.cpu":      "CPU",
        "quickactions.systemusage.ram":      "RAM",
        "quickactions.systemusage.temp":     "Temp",
        "quickactions.systemusage.disk":     "Disk",
        "music.nothing_playing":             "Nothing is playing",
        "music.searching_lyrics":            "Searching lyrics...",
        "music.no_lyrics":                   "No lyrics found",
        "music.select_local_file":           "Select a local file",
        "guide.lyrics_picker.title":         "Select lyrics file",
        "guide.lyrics_picker.no_lyrics_selected": "No lyrics selected",
        "guide.file_picker.title":           "Choose image",
        "guide.file_picker.input_placeholder": "Search...",
        "guide.file_picker.not_found":       "No files found",
        "guide.file_picker.no_file_selected": "No file selected",
        "guide.file_picker.root":            "Root",
        "guide.file_picker.places.home":     "Home",
        "guide.file_picker.places.downloads": "Downloads",
        "guide.file_picker.places.music":    "Music",
        "guide.file_picker.places.documents": "Documents",
        "guide.file_picker.places.pictures": "Pictures",
        "syspanel.battery.fully_charged":    "Fully charged",
        "syspanel.battery.charging":         "Charging",
        "syspanel.battery.charging_time":    "Charging \u2022 {hours}h {mins}m",
        "syspanel.battery.discharging":      "Discharging",
        "syspanel.battery.left_time":        "{hours}h {mins}m left"
    })

    function t(key, args) {
        var v = strings[key];
        if (v === undefined) return key;
        if (args && typeof args === "object") {
            for (var k in args) {
                v = v.replace(new RegExp("\\{" + k + "\\}", "g"), args[k]);
            }
        }
        return v;
    }
}
