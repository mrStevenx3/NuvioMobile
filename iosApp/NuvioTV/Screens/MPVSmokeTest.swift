import SharedCore
import AVKit
import SwiftUI

#if DEBUG

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

#endif
