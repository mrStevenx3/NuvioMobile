import Combine
import Foundation
import SharedCore

extension DiscoverRowsPlan {
    /// Distinct catalog types in option order (`DiscoverSources.types`, restated so the view model
    /// and its tests don't need the shared object).
    static func types(_ options: [DiscoverCatalogOption]) -> [String] {
        var seen = Set<String>()
        return options.compactMap { seen.insert($0.type).inserted ? $0.type : nil }
    }
}

#if DEBUG
#endif
