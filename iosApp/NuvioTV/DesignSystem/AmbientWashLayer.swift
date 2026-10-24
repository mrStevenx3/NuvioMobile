import Combine
import Foundation
import SharedCore
import SwiftUI
import UIKit

// Home Stage & Strip (H3, W1-B; P2 spec `docs/research/home-stage-strip-spec-P2-ambient-collections-settings.md`
// section 1): the ambient wash's model and view. `AmbientWashRenderer.swift` is the pure half.
//
// Z-order on a Stage page, bottom to top: the page's theme background, THIS layer (full screen, never
// focusable, never hit-tested), the alpha-masked stage art, the stage text and the strip. With the
// wash off, this layer renders nothing and the masked art edge shows the theme background, which
// looks like today's scrim fade.
//
// Mount it once per Stage page, at layer 0, with the stage's wash feed:
// `AmbientWashLayer(feed: stage.swap.washFeed)` (`StageStripHome`, wired by the main session at the
// W1 merge; the folder page passes `probeID: "debug_wash_folder"`).

/// The Ambient Background switch (Settings > Home Screen > Layout), device-local like every Home look
/// key: read with `@AppStorage`, never synced. On by default. `-home_ambient_background NO` works as a
/// launch argument. Both the Settings row and `AmbientWashLayer` read this one key.
nonisolated enum AmbientWashSetting {
    static let defaultsKey: String = "home_ambient_background"
    static let defaultValue: Bool = true
}

#if DEBUG
#endif

