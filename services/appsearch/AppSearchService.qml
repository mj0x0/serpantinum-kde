// Fuzzy app search over Quickshell's native DesktopEntries. Lean version of end-4's
// AppSearch: a subsequence scorer with word-boundary and contiguity bonuses.

pragma Singleton
import QtQuick
import Quickshell

Item {
    id: root

    // Visible apps, de-duplicated by id.
    readonly property var apps: {
        let all = DesktopEntries.applications ? DesktopEntries.applications.values : []
        let seen = ({})
        let out = []
        for (let i = 0; i < all.length; i++) {
            let a = all[i]
            if (!a || a.noDisplay) continue
            if (seen[a.id]) continue
            seen[a.id] = true
            out.push(a)
        }
        return out
    }

    // Subsequence score: all query chars must appear in order. Bonuses for
    // matches at word starts and for consecutive runs. 0 = no match.
    function score(query, target) {
        if (!target) return 0
        query = query.toLowerCase()
        target = target.toLowerCase()
        if (query === "") return 1
        let qi = 0, sc = 0, streak = 0, prev = -2
        for (let ti = 0; ti < target.length && qi < query.length; ti++) {
            if (target.charAt(ti) === query.charAt(qi)) {
                let bonus = 1
                if (ti === prev + 1) { streak++; bonus += streak * 2 } else { streak = 0 }
                let pc = ti > 0 ? target.charAt(ti - 1) : " "
                if (ti === 0 || pc === " " || pc === "-" || pc === "_" || pc === ".") bonus += 4
                sc += bonus
                prev = ti
                qi++
            }
        }
        if (qi < query.length) return 0
        sc += Math.max(0, 8 - target.length * 0.05)   // slight preference for shorter names
        return sc
    }

    function query(q) {
        let s = (q || "").trim()
        // Strip a leading math prefix so "=" queries don't pollute app results.
        if (s.startsWith("=")) return []
        if (s === "") {
            return apps.slice().sort((a, b) => (a.name || "").localeCompare(b.name || ""))
        }
        let scored = []
        for (let i = 0; i < apps.length; i++) {
            let a = apps[i]
            let best = score(s, a.name)
            let g = score(s, a.genericName)
            if (g > best) best = g
            if (a.keywords && a.keywords.length) {
                let ks = score(s, a.keywords.join(" ")) * 0.7
                if (ks > best) best = ks
            }
            if (best === 0) {
                let idsc = score(s, a.id) * 0.5
                if (idsc > best) best = idsc
            }
            if (best > 0) scored.push({ entry: a, score: best })
        }
        scored.sort((a, b) => b.score - a.score)
        return scored.map(x => x.entry)
    }
}
