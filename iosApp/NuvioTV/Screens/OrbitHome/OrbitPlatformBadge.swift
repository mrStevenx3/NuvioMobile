import SharedCore
import SwiftUI

// Orbit Home (Steven, 2026-10-25): where a title can be watched — what makes Orbit Orbit. A small
// badge in each platform's own style, from TMDB's subscription platforms in France
// (`OrbitMeta.platforms`). A title on none (his own sources) has no badge and shows as before.

enum OrbitPlatformBadgeKind: CaseIterable {
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

    /// The first platform the title is on (in TMDB's order), nil when on none.
    static func of(_ meta: OrbitMeta?) -> OrbitPlatformBadgeKind? {
        guard let ids = meta?.platforms, !ids.isEmpty else { return nil }
        for id in ids {
            if let kind = allCases.first(where: { $0.providerIds.contains(id) }) { return kind }
        }
        return nil
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
            Text("Disney+")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
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
}
