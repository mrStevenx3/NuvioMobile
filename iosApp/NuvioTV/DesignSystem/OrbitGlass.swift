import SwiftUI

/// Steven (2026-10-30: "un truc uniforme"): Orbit's one glass — every see-through control (the bar's
/// pills, the house, the hero's and the title page's buttons, the chips, the panels) is the same
/// slightly dark glass, so white icons and words read on a bright picture too.
enum OrbitGlass {
    /// The glass's tint (over the bar's blur, or alone on a button).
    static let tint = Color.black.opacity(0.34)
    /// Its fine light edge (Steven, 2026-10-30: on a dark poster the dark glass vanished) — the glass
    /// shows on a dark picture by its edge, on a bright one by its tint.
    static let rim = Color.white.opacity(0.3)
}
