import Combine
import SwiftUI
import UIKit

/// Batch F: true inside a strip page while Short Rows Fit is on. A wide-poster card then drops its
/// reserved grown-trailer slot (`InlineTrailerCard.shapeSlotSizer`), so its row is only as tall as
/// it really is and grows while the trailer plays. Classic's planners size rows with the slot, so
/// it stays false everywhere else.
private struct StripRowFitsHeightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var stripRowFitsHeight: Bool {
        get { self[StripRowFitsHeightKey.self] }
        set { self[StripRowFitsHeightKey.self] = newValue }
    }
}

