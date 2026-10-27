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

    /// Steven (2026-10-27, Home and the studios): a platform's badge only on its own programmes —
    /// a Netflix production, an Amazon Original… — not on a title it merely carries.
    static func original(_ meta: OrbitMeta?) -> OrbitPlatformBadgeKind? {
        guard let meta, !meta.producers.isEmpty else { return nil }
        let makers = meta.producers.map { $0.lowercased() }
        return allCases.first { kind in makers.contains { kind.isMaker($0) } }
    }

    /// The production company or network is this platform's own.
    private func isMaker(_ name: String) -> Bool {
        switch self {
        case .netflix: return name.contains("netflix")
        case .disney: return name.contains("disney+") || name == "disney plus"
        case .prime: return name.contains("amazon") || name.contains("prime video")
        case .hbo: return name.contains("hbo") || name == "max"
        case .paramount: return name.contains("paramount+") || name.contains("paramount plus")
        case .appletv: return name.contains("apple tv") || name.contains("apple studios") || name.contains("apple original")
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

/// The badge: each platform's mark in its colours, on a small dark pill. Steven (2026-10-25, after
/// trying logos and no pill): every badge back as it first was.
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
            netflixText
        case .disney:
            disneyText
        case .prime:
            primeText
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
            Text("Paramount+")
                .font(.system(size: size, weight: .semibold, design: .serif).italic())
                .foregroundStyle(Color(red: 0.35, green: 0.6, blue: 1.0))
        case .appletv:
            Image("AppleTVMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: size * 0.9)
                .foregroundStyle(Color.white)
        }
    }

    private var netflixText: some View {
        Text("NETFLIX")
            .font(.system(size: size, weight: .black).width(.condensed))
            .foregroundStyle(Color(red: 0.9, green: 0.04, blue: 0.08))
    }

    private var primeText: some View {
        // Steven: white, as Amazon's own mark now is (no longer blue).
        Text("prime video")
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(Color.white)
    }

    private var disneyText: some View {
        Text("Disney+")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
    }
}
