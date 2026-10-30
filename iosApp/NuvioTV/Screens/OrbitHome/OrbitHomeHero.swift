import Combine
import CoreImage
import SharedCore
import SwiftUI

// Orbit Home (Steven, 2026-10-25, pass 2: the platforms' pages made it look plain): the hero full
// screen — the title's backdrop edge to edge (its trailer once the viewer rests on it), the platform
// it is on, the logo or the name, the meta line, three lines of synopsis, the "Voir la fiche" pill,
// the dots; the first row's heading peeks at the bottom. Left / Right go to the previous / next title.

struct OrbitHomeHeroView: View {
    let item: MetaPreview?
    let focused: Bool
    var count: Int = 0
    var index: Int = 0
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitHomeLayout.self
        let size = CGSize(width: L.heroWidth, height: L.heroHeight)
        ZStack(alignment: .topLeading) {
            L.background
            // Steven's video: changing titles went through black. The art stays and swaps once the
            // next one is ready (no fade through the page); only the details cross-fade.
            if let item {
                OrbitSwapImage(url: item.banner ?? metaStore.meta(for: item)?.backdrop, fallback: item.poster, size: size)
            }
            if let item, let trailerURL {
                TrailerHeroPlayer(urlString: trailerURL,
                                  onFailure: onTrailerFailure,
                                  zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                  loops: false,
                                  onPlaybackEnded: onTrailerEnded,
                                  cornerRadius: 0)
                    .frame(width: size.width, height: size.height)
                    .id("\(item.type):\(item.id)")
                    .transition(.opacity.animation(.easeOut(duration: 0.5)))
            }
            // Steven (device: the art flashed lighter, then darkened, on each change): the shades
            // stay put; only the title's details cross-fade.
            LinearGradient(stops: [
                // (Steven, 2026-10-30: the text has its own shadow now — the side shade a third lighter.)
                .init(color: L.background.opacity(0.6), location: 0),
                .init(color: L.background.opacity(0.3), location: 0.38),
                .init(color: .clear, location: 0.64),
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .clear, location: 0.16),
                .init(color: .clear, location: 0.6),
                .init(color: L.background, location: 0.97),
            ], startPoint: .top, endPoint: .bottom)
            if let item {
                let meta = metaStore.meta(for: item)
                let info = OrbitInfo.make(item, meta: meta)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let kind = OrbitPlatformBadgeKind.original(meta) {
                            OrbitPlatformBadge(kind: kind, size: 27)
                                .padding(.bottom, 24)
                        }
                        OrbitTitleMark(name: item.name, logo: info.logo,
                                       maxSize: CGSize(width: 640, height: 200), textSize: 70, hugsLogo: true)
                            .frame(width: 640, alignment: .leading)
                        // Steven (2026-10-30): the small lines read on any art — a soft shadow under the
                        // letters only (no veil over the image); drawn once into a picture, so the page's
                        // moves carry it without working it out again.
                        OrbitMetaLine(info: info, size: 28)
                            .modifier(OrbitHeroTextShade())
                            .padding(.top, 34)
                        Text(info.synopsis)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .lineSpacing(5)
                            .lineLimit(3)
                            .frame(width: 880, alignment: .leading)
                            .modifier(OrbitHeroTextShade())
                            .padding(.top, 22)
                        Text("Voir la fiche")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(focused ? Color.black : Color.white)
                            .padding(.horizontal, 44)
                            .frame(height: 76)
                            .background(Capsule().fill(focused ? Color.white : OrbitGlass.tint))
                            .scaleEffect(focused ? 1.05 : 1, anchor: .leading)
                            .animation(.easeOut(duration: 0.16), value: focused)
                            .padding(.top, 30)
                    }
                    .frame(width: 900, height: L.heroInfoBottom, alignment: .bottomLeading)
                    .offset(x: L.margin)
                }
                .id("\(item.type):\(item.id)")
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }

            if count > 1 {
                HStack(spacing: 10) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 1 : 0.35))
                            .frame(width: i == index ? 24 : 8, height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: index)
                .frame(width: size.width)
                .offset(y: L.heroInfoBottom + 8)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}

// MARK: - Genres

/// One genre chip: TMDB's genre id for the page's type.
nonisolated struct OrbitGenre: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let tv: Bool

    static let movies: [OrbitGenre] = [
        (28, "Action"), (18, "Drame"), (35, "Comédie"), (53, "Thriller"), (14, "Fantastique"),
        (10749, "Romance"), (10751, "Famille"), (16, "Animation"), (27, "Horreur"), (878, "Science-Fiction"),
        (12, "Aventure"), (80, "Crime"), (9648, "Mystère"), (99, "Documentaire"), (36, "Histoire"),
        (10752, "Guerre"), (10402, "Musique"), (37, "Western"),
    ].map { OrbitGenre(id: $0.0, name: $0.1, tv: false) }

    static let series: [OrbitGenre] = [
        (10759, "Action & Aventure"), (18, "Drame"), (35, "Comédie"), (80, "Crime"),
        (10765, "Science-Fiction & Fantastique"), (9648, "Mystère"), (16, "Animation"), (10751, "Famille"),
        (99, "Documentaire"), (10764, "Télé-réalité"), (10762, "Enfants"), (10768, "Guerre & Politique"),
        (37, "Western"),
    ].map { OrbitGenre(id: $0.0, name: $0.1, tv: true) }
}

// MARK: - Pre-blurred art

/// Fluidity (Steven, 2026-10-25, before the IPA): a blurred copy of an art, blurred ONCE on a
/// small copy off the main thread and drawn scaled up — instead of a live full-screen `.blur`,
/// which the Apple TV recomputes on every frame anything above it moves. `radius` is in screen
/// points (as `.blur`'s).
struct OrbitPreBlurred: View {
    let url: String?
    let radius: CGFloat

    @State private var image: UIImage?
    @State private var shown: String?

    /// The small copy's width: blurring it at radius / scale gives the same look full screen.
    private static let width: CGFloat = 480

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(shown ?? "-")
                    .transition(.opacity)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .clipped()
        .animation(.easeInOut(duration: 0.35), value: shown)
        .task(id: "\(url ?? "-")|\(radius)") {
            guard let url, let address = URL(string: url) else { image = nil; shown = nil; return }
            guard let small = try? await ArtworkStore.fetch(address, decode: .init(size: .pixels(Int(Self.width)), fill: true, scale: 1)),
                  let cg = small.cgImage else { return }
            let pixels = radius * Self.width / OrbitHomeLayout.screenWidth
            let blurred = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                OrbitPreBlurred.blur(cg, radius: pixels)
            }.value
            guard !Task.isCancelled, let blurred else { return }
            image = blurred
            shown = url
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    nonisolated static func blur(_ cg: CGImage, radius: CGFloat) -> UIImage? {
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let rendered = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: rendered)
    }
}


/// A soft shadow under small text over an image (the hero's synopsis and its line of details): a
/// close dark edge and a wider soft one, baked into one picture with the text.
struct OrbitHeroTextShade: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.55), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
            .padding(14)
            .drawingGroup()
            .padding(-14)
    }
}
