import Combine
import CoreImage
import SharedCore
import SwiftUI

// Orbit Home (Steven, 2026-10-25, pass 2: the platforms' pages made it look plain): the hero full
// screen — the title's backdrop edge to edge (its trailer once the viewer rests on it), the platform
// it is on, the logo or the name, the meta line, three lines of synopsis, the "Voir la fiche" pill,
// the dots; the first row's heading peeks at the bottom. Left / Right go to the previous / next title.

/// Steven (2026-10-31: at launch Home's art stayed black 2–3 s — its catalogues load first): the
/// art of Home's first title, kept from one launch to the next, shown at once while they load.
enum OrbitLaunchArt {
    private static let key = "orbit.home.launchArt"
    /// Read once per launch (what last time left).
    static let url: String? = {
        let value = UserDefaults.standard.string(forKey: key)
        return (value ?? "").isEmpty ? nil : value
    }()

    static func remember(_ art: String?) {
        guard let art, !art.isEmpty, UserDefaults.standard.string(forKey: key) != art else { return }
        UserDefaults.standard.set(art, forKey: key)
    }
}

/// Home at launch, until its titles are there: last time's art under the hero's own shades.
struct OrbitHomeLaunchArt: View {
    let url: String

    var body: some View {
        let L = OrbitHomeLayout.self
        let size = CGSize(width: L.heroWidth, height: L.heroHeight)
        ZStack(alignment: .topLeading) {
            L.background
            OrbitSwapImage(url: url, fallback: nil, size: size)
            // (The hero's shades, as `OrbitHomeHeroView` draws them.)
            LinearGradient(stops: [
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
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        // (Home without titles at all — offline, no hero: it does not stay behind the rows.)
        .opacity(expired ? 0 : 1)
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { expired = true }
        }
    }

    @State private var expired = false
}

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
                // (The first page, at launch: last time's art stands in until its own is there.)
                OrbitSwapImage(url: item.banner ?? metaStore.meta(for: item)?.backdrop, fallback: item.poster, size: size,
                               standIn: index == 0 ? OrbitLaunchArt.url : nil)
                    .onChange(of: item.banner ?? metaStore.meta(for: item)?.backdrop, initial: true) { _, art in
                        if index == 0 { OrbitLaunchArt.remember(art) }
                    }
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
                            .overlay(Capsule().strokeBorder(OrbitGlass.rim.opacity(focused ? 0 : 1), lineWidth: 1.5))
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
                // (Steven, 2026-10-30: lower, with the hero full screen again.)
                .offset(y: L.heroDotsY)
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
    /// A vertical shift belonging to each picture (kept by it as it fades out: never moved after).
    var shiftY: CGFloat = 0
    /// Changing on the sharp picture's own curve (`OrbitSwapImage`: the new one over the old one,
    /// which goes once it is covered) — the Studios banner's blurred copy under it.
    var withSharp = false

    @State private var image: UIImage?
    @State private var shown: String?
    @State private var shownShift: CGFloat = 0
    @State private var generation = 0

    /// The small copy's width: blurring it at radius / scale gives the same look full screen.
    private static let width: CGFloat = 480

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .offset(y: shownShift)
                    .id(withSharp ? "\(generation)" : (shown ?? "-"))
                    .zIndex(withSharp ? Double(generation) : 0)
                    .transition(withSharp
                                ? .asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.24)),
                                              removal: .opacity.animation(.easeOut(duration: 0.15).delay(0.24)))
                                : .opacity)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .clipped()
        .animation(withSharp ? nil : .easeInOut(duration: 0.35), value: shown)
        .task(id: "\(url ?? "-")|\(radius)") {
            guard let url else { image = nil; shown = nil; return }
            // (Blurred before — a studio's banner prepared ahead: at once.)
            if let ready = Self.made.object(forKey: "\(url)|\(radius)" as NSString) {
                put(ready, url)
                return
            }
            guard let blurred = await Self.prepare(url, radius: radius), !Task.isCancelled else { return }
            put(blurred, url)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func put(_ picture: UIImage, _ url: String) {
        generation &+= 1
        shownShift = shiftY
        image = picture
        shown = url
    }

    /// The blurred copies made (by url and radius).
    nonisolated(unsafe) static let made: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        return cache
    }()
    /// One Core Image context for every blur (making one costs more than the blur).
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The blurred copy of `url` at `radius`, made once and kept.
    @discardableResult
    static func prepare(_ url: String, radius: CGFloat) async -> UIImage? {
        let key = "\(url)|\(radius)" as NSString
        if let ready = made.object(forKey: key) { return ready }
        guard let address = URL(string: url),
              let small = try? await ArtworkStore.fetch(address, decode: .init(size: .pixels(Int(width)), fill: true, scale: 1)),
              let cg = small.cgImage else { return nil }
        let pixels = radius * width / OrbitHomeLayout.screenWidth
        let blurred = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            OrbitPreBlurred.blur(cg, radius: pixels)
        }.value
        if let blurred { made.setObject(blurred, forKey: key) }
        return blurred
    }

    nonisolated static func blur(_ cg: CGImage, radius: CGFloat) -> UIImage? {
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let rendered = context.createCGImage(output, from: input.extent)
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
