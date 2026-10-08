pragma Singleton

import "../settings"
import QtQuick
import Quickshell

// ui.radius, serpantinum v2's ThemeBackend.borderRadius as a knob. Unset or null means
// every call returns its fallback, so the shell keeps the corners it had before the knob.
Singleton {
    readonly property var raw: ShellSettings.value("ui.radius", null)
    readonly property bool active: typeof raw === "number" && isFinite(raw)
    readonly property real value: active ? Math.round(Math.max(0, Math.min(64, raw))) : 8

    // Surfaces, cards, rows, buttons: upstream's plain `radius: borderRadius`.
    function outer(fallback) { return active ? value : fallback }
    // Never past `cap` (the literal when omitted): upstream's Math.min(borderRadius, cap).
    function inner(fallback, cap) { return active ? Math.min(value, cap === undefined ? fallback : cap) : fallback }
    // A shape nested `by` px inside an outer() surface.
    function inset(fallback, by) { return active ? Math.max(0, value - by) : fallback }
    // Upstream's Math.min(cap, borderRadius * factor).
    function scaled(fallback, factor, cap) { return active ? Math.min(cap, value * factor) : fallback }
    // Upstream's clampedBorderRadius: eases past 24 for the biggest chassis.
    function eased(fallback) { return active ? (value <= 24 ? value : Math.floor(24 + Math.pow(value - 24, 0.55))) : fallback }
    // Upstream's launcher/dock/clipboard curve: doubles up to 16, then flattens toward 32.
    function chassis(fallback) { return active ? (value <= 16 ? value * 2 : Math.min(32, 32 - 16 * Math.exp(-(value - 16) / 12))) : fallback }
    // Canvas paths do not clamp the way Rectangle does; keep the arcs inside w x h.
    function fit(r, w, h) { return Math.max(0, Math.min(r, w / 2, h / 2)) }
}
