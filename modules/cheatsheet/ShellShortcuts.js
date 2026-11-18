.pragma library

// Tripwire: repo-wide `grep -rn 'Shortcut {' --include='*.qml' .` when this was written.
var declarationCount = 129;

// "a/b" inside a chord is one key family, rendered as a single chip: "Up/Down", "Shift + 1/2/3".
var groups = [
    {
        name: "Volume popup",
        items: [
            { chords: ["1"], label: "Shows the Outputs tab" },
            { chords: ["2"], label: "Shows the Inputs tab" },
            { chords: ["3"], label: "Shows the Streams tab" },
            { chords: ["Tab"], label: "Cycles the tabs forward: Outputs, Inputs, Streams, and round again" },
            { chords: ["Up/Down"], label: "Moves the selection through the device list, scrolling it into view" },
            { chords: ["Return", "Enter"], label: "Makes the selected device the default output or input — Streams ignore it" },
            { chords: ["Right", "+", "="], label: "Raises the volume 5%, on the selected device or the default one" },
            { chords: ["Left", "-"], label: "Lowers the volume 5%, on the selected device or the default one" },
            { chords: ["M"], label: "Mutes or unmutes the selected device, or the default one" }
        ]
    },
    {
        name: "Music popup",
        items: [
            { chords: ["Shift + 1", "E"], label: "Shows the Equalizer tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Shift + 2", "A"], label: "Shows the Audio tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Shift + 3", "L"], label: "Shows the Lyrics tab", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Tab"], label: "Moves to the next tab, wrapping Equalizer to Audio to Lyrics", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Shift + Tab"], label: "Moves back to the previous tab, wrapping", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["1/2/3/4/5/6/7/8"], label: "Applies the EQ preset in that slot: Flat, Bass, Treble, Vocal, Pop, Rock, Jazz, Classic", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["]"], label: "Steps to the next EQ preset, wrapping around", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["["], label: "Steps to the previous EQ preset, wrapping around", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["0"], label: "Flattens the equalizer back to the Flat preset", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Ctrl + =", "Ctrl + +"], label: "Makes the lyrics text one step bigger, up to 2x", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Ctrl + -"], label: "Makes the lyrics text one step smaller, down to 0.7x", condition: "Unless the Artist or Song search box has focus" },
            { chords: ["Ctrl + 0"], label: "Resets the lyrics text back to normal size", condition: "Unless the Artist or Song search box has focus" }
        ]
    },
    {
        name: "Music popup — Lyrics tab",
        items: [
            { chords: [","], label: "Nudges this track's lyric timing 0.1s earlier and saves it", condition: "While the Lyrics tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["."], label: "Nudges this track's lyric timing 0.1s later and saves it", condition: "While the Lyrics tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["R"], label: "Re-fetches the lyrics for this track, bypassing the cache", condition: "While the Lyrics tab is showing, unless the Artist or Song search box has focus" }
        ]
    },
    {
        name: "Music popup — Audio tab",
        items: [
            { chords: ["Left"], label: "Shifts the stereo balance 0.05 toward the left speaker", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["Right"], label: "Shifts the stereo balance 0.05 toward the right speaker", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["M"], label: "Toggles the mono downmix on or off", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["S"], label: "Toggles swapping the left and right channels", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["D"], label: "Cycles dynamic range compression: off, balanced, night", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["T"], label: "Starts or stops the left/right test tone, which also stops itself after about 3s", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" },
            { chords: ["R"], label: "Resets audio: balance centred, mono and swap off, dynamics off, tone stopped", condition: "While the Audio tab is showing, unless the Artist or Song search box has focus" }
        ]
    },
    {
        name: "Notification centre",
        items: [
            { chords: ["Tab"], label: "Moves to the next section: notifications, quick actions, power buttons, power profile" },
            { chords: ["Shift + Tab"], label: "Moves to the previous section" },
            { chords: ["Down"], label: "Selects the next notification down, or steps forward through the focused row of buttons" },
            { chords: ["Up"], label: "Selects the notification above, or steps back through the focused row of buttons" },
            { chords: ["Right"], label: "Expands the selected notification group and marks it read, or steps forward through the focused row" },
            { chords: ["Left"], label: "Collapses the selected notification group, or steps back through the focused row" },
            { chords: ["Return", "Enter", "Space"], label: "Activates the selection: opens the notification or folds its group, flips the quick-action toggle, or arms then confirms the power button" },
            { chords: ["Backspace", "Delete"], label: "Dismisses the selected notification or group; with nothing selected the first press only selects" },
            { chords: ["Shift + Backspace", "Shift + Delete"], label: "Clears every notification, sliding the visible cards away first" },
            { chords: ["D"], label: "Turns Do Not Disturb on or off" }
        ]
    },
    {
        name: "Network panel",
        items: [
            { chords: ["1"], label: "Opens the VPN tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["2"], label: "Opens the Wi-Fi tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["3"], label: "Opens the Ethernet tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["4"], label: "Opens the Servers tab", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["Tab"], label: "Moves to the next tab, wrapping round from Servers back to VPN", condition: "Unless a password or text field in the open tab has the keyboard" },
            { chords: ["Shift + Tab"], label: "Moves to the previous tab, wrapping round from VPN back to Servers", condition: "Unless a password or text field in the open tab has the keyboard" }
        ]
    },
    {
        name: "Clipboard panel",
        items: [
            { chords: ["Ctrl + 1"], label: "Shows the Recent view and puts the cursor back in the search box", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + 2"], label: "Shows the Images grid and loads the rest of the history", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + 3"], label: "Shows the Text-only view and loads the rest of the history", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + Tab"], label: "Cycles forward through Recent, Images and Text", condition: "Only while the clipboard panel is open" },
            { chords: ["Ctrl + Shift + Tab"], label: "Cycles backward through Recent, Images and Text", condition: "Only while the clipboard panel is open" }
        ]
    },
    {
        name: "Floating sidebar",
        items: [
            { chords: ["1/2/3"], label: "Jumps straight to that tab and expands the panel: 1 Colour picker, 2 System usage, 3 Timer", condition: "While the sidebar is showing, unless the open tab has claimed that digit" },
            { chords: ["Tab"], label: "Moves to the next tab, wrapping, and restarts the auto-hide countdown", condition: "While the sidebar is showing, unless the open tab has claimed Tab" },
            { chords: ["Shift + Tab"], label: "Moves to the previous tab, wrapping, and restarts the auto-hide countdown", condition: "While the sidebar is showing, unless the open tab has claimed Shift+Tab" },
            { chords: ["Return", "Enter"], label: "Expands the sidebar into the full panel, or collapses it again", condition: "While the sidebar is showing, unless the open tab has claimed it — the Timer tab does, to start and stop" },
            { chords: ["Left"], label: "Moves one tab back along the rail, stopping at the first", condition: "While the sidebar is docked to the bottom edge, unless the open tab has claimed Left" },
            { chords: ["Right"], label: "Moves one tab forward along the rail, stopping at the last", condition: "While the sidebar is docked to the bottom edge, unless the open tab has claimed Right" },
            { chords: ["Up"], label: "Steps one tab along the rail: back on the left edge, forward on the right", condition: "While the sidebar is docked to the left or right edge, unless the open tab has claimed Up" },
            { chords: ["Down"], label: "Steps one tab along the rail: forward on the left edge, back on the right", condition: "While the sidebar is docked to the left or right edge, unless the open tab has claimed Down" },
            { chords: ["Escape"], label: "Collapses the expanded panel, or hides the sidebar back to its edge peek once it is already collapsed", condition: "While the sidebar is showing and unpinned, unless the open tab has claimed Escape" }
        ]
    },
    {
        name: "Timer tab",
        items: [
            { chords: ["Shift + 1/2/3"], label: "Switches between the Timer, Stopwatch and Pomodoro modes" },
            { chords: ["Return", "Enter", "Space"], label: "Starts or pauses whichever of the three modes is showing" },
            { chords: ["R"], label: "Resets the mode on screen: timer back to its preset (or to zero if it is already there), stopwatch and laps cleared, pomodoro back to a fresh focus session" },
            { chords: ["Left/Right"], label: "Selects the digit pair to either side: hours, minutes, seconds", condition: "Only in Timer mode, while the countdown is stopped and still showing its preset" },
            { chords: ["Up/Down"], label: "Adds one to or takes one off the selected digit pair, carrying at 60 and stopping at zero", condition: "Only in Timer mode, while the countdown is stopped and still showing its preset" }
        ]
    },
    {
        name: "Screenshot overlay",
        items: [
            { chords: ["Return", "Space"], label: "Takes the shot of the selection, or starts and stops the recording in video mode" },
            { chords: ["Tab"], label: "Switches between screenshot and screen-recording mode" },
            { chords: ["Left"], label: "Switches to screenshot mode, restoring the photo region you had parked" },
            { chords: ["Right"], label: "Switches to screen-recording mode, which selects the whole screen" },
            { chords: ["F11"], label: "Toggles the selection between the whole screen and the region you had drawn" },
            { chords: ["F"], label: "Starts recording the whole screen in video mode; otherwise toggles the full-screen selection" },
            { chords: ["T"], label: "Runs OCR over the selected region and shows the recognised text", condition: "Only in screenshot mode, not in recording mode" },
            { chords: ["Escape"], label: "Dismisses the OCR card, then the QR card, then the overlay itself" }
        ]
    },
    {
        name: "Settings",
        items: [
            { chords: ["Ctrl + F", "Ctrl + K"], label: "Opens the settings search and puts the cursor in the search box" },
            { chords: ["Ctrl + PgDown", "Ctrl + Tab"], label: "Goes to the next settings page, stepping through a section's subpages first" },
            { chords: ["Ctrl + PgUp", "Ctrl + Shift + Tab"], label: "Goes to the previous settings page, stepping back through a section's subpages first" },
            { chords: ["Ctrl + W", "Ctrl + Q"], label: "Closes the Settings window" },
            { chords: ["Escape"], label: "Clears the search or drops focus out of a field first, and only then closes Settings" }
        ]
    },
    {
        name: "Wallpaper picker",
        items: [
            { chords: ["Left"], label: "Selects the previous wallpaper, rolling back into the previous filter when it runs out", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Right"], label: "Selects the next wallpaper, rolling on into the next filter when it runs out", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Up/Down"], label: "Moves a row in the grid view, or a page in the fan view — Slices ignores it", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Return"], label: "Sets the selected wallpaper and closes the picker", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Space"], label: "Opens or closes the full-size preview of the highlighted wallpaper", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Tab"], label: "Moves to the next filter chip in the top bar", condition: "Not while a wallpaper is being applied, and not on the Wallhaven tab" },
            { chords: ["Shift + Tab"], label: "Moves to the previous filter chip in the top bar", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Shift + 1/2/3/4/5/6/7/8"], label: "Filters by colour: Red, Orange, Yellow, Green, Blue, Purple, Pink, Monochrome", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field; the shifted symbols !@#$%^&* work too" },
            { chords: ["Shift + 9"], label: "Opens the Wallhaven tab", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Shift + 0"], label: "Clears the filter back to All wallpapers", condition: "Not while a wallpaper is being applied, and not while typing in the Wallhaven search field" },
            { chords: ["Ctrl + 1/2/3"], label: "Switches the layout and remembers it: 1 Slices, 2 Wall grid, 3 Hand fan", condition: "Not while a wallpaper is being applied, not on the Wallhaven tab, and not while typing in the Wallhaven search field" }
        ]
    },
    {
        name: "Wallpaper picker — Wallhaven tab",
        items: [
            { chords: ["Left/Right"], label: "Moves the highlight between search results", condition: "Only while the search field is not focused" },
            { chords: ["Up"], label: "Moves the highlight up one row of results", condition: "Only while the search field is not focused" },
            { chords: ["Down"], label: "Drops out of the search field into the result grid, or moves the highlight down one row when already there" },
            { chords: ["Tab"], label: "Opens or closes the full-size preview, fetching the full image if only a thumbnail is cached", condition: "Only while the search field is not focused" },
            { chords: ["Return"], label: "Downloads the highlighted wallpaper — setting it straight away if it is already saved — and closes the preview", condition: "Only while the search field is not focused" }
        ]
    },
    {
        name: "Power panel",
        items: [
            { chords: ["Tab"], label: "Flips between the status nodes and the ring of apps holding the machine awake" },
            { chords: ["Shift + 1"], label: "Switches to the first power profile offered (Performance)", condition: "Only when the system reports power profiles" },
            { chords: ["Shift + 2"], label: "Switches to the second power profile offered (Balanced)", condition: "Only when the system reports power profiles" },
            { chords: ["Shift + 3"], label: "Switches to the third power profile offered (Power saver)", condition: "Only when the system reports power profiles and offers a third one" }
        ]
    },
    {
        name: "Focus Time",
        items: [
            { chords: ["Left"], label: "Goes back a day, or a whole week while the week overview is showing" },
            { chords: ["Right"], label: "Goes forward a day, or a whole week while the week overview is showing" },
            { chords: ["Home"], label: "Jumps back seven days, whichever view is showing" },
            { chords: ["End"], label: "Jumps forward seven days, whichever view is showing" }
        ]
    },
    {
        name: "Theme picker",
        items: [
            { chords: ["Return", "Enter"], label: "Applies the highlighted theme shell-wide and closes the picker" },
            { chords: ["Escape"], label: "Closes the picker and puts the previous theme back, discarding the live preview" }
        ]
    },
    {
        name: "Calendar",
        items: [
            { chords: ["Left"], label: "Steps the calendar back a month while the pointer is over it, otherwise moves the weather back a forecast day" },
            { chords: ["Right"], label: "Steps the calendar forward a month while the pointer is over it, otherwise moves the weather forward a forecast day, up to 4 days out" }
        ]
    },
    {
        name: "Bar popups",
        items: [
            { chords: ["Escape"], label: "In any bar popup — Network, Bluetooth, Power, Volume, Music, notifications — lets the popup back out of its own state first (search, sub-tab) and closes it only if the popup does not take it" }
        ]
    },
    {
        name: "Widget redactor",
        items: [
            { chords: ["Escape"], label: "Deselects the widget and leaves the redactor, switching the desktop widgets back out of edit mode" }
        ]
    },
    {
        name: "File picker",
        items: [
            { chords: ["Escape"], label: "Closes the picker without choosing anything" },
            { chords: ["Tab"], label: "Moves to the next place in the sidebar", condition: "Only while the picker lists places" },
            { chords: ["Shift + Tab"], label: "Moves to the previous place in the sidebar", condition: "Only while the picker lists places" },
            { chords: ["Return", "Enter"], label: "Opens the highlighted entry, or confirms the current selection" }
        ]
    },
    {
        name: "Authentication prompt",
        items: [
            { chords: ["Escape"], label: "Cancels the request and dismisses the polkit prompt" },
            { chords: ["Return", "Enter"], label: "Submits the password", condition: "Only once something has been typed" }
        ]
    }
];

for (var gi = 0; gi < groups.length; gi++)
    for (var ii = 0; ii < groups[gi].items.length; ii++)
        groups[gi].items[ii].group = groups[gi].name;
