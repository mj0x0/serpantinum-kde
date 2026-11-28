.pragma library

// Tripwire: repo-wide `grep -rn 'Shortcut {' --include='*.qml' .` when this was written.
var declarationCount = 138;

// "a/b" inside a chord is one key family, rendered as a single chip: "Up/Down", "Shift + 1/2/3".
var groups = [
    {
        name: "Volume popup",
        items: [
            { chords: ["1"], label: "Outputs tab" },
            { chords: ["2"], label: "Inputs tab" },
            { chords: ["3"], label: "Streams tab" },
            { chords: ["Tab"], label: "Next tab" },
            { chords: ["Up/Down"], label: "Move through the devices" },
            { chords: ["Return", "Enter"], label: "Make the device default" },
            { chords: ["Right", "+", "="], label: "Volume up 5%" },
            { chords: ["Left", "-"], label: "Volume down 5%" },
            { chords: ["M"], label: "Mute or unmute" }
        ]
    },
    {
        name: "Music popup",
        items: [
            { chords: ["Shift + 1", "E"], label: "Equalizer tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Shift + 2", "A"], label: "Audio tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Shift + 3", "L"], label: "Lyrics tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Tab"], label: "Next tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Shift + Tab"], label: "Previous tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["1/2/3/4/5/6/7/8"], label: "EQ preset in that slot", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["]"], label: "Next EQ preset", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["["], label: "Previous EQ preset", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["0"], label: "Reset the EQ to Flat", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Ctrl + =", "Ctrl + +"], label: "Lyrics text bigger", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Ctrl + -"], label: "Lyrics text smaller", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Ctrl + 0"], label: "Lyrics text normal size", condition: "Unless the Artist or Song search box has focus" }
        ]
    },
    {
        name: "Music popup — Audio tab",
        items: [
            { chords: ["Left"], label: "Balance left", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["Right"], label: "Balance right", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["M"], label: "Mono downmix", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["S"], label: "Swap the channels", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["D"], label: "Cycle the dynamics", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["T"], label: "Test tone", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["R"], label: "Reset the audio settings", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" }
        ]
    },
    {
        name: "Music popup — Lyrics tab",
        items: [
            { chords: [","], label: "Lyrics 0.1s earlier", condition: "While the Lyrics tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["."], label: "Lyrics 0.1s later", condition: "While the Lyrics tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["R"], label: "Re-fetch the lyrics", condition: "While the Lyrics tab is showing, unless the Artist or Song search box has focus" }
        ]
    },
    {
        name: "Notification centre",
        items: [
            { chords: ["Tab"], label: "Next section" },
            { chords: ["Shift + Tab"], label: "Previous section" },
            { chords: ["Down"], label: "Next notification" },
            { chords: ["Up"], label: "Previous notification" },
            { chords: ["Right"], label: "Expand the group, mark it read" },
            { chords: ["Left"], label: "Collapse the group" },
            { chords: ["Return", "Enter", "Space"], label: "Activate the selection" },
            { chords: ["Backspace", "Delete"], label: "Dismiss the notification" },
            { chords: ["Shift + Backspace", "Shift + Delete"], label: "Clear every notification" },
            { chords: ["D"], label: "Do Not Disturb" }
        ]
    },
    {
        name: "Network panel",
        items: [
            { chords: ["1"], label: "VPN tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["2"], label: "Wi-Fi tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["3"], label: "Ethernet tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["4"], label: "Servers tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["Tab"], label: "Next tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["Shift + Tab"], label: "Previous tab", condition: "Unless a password or text field in the open tab has the keyboard" }
        ]
    },
    {
        name: "Clipboard panel",
        items: [
            { chords: ["Ctrl + 1"], label: "Recent view", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + 2"], label: "Images grid", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + 3"], label: "Text-only view", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + Tab"], label: "Next view", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + Shift + Tab"], label: "Previous view", condition: "Only while the clipboard panel is open" }
        ]
    },
    {
        name: "Floating sidebar",
        items: [
            { chords: ["1/2/3/4"], label: "Jump to that tab and expand", condition: "While the sidebar is showing, unless the open tab has claimed that digit" },
            { chords: ["Tab"], label: "Next tab", condition: "While the sidebar is showing, unless the open tab has claimed Tab" },
            { chords: ["Shift + Tab"], label: "Previous tab", condition: "While the sidebar is showing, unless the open tab has claimed Shift+Tab" },
            { chords: ["Return", "Enter"], label: "Expand or collapse the panel", condition: "While the sidebar is showing, unless the open tab has claimed it — the Timer tab does, to start and stop" },
            { chords: ["Left"], label: "Back along the rail", condition: "While the sidebar is docked to the bottom edge, unless the open tab has claimed Left" },
            { chords: ["Right"], label: "Forward along the rail", condition: "While the sidebar is docked to the bottom edge, unless the open tab has claimed Right" },
            { chords: ["Up"], label: "One tab up the rail", condition: "While the sidebar is docked to the left or right edge, unless the open tab has claimed Up" },
            { chords: ["Down"], label: "One tab down the rail", condition: "While the sidebar is docked to the left or right edge, unless the open tab has claimed Down" },
            { chords: ["Escape"], label: "Collapse, then hide", condition: "While the sidebar is showing and unpinned, unless the open tab has claimed Escape" }
        ]
    },
    {
        name: "Timer tab",
        items: [
            { chords: ["Shift + 1/2/3"], label: "Timer, Stopwatch or Pomodoro" },
            { chords: ["Return", "Enter", "Space"], label: "Start or pause" },
            { chords: ["R"], label: "Reset the current mode" },
            { chords: ["Left/Right"], label: "Pick hours, minutes or seconds", condition: "Only in Timer mode, while the countdown is stopped and still showing its preset" },
            { chords: ["Up/Down"], label: "Adjust the selected digits", condition: "Only in Timer mode, while the countdown is stopped and still showing its preset" }
        ]
    },
    {
        name: "Notes tab",
        items: [
            { chords: ["Ctrl + N"], label: "New note", condition: "Saves the open note first" },
            { chords: ["Ctrl + S"], label: "Save, keep editing", condition: "While editing a note" },
            { chords: ["Ctrl + Return", "Ctrl + Enter"], label: "Save and close", condition: "While editing a note" },
            { chords: ["Escape"], label: "Save and close", condition: "While editing a note" },
            { chords: ["Ctrl + E"], label: "Toggle markdown preview", condition: "While editing a note" },
            { chords: ["Ctrl + P"], label: "Pin or unpin", condition: "The open note while editing, otherwise every selected note" },
            { chords: ["Ctrl + Shift + D"], label: "Delete", condition: "The open note while editing, otherwise every selected note" },
            { chords: ["Escape"], label: "Clear the selection", condition: "While notes are selected and no note is open" }
        ]
    },
    {
        name: "Screenshot overlay",
        items: [
            { chords: ["Return", "Space"], label: "Capture, or start and stop" },
            { chords: ["Tab"], label: "Switch the capture mode" },
            { chords: ["Left"], label: "Screenshot mode" },
            { chords: ["Right"], label: "Recording mode" },
            { chords: ["F11"], label: "Whole screen or your region" },
            { chords: ["F"], label: "Full screen: record or select" },
            { chords: ["T"], label: "OCR the selection", condition: "Only in screenshot mode, not in recording mode" },
            { chords: ["Escape"], label: "Dismiss the card, then the overlay" }
        ]
    },
    {
        name: "Settings",
        items: [
            { chords: ["Ctrl + F", "Ctrl + K"], label: "Search the settings" },
            { chords: ["Ctrl + PgDown", "Ctrl + Tab"], label: "Next page" },
            { chords: ["Ctrl + PgUp", "Ctrl + Shift + Tab"], label: "Previous page" },
            { chords: ["Ctrl + W", "Ctrl + Q"], label: "Close Settings" },
            { chords: ["Escape"], label: "Clear the search, then close" }
        ]
    },
    {
        name: "Wallpaper picker",
        items: [
            { chords: ["Left"], label: "Previous wallpaper", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Right"], label: "Next wallpaper", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Up/Down"], label: "A row in the grid, a page in the fan", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Return"], label: "Set it and close the picker", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Space"], label: "Toggle the full-size preview", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Tab"], label: "Next filter chip", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Shift + Tab"], label: "Previous filter chip", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Shift + 1/2/3/4/5/6/7/8"], label: "Filter by colour", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field; the shifted symbols !@#$%^&* work too" },
            { chords: ["Shift + 9"], label: "Wallhaven tab", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Shift + 0"], label: "Clear the filter", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Ctrl + 1/2/3"], label: "Layout: Slices, Wall or Fan", condition: "Not while a wallpaper is being applied, not on the Wallhaven tab, and not while typing in the Wallhaven search field" }
        ]
    },
    {
        name: "Wallpaper picker — Wallhaven tab",
        items: [
            { chords: ["Left/Right"], label: "Move between the results", condition: "Only while the search field is not focused" },
            { chords: ["Up"], label: "Up one row", condition: "Only while the search field is not focused" },
            { chords: ["Down"], label: "Into the results, then down a row" },
            { chords: ["Tab"], label: "Toggle the full-size preview", condition: "Only while the search field is not focused" },
            { chords: ["Return"], label: "Download, or set it if saved", condition: "Only while the search field is not focused" }
        ]
    },
    {
        name: "Power panel",
        items: [
            { chords: ["Tab"], label: "Status nodes or the wake ring" },
            { chords: ["Shift + 1"], label: "Performance profile", condition: "Only when the system reports power profiles" },
            { chords: ["Shift + 2"], label: "Balanced profile", condition: "Only when the system reports power profiles" },
            { chords: ["Shift + 3"], label: "Power saver profile", condition: "Only when the system reports power profiles and offers a third one" }
        ]
    },
    {
        name: "Focus Time",
        items: [
            { chords: ["Left"], label: "Back a day, or a week" },
            { chords: ["Right"], label: "Forward a day, or a week" },
            { chords: ["Home"], label: "Back seven days" },
            { chords: ["End"], label: "Forward seven days" }
        ]
    },
    {
        name: "Theme picker",
        items: [
            { chords: ["Return", "Enter"], label: "Apply the theme and close" },
            { chords: ["Escape"], label: "Close and put the old theme back" }
        ]
    },
    {
        name: "Calendar",
        items: [
            { chords: ["Left"], label: "Back a month, or a forecast day" },
            { chords: ["Right"], label: "Forward a month, or a forecast day" }
        ]
    },
    {
        name: "Bar popups",
        items: [
            { chords: ["Escape"], label: "Back out, then close the popup" }
        ]
    },
    {
        name: "Widget redactor",
        items: [
            { chords: ["Escape"], label: "Deselect, then leave edit mode" }
        ]
    },
    {
        name: "File picker",
        items: [
            { chords: ["Escape"], label: "Close without choosing" },
            { chords: ["Tab"], label: "Next place", condition: "Only while the picker lists places" },
            { chords: ["Shift + Tab"], label: "Previous place", condition: "Only while the picker lists places" },
            { chords: ["Return", "Enter"], label: "Open the entry, or confirm" }
        ]
    },
    {
        name: "Authentication prompt",
        items: [
            { chords: ["Escape"], label: "Cancel the request" },
            { chords: ["Return", "Enter"], label: "Submit the password", condition: "Only once something has been typed" }
        ]
    }
];

for (var gi = 0; gi < groups.length; gi++)
    for (var ii = 0; ii < groups[gi].items.length; ii++)
        groups[gi].items[ii].group = groups[gi].name;
