import SwiftUI
import UIKit

/// Steven's fork: Stage Home's "Info Below the Poster" option (Settings → Home Screen, off by
/// default), like wako: the focused title's meta line and synopsis draw in a band under its row
/// rather than on the stage, which then shows only the artwork (and the logo).
nonisolated enum StageInfoBelow {
    static let defaultsKey = "home_stage_info_below"
    static let synopsisLines = 3
    /// Device pass (Steven: the rows were too far apart): no extra gap after the synopsis; the
    /// page's own focus lift (2 × 20) and `pullUp` separate it from the next heading.
    static let bottomGap: CGFloat = -10
    /// Device pass (Steven: the title sat right under the posters): 24 (was 44), the block 20 pt lower.
    static let pullUp: CGFloat = 24
    /// The bold 34 title line above the meta line (`StageTextBlock`).
    static let titleLine: CGFloat = 41
    /// The stage can be shorter in this mode: it holds no text block any more.
    static let stageFloor: CGFloat = 300
    /// Steven's fork (Orbit Home): the stage's height above the first row's heading.
    static let orbitStageHeight: CGFloat = 150
    /// Wako pass 6: the top-right stage logo's gap to the screen's right edge.
    static let logoTrailingMargin: CGFloat = 60
    /// Wako pass 10: the corner logo's top, level with the Orbit bar (38).
    static let logoTop: CGFloat = 38
    /// Wako pass 6: the shade behind the top-right logo, from this fraction of the width to the edge.
    static let rightShadeStart: CGFloat = 0.45
    static let rightShadeOpacity: Double = 0.55
    /// Wako pass 7: how far below the stage the bottom-right shade fades out.
    static let shadeFadeBelowStage: CGFloat = 160
}
