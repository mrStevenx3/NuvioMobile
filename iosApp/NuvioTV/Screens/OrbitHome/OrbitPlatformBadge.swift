import SharedCore
import SwiftUI

// Orbit Home (Steven, 2026-10-25): where a title can be watched — what makes Orbit Orbit. A small
// badge in each platform's own style, from TMDB's subscription platforms in France
// (`OrbitMeta.platforms`). A title on none (his own sources) has no badge and shows as before.

nonisolated enum OrbitPlatformBadgeKind: CaseIterable {
    case netflix, disney, prime, hbo, paramount, appletv

    /// TMDB's watch-provider ids (with their ads tiers and channels).
    var providerIds: Set<Int> {
        switch self {
        case .netflix: return [8, 1796]
        case .disney: return [337]
        case .prime: return [119, 2100]
        case .hbo: return [1899, 384]
        case .paramount: return [531, 582, 2303]
        case .appletv: return [350, 2243]
        }
    }

    var name: String {
        switch self {
        case .netflix: return "Netflix"
        case .disney: return "Disney+"
        case .prime: return "Prime Video"
        case .hbo: return "HBO Max"
        case .paramount: return "Paramount+"
        case .appletv: return "Apple TV"
        }
    }

    /// The platform shown for a title: among those it is on in France, its own network's first
    /// (Steven: Love & Death, an HBO series also on Netflix, showed NETFLIX), else TMDB's first.
    /// Nil when it is on none.
    static func of(_ meta: OrbitMeta?) -> OrbitPlatformBadgeKind? {
        guard let meta, !meta.platforms.isEmpty else { return nil }
        var available: [OrbitPlatformBadgeKind] = []
        for id in meta.platforms {
            if let kind = allCases.first(where: { $0.providerIds.contains(id) }), !available.contains(kind) {
                available.append(kind)
            }
        }
        if available.count > 1 {
            let makers = meta.producers.map { $0.lowercased() }
            if let own = available.first(where: { kind in makers.contains { kind.isMaker($0) } }) { return own }
        }
        return available.first
    }

    /// The production company or network is this platform's own.
    private func isMaker(_ name: String) -> Bool {
        switch self {
        case .netflix: return name.contains("netflix")
        case .disney: return name.contains("disney+") || name == "disney plus"
        case .prime: return name.contains("amazon") || name.contains("prime video")
        case .hbo: return name.contains("hbo") || name == "max"
        case .paramount: return name.contains("paramount+") || name.contains("paramount plus")
        case .appletv: return name.contains("apple tv")
        }
    }
}

/// The platforms' logos from Steven's collection (its folders' title logos), for the badges that
/// have no mark of their own in the app (Disney+: Steven, "reprends notre logo").
@MainActor
enum OrbitPlatformLogos {
    private(set) static var urls: [OrbitPlatformBadgeKind: String] = [:]

    static func update() {
        guard let collections = CollectionRepository.shared.collections.value_ as? [NuvioCollection] else { return }
        var found: [OrbitPlatformBadgeKind: String] = [:]
        for folder in collections.flatMap(\.folders) {
            let title = folder.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .replacingOccurrences(of: " ", with: "")
            guard let logo = folder.titleLogoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !logo.isEmpty else { continue }
            if title.contains("disney"), found[.disney] == nil { found[.disney] = logo }
        }
        urls = found
    }

    /// The logo for a platform (looked up again while none is known: the collection loads late).
    static func url(_ kind: OrbitPlatformBadgeKind) -> String? {
        if urls.isEmpty { update() }
        return urls[kind]
    }
}

/// The badge: each platform's mark in its colours, on a small dark pill.
struct OrbitPlatformBadge: View {
    let kind: OrbitPlatformBadgeKind
    var size: CGFloat = 20

    var body: some View {
        content
            .padding(.horizontal, size * 0.55)
            .frame(height: size * 1.6)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .netflix:
            Text("NETFLIX")
                .font(.system(size: size, weight: .black).width(.condensed))
                .foregroundStyle(Color(red: 0.9, green: 0.04, blue: 0.08))
        case .disney:
            if let logo = OrbitPlatformLogos.url(.disney) {
                CachedAsyncImage(string: logo, contentMode: .fit,
                                 decodeSize: .points(width: size * 8, height: size * 3),
                                 loading: { Color.clear }, failure: { disneyText })
                    // Steven: it looked small next to NETFLIX or HBO max.
                    .frame(width: size * 4.6, height: size * 1.5)
            } else {
                disneyText
            }
        case .prime:
            Text("prime video")
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(OrbitPrimeLayout.blue)
        case .hbo:
            HStack(spacing: size * 0.25) {
                Image("HBOMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: size * 0.82)
                Text("max").font(.system(size: size, weight: .bold))
            }
            .foregroundStyle(Color.white)
        case .paramount:
            // The official "Paramount+" script (Steven's logo, its ORIGINAL line left out), in its blue.
            Image("ParamountMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: size * 1.2)
                .foregroundStyle(Color(red: 0.2, green: 0.5, blue: 1.0))
        case .appletv:
            Image("AppleTVMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: size * 0.9)
                .foregroundStyle(Color.white)
        }
    }

    private var disneyText: some View {
        Text("Disney+")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
    }
}
