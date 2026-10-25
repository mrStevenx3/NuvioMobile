import Combine
import SwiftUI
import UIKit
import SharedCore

nonisolated enum FocusLeadsRow {
    static let defaultsKey = "home_focus_leads_row"
    /// The gap between Home's catalog cards while this mode is on (Classic rows use 28).
    /// Steven's fork (device pass, wako): tighter, 10 (was 14).
    /// Device pass (Steven: closer, like wako): 6 (was 10, then 14).
    static let cardGap: CGFloat = 6
    /// Escape hatch, read once: `defaults write … debug.focusLeadsEngineScroll -bool YES` gives the
    /// focus engine its own row scroll back (the pre-device-pass-2 behaviour).
    static let engineScrolls = UserDefaults.standard.bool(forKey: "debug.focusLeadsEngineScroll")
    /// The glide that brings the focused card to the leading edge. Short enough to keep up with a
    /// held Right, long enough to read as the row sliding under a fixed selection.
    static let animation = Animation.easeOut(duration: 0.32)

    /// Raw `ScrollPosition.scrollTo(x:)` offset that puts card `index` on the viewport's leading
    /// edge (uniform resting widths before it), clamped to the row's scrollable range. Nil when the
    /// row already rests there.
    static func offset(index: Int, cardWidth: CGFloat, gap: CGFloat, sample: RowHScrollSample) -> CGFloat? {
        guard index >= 0, cardWidth > 0, sample.viewportWidth > 0 else { return nil }
        let leading = CGFloat(index) * (cardWidth + gap)
        let maxOffset = max(0, sample.paddedContentWidth - sample.viewportWidth)
        let target = min(max(leading, 0), maxOffset)
        guard abs(target - sample.paddedVisibleMinX) > 0.5 else { return nil }
        return target - sample.insetLeading
    }

    /// Empty room after a row's last card, so the LAST card can still reach the leading edge
    /// (otherwise the row stops scrolling once its end is on screen). The screen width less the
    /// widest the card can get is always enough; any surplus is just blank space at the row's end.
    @MainActor static func trailingRoom(expandedCardWidth: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, UIScreen.main.bounds.width - expandedCardWidth - gap)
    }
}

/// Swift-side navigation value. Kotlin data classes don't conform to Swift `Hashable`, so we wrap the
/// `MetaPreview` and hash on its stable identity (type + id) while still carrying all its fields for
/// the destination's initial render. Shared by Home, Search, and detail "more like this".
struct TitleRoute: Hashable {
    let preview: MetaPreview
    /// Steven (Apple TV): the detail page opens by growing out of its poster (tvOS's zoom), only
    /// from the Apple TV page — not part of the route's identity.
    var zoom: Bool = false
    /// The platform page it was opened from (its light touch on the detail page) — not part of the
    /// route's identity either.
    var platform: OrbitDetailPlatform? = nil

    /// The poster's id for the zoom.
    var zoomID: String { "\(preview.type):\(preview.id)" }

    static func == (lhs: TitleRoute, rhs: TitleRoute) -> Bool {
        lhs.preview.id == rhs.preview.id && lhs.preview.type == rhs.preview.type
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(preview.id)
        hasher.combine(preview.type)
    }
}

/// Navigation value for the full-grid "See All" screen. `CatalogTarget` is a Kotlin sealed interface
/// and can't be a `NavigationStack` value directly, so we wrap it — hashing on the section's stable
/// `key` while carrying the title + target for the destination (same approach as `TitleRoute`).
struct CatalogRoute: Hashable {
    let key: String
    let title: String
    let target: any CatalogTarget

    init(section: HomeCatalogSection) {
        self.key = section.key
        self.title = section.title
        self.target = section.target
    }

    static func == (lhs: CatalogRoute, rhs: CatalogRoute) -> Bool { lhs.key == rhs.key }

    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// Navigation value for a cast/crew member's detail page (TMDB person id + name for the initial
/// render). Only produced when a `MetaPerson` has a `tmdbId`. Hashes on the id.
struct PersonRoute: Hashable {
    let id: Int
    let name: String

    static func == (lhs: PersonRoute, rhs: PersonRoute) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Navigation value for a studio/network browse page (TMDB discover-by-company/network). Only
/// produced when a `MetaCompany` has a `tmdbId`. `isNetwork` picks the TMDB entity kind (networks
/// come from `meta.networks`, studios from `meta.productionCompanies`); `sourceType` is the origin
/// title's type ("movie"/"series"), which orders the rails. Hashes on kind + id.
struct EntityRoute: Hashable {
    let id: Int
    let name: String
    let isNetwork: Bool
    let sourceType: String

    static func == (lhs: EntityRoute, rhs: EntityRoute) -> Bool {
        lhs.id == rhs.id && lhs.isNetwork == rhs.isNetwork
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isNetwork)
    }
}

/// A single poster tile, now backed by the shared `PosterCard` design-system component
/// (cached artwork, shimmer, brand focus ring, focus-aware title).
struct PosterCardView: View {
    let item: MetaPreview
    /// See `PosterCard.footnote`.
    var footnote: String? = nil
    /// FEAT-64: see `PosterCard.watchBadge` (catalog rows pass it through `InlineTrailerCard`).
    var watchBadge: PosterWatchBadge? = nil

    var body: some View {
        PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.rawPosterUrl,
                   watchBadge: watchBadge, footnote: footnote)
    }
}

