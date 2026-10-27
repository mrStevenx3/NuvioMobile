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
                    .frame(height: OrbitPlatformIntro.cornerHeight, alignment: .top)
            } else if platform.theme == .netflix {
                // Steven: just his N, larger, not the whole Netflix word.
                Image("NetflixN")
                    .resizable()
                    .scaledToFit()
                    .frame(height: OrbitPlatformIntro.cornerHeight)
            } else if let url = platform.logoUrl, !url.isEmpty {
                CachedAsyncImage(string: url, contentMode: .fit,
                                 decodeSize: .points(width: 380, height: 140),
                                 loading: { Color.clear }, failure: { Color.clear })
                    .brightness(platform.theme.whiteLogo ? 1 : 0)
                    .frame(width: 190, height: OrbitPlatformIntro.cornerHeight, alignment: .topTrailing)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        // The same corner as the platform's page (Steven: on the TV's diagonal).
        .padding(.top, OrbitPlatformIntro.cornerInset)
        .padding(.trailing, OrbitPlatformIntro.cornerInset)
        .allowsHitTesting(false)
    }
}

/// "N SÉRIE", "prime", "HBO ORIGINAL", "Paramount+ ORIGINAL" above the title.
struct OrbitDetailOwnTag: View {
    let own: OrbitDetailOwn
    let series: Bool
    /// The title's drawn width (Steven: the tag fits its title — a wide logo, a larger tag; a short
    /// one, a smaller tag). 480 is the size the tag was drawn for.
    var titleWidth: CGFloat = 480

    private var k: CGFloat { min(1.3, max(0.7, titleWidth / 480)) }

    var body: some View {
        tag.animation(.easeOut(duration: 0.2), value: k)
    }

    @ViewBuilder
    private var tag: some View {
        let k = k
        switch own {
        case .netflix:
            HStack(spacing: 8) {
                Image("NetflixN").resizable().scaledToFit().frame(height: 34 * k)
                Text(series ? String(localized: "SÉRIE") : String(localized: "FILM"))
                    .font(.system(size: 24 * k, weight: .bold))
                    .kerning(5 * k)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        case .prime:
            // Steven: the Prime Video page's own mark — "prime" with Amazon's smile under it.
            OrbitPrimeMark(size: 34 * k)
        case .hbo, .hboMax:
            HStack(spacing: 10) {
                Text(own == .hbo ? "HBO" : "HBO max")
                    .font(.system(size: 30 * k, weight: .black))
                Text(String(localized: "ORIGINAL"))
                    .font(.system(size: 21 * k, weight: .semibold))
                    .kerning(7 * k)
            }
            .foregroundStyle(Color.white)
        case .paramount:
            Image("ParamountOriginal")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white)
                .frame(height: 56 * k)
        }
    }
}
