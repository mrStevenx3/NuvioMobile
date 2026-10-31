import Combine
import SwiftUI

// Orbit Home (Steven's fork): every measure of the page, taken from Steven's reference video
// (a 1080p TV filmed at 1280 × 720: the screen spans ≈ 1170 px of it, so 1 px ≈ 1.64 pt).
//
//     bar band                               y 25…98 (the Orbit bar)
//     hero        top 115, 1776 × 860, radius 24
//     genres      chips 272 × 156, gap 22, the focused chip pinned at the left margin
//     row         heading centre at the anchor; cards 44 below it, 500 tall;
//                 the focused title in a 16:9 frame (889 × 500) at the left margin, posters
//                 320 × 500 after it (gap 16), the previous poster a sliver at the screen's edge;
//                 meta line centre 582, synopsis (3 lines of 34) from 626; next row 820 below.
//
// The focused section is brought to a fixed screen line (hero top 115, chips top 144, row heading
// 150); the sections above it fade out as they leave, the next one peeks at the bottom.

enum OrbitHomeLayout {
    static let screenWidth: CGFloat = 1920
    static let screenHeight: CGFloat = 1080

    /// The left margin of headings, the frame, the chips and the hero.
    static let margin: CGFloat = 72

    // Hero (Steven, 2026-10-25, pass 2: full screen, as the platforms' carousels)
    static let heroTop: CGFloat = 0
    static let heroHeight: CGFloat = screenHeight
    static let heroRadius: CGFloat = 0
    static var heroWidth: CGFloat { screenWidth }
    /// Where the hero's details end (their bottom); the dots under them.
    /// (Steven, 2026-10-31: the hero full screen — its details lower, 65 points.)
    static let heroInfoBottom: CGFloat = 965
    /// The page dots' line (under the details, near the screen's foot).
    static let heroDotsY: CGFloat = 1022
    /// From the hero's top to the first row's heading centre (the heading peeks at the bottom).
    static let heroPitch: CGFloat = 1000

    // Genres
    static let chipWidth: CGFloat = 272
    static let chipHeight: CGFloat = 156
    static let chipGap: CGFloat = 22
    static let chipRadius: CGFloat = 20
    static let chipsTop: CGFloat = 144
    /// From the chips' top to the first row's heading centre.
    static let genresPitch: CGFloat = 261

    // Rows
    static let rowAnchor: CGFloat = 150
    // Steven (device, 2026-10-25): the classic row 15 % smaller — it took the whole screen and
    // overshadowed the Top 10; the next row now shows below it.
    static let rowPitch: CGFloat = 745
    static let cardsTop: CGFloat = 44
    static let cardHeight: CGFloat = 425
    static let posterWidth: CGFloat = 272
    static let frameWidth: CGFloat = 756
    static let gap: CGFloat = 16
    static let posterRadius: CGFloat = 10
    static let frameRadius: CGFloat = 12
    static let frameBorder: CGFloat = 4
    static let metaCentre: CGFloat = 507
    static let synopsisTop: CGFloat = 535
    static let synopsisWidth: CGFloat = 960
    static let headingFont: CGFloat = 30
    static let metaFont: CGFloat = 28
    static let synopsisFont: CGFloat = 26
    static let synopsisLineSpacing: CGFloat = 4

    /// A card's x for its distance `d` from the row's lead (0 = in the frame, under it).
    static func cardX(_ d: Int) -> CGFloat {
        if d == 0 { return margin }
        if d > 0 { return margin + frameWidth + gap + CGFloat(d - 1) * (posterWidth + gap) }
        return margin - gap - posterWidth + CGFloat(d + 1) * (posterWidth + gap)
    }

    /// A chip's x for its distance from the focused chip.
    static func chipX(_ d: Int) -> CGFloat { margin + CGFloat(d) * (chipWidth + chipGap) }

    // Motion
    static let horizontal = Animation.easeOut(duration: 0.26)
    static let vertical = Animation.easeInOut(duration: 0.38)
    static let crossfade = Animation.easeInOut(duration: 0.22)

    static let green = Color(red: 0.24, green: 0.86, blue: 0.40)
    static let background = Color(red: 0.03, green: 0.03, blue: 0.04)
    /// Steven (2026-10-31, trying it: the TV's halos round bright posters on a dark ground — "si ça
    /// me plaît pas, j'aurai une autre solution"): a more even ground behind the rows. The darkening
    /// towards the bottom lighter (was 0.55), and the blacks lifted a little (was none). Back to
    /// 0.55 and 0 to undo.
    static let footShade: Double = 0.3
    static let floorLift: Double = 0.035
}
