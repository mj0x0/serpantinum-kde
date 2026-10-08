.pragma library

// Shared ellipse maths for the orbital panels (Network tabs, Bluetooth), so a ring's
// angles, radii and clamped card positions are derived in one place.

// Evenly spaced slot `i` of `n`, offset by the ambient spin.
function slotAngle(i, n, spin) {
    return spin + (i / Math.max(1, n)) * Math.PI * 2;
}

// A stable slot in a fixed-size ring, drifting at `rate` of the ambient spin.
function ringAngle(slot, slots, spin, rate) {
    return (slot / Math.max(1, slots)) * Math.PI * 2 + spin * rate;
}

// Top-left of a w x h card centred on an ellipse inside a cw x ch container.
function pos(cw, ch, angle, radX, radY, w, h) {
    return {
        x: cw / 2 + Math.cos(angle) * radX - w / 2,
        y: ch / 2 + Math.sin(angle) * radY - h / 2
    };
}

function clampIn(p, w, h, cw, ch) {
    return {
        x: Math.max(0, Math.min(p.x, cw - w)),
        y: Math.max(0, Math.min(p.y, ch - h))
    };
}

// base/step are {x,y}: the ring widens past four nodes and `drift` pushes it all outward.
function ringRadii(base, drift, count, step) {
    var over = Math.max(0, count - 4);
    return {
        x: base.x + drift + step.x * over,
        y: base.y + drift * 0.6 + step.y * over
    };
}
