import SharedCore

// Steven's fork (2026-10-24): Chris's episodes section is gone (the Orbit detail page draws its own,
// `OrbitEpisodesSection`). What stays is shared by the detail view model.

enum EpisodesSection {
    /// True if this title should show an episode list at all.
    static func isSeriesLike(_ meta: MetaDetails) -> Bool {
        meta.type == "series" || meta.videos.contains { $0.season != nil || $0.episode != nil }
    }
}

/// `KotlinInt` is an `NSNumber` subclass, whose `.intValue` Swift accessor is `Int32`. This converts
/// to a plain Swift `Int` to avoid Int/Int32 mismatches throughout.
extension KotlinInt {
    nonisolated var value: Int { Int(truncating: self) }
}
