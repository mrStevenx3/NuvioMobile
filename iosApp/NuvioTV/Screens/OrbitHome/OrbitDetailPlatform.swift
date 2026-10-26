import SharedCore
import SwiftUI

// The detail page opened from a platform (Steven, 2026-10-25: once every platform was done, the
// detail page takes a light touch of the one it was opened from). Orbit's page stays the same; only
// its touches change: the platform's logo in the top right corner, its "original" tag above the
// title, its Lecture button, its tint under the sections.

enum OrbitPlatformTheme: String, Hashable {
    case netflix, disney, prime, hbo, paramount, appletv

    /// The page's tint under the sections (where Orbit darkens the art to black).
    var tint: Color {
        switch self {
        case .netflix: return Color(red: 0.03, green: 0.03, blue: 0.03)
        case .disney: return Color(red: 0.03, green: 0.07, blue: 0.17)
        case .prime: return OrbitPrimeLayout.background
        case .hbo: return OrbitHBOLayout.background
        case .paramount: return OrbitParamountLayout.background
        case .appletv: return Color(red: 0.2, green: 0.23, blue: 0.27)
        }
    }

    /// The Lecture button, as each app draws it.
    var playFill: Color {
        switch self {
        case .prime: return OrbitPrimeLayout.blue
        case .paramount: return OrbitParamountLayout.blue
        default: return .white
        }
    }

    var playText: Color { playFill == .white ? .black : .white }

    /// Netflix and Paramount+: a rounded rectangle; the others a capsule.
    var playRadius: CGFloat? {
        switch self {
        case .netflix: return 8
        case .paramount: return 8
        default: return nil
        }
    }

    /// The folder's logo drawn in white in the corner (their own colour sinks in the dark page).
    var whiteLogo: Bool { self == .paramount || self == .appletv }
}

/// Whose original the title is, for the tag above its title.
enum OrbitDetailOwn: Hashable {
    case netflix, prime, hbo, hboMax, paramount
}

/// What a platform page hands the detail page it opens.
struct OrbitDetailPlatform: Hashable {
    let theme: OrbitPlatformTheme
    var own: OrbitDetailOwn? = nil
    var logoUrl: String? = nil
}

/// The platform's logo, small in the top right corner (where its page had it).
struct OrbitDetailPlatformMark: View {
    let platform: OrbitDetailPlatform

    var body: some View {
        Group {
            if platform.theme == .appletv {
                Image("AppleTVMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white)
                    .frame(height: 44)
            } else if platform.theme == .netflix {
                // Steven: just his N, larger, not the whole Netflix word.
                Image("NetflixN")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 76)
            } else if let url = platform.logoUrl, !url.isEmpty {
                CachedAsyncImage(string: url, contentMode: .fit,
                                 decodeSize: .points(width: 380, height: 140),
                                 loading: { Color.clear }, failure: { Color.clear })
                    .brightness(platform.theme.whiteLogo ? 1 : 0)
                    .frame(width: 190, height: 70, alignment: .trailing)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 40)
        .padding(.trailing, 72)
        .allowsHitTesting(false)
    }
}

/// "N SÉRIE", "prime", "HBO ORIGINAL", "Paramount+ ORIGINAL" above the title.
struct OrbitDetailOwnTag: View {
    let own: OrbitDetailOwn
    let series: Bool

    var body: some View {
        switch own {
        case .netflix:
            HStack(spacing: 8) {
                Image("NetflixN").resizable().scaledToFit().frame(height: 34)
                Text(series ? String(localized: "SÉRIE") : String(localized: "FILM"))
                    .font(.system(size: 24, weight: .bold))
                    .kerning(5)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        case .prime:
            Text("prime")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(OrbitPrimeLayout.blue)
        case .hbo, .hboMax:
            HStack(spacing: 10) {
                Text(own == .hbo ? "HBO" : "HBO max")
                    .font(.system(size: 30, weight: .black))
                Text(String(localized: "ORIGINAL"))
                    .font(.system(size: 21, weight: .semibold))
                    .kerning(7)
            }
            .foregroundStyle(Color.white)
        case .paramount:
            Image("ParamountOriginal")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white)
                .frame(height: 56)
        }
    }
}
