import Combine
import CoreImage
import SharedCore
import SwiftUI

// Orbit Home (Steven's fork): the hero — a wide rounded card under the bar with the title's
// backdrop (its trailer once the viewer rests on it), the logo or the name, the meta line, three
// lines of synopsis and a "Voir la fiche" pill; Left / Right go to the previous / next title.
// Behind it, the page takes the title's colours (`OrbitAmbient`).

struct OrbitHomeHeroView: View {
    let item: MetaPreview?
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.08)
            if let item {
                let meta = metaStore.meta(for: item)
                let info = OrbitInfo.make(item, meta: meta)
                ZStack(alignment: .bottomLeading) {
                    OrbitImage(url: item.banner ?? meta?.backdrop, fallback: item.poster,
                               size: CGSize(width: L.heroWidth, height: L.heroHeight))
                    if let trailerURL {
                        TrailerHeroPlayer(urlString: trailerURL,
                                          onFailure: onTrailerFailure,
                                          zoomKey: TrailerResolutionCache.key(type: item.type, id: item.id),
                                          loops: false,
                                          onPlaybackEnded: onTrailerEnded,
                                          cornerRadius: L.heroRadius)
                            .frame(width: L.heroWidth, height: L.heroHeight)
                            .transition(.opacity)
                    }
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.42),
                        .init(color: .clear, location: 0.68),
                    ], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        OrbitTitleMark(name: item.name, logo: info.logo,
                                       maxSize: CGSize(width: 620, height: 190), textSize: 66)
                        OrbitMetaLine(info: info, size: 30)
                            .padding(.top, 48)
                        Text(info.synopsis)
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .lineSpacing(5)
                            .lineLimit(3)
                            .frame(width: 940, alignment: .leading)
                            .padding(.top, 40)
                        Text("Voir la fiche")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(focused ? Color.black : Color.white)
                            .padding(.horizontal, 46)
                            .frame(height: 82)
                            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.22)))
                            .scaleEffect(focused ? 1.04 : 1, anchor: .leading)
                            .padding(.top, 28)
                    }
                    .padding(.leading, 88)
                    .padding(.bottom, 44)
                }
                .animation(.easeOut(duration: 0.5), value: trailerURL)
                .id("\(item.type):\(item.id)")
                .transition(.asymmetric(insertion: .opacity,
                                        removal: .opacity.animation(.linear(duration: 0.01).delay(0.35))))
            }
        }
        .frame(width: L.heroWidth, height: L.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: L.heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.heroRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 0.85 : 0.25), lineWidth: focused ? 3 : 1.5)
        }
        .animation(.easeInOut(duration: 0.35), value: item.map { "\($0.type):\($0.id)" } ?? "-")
        .animation(.easeOut(duration: 0.2), value: focused)
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

struct OrbitGenresView: View {
    let genres: [OrbitGenre]
    let lead: Int
    let focused: Bool

    var body: some View {
        let L = OrbitHomeLayout.self
        let window = max(0, lead - 1)...max(max(0, lead - 1), min(genres.count - 1, lead + 7))
        ZStack(alignment: .topLeading) {
            if !genres.isEmpty {
                ForEach(Array(zip(window, genres[window])), id: \.1.id) { index, genre in
                    OrbitGenreChip(name: genre.name, focused: focused && index == lead)
                        .offset(x: L.chipX(index - lead))
                        .transition(.identity)
                }
            }
        }
        .animation(L.horizontal, value: lead)
        .frame(width: L.screenWidth, height: L.chipHeight + 20, alignment: .topLeading)
    }
}

struct OrbitGenreChip: View {
    let name: String
    let focused: Bool

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(white: 0.42), Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
            Text(name)
                .font(.system(size: 27, weight: .heavy).width(.condensed))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.leading, 22)
                .padding(.trailing, 14)
                .padding(.bottom, 20)
        }
        .frame(width: L.chipWidth, height: L.chipHeight)
        .clipShape(RoundedRectangle(cornerRadius: L.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.chipRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0.22), lineWidth: focused ? 4 : 1.5)
        }
        .scaleEffect(focused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

// MARK: - Ambient

/// The page behind the hero: the hero title's backdrop, tiny and blurred once, darkened; black
/// below the hero (the rows' page). Never blurred per frame.
struct OrbitAmbient: View {
    let url: String?
    let visible: Bool
    @State private var image: UIImage?
    @State private var shown: String?

    var body: some View {
        ZStack {
            OrbitHomeLayout.background
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(visible ? 0.75 : 0)
                    .id(shown ?? "-")
                    .transition(.opacity)
                Color.black.opacity(0.35)
                    .opacity(visible ? 1 : 0)
            }
        }
        .frame(width: OrbitHomeLayout.screenWidth, height: OrbitHomeLayout.screenHeight)
        .clipped()
        .animation(.easeInOut(duration: 0.5), value: shown)
        .animation(OrbitHomeLayout.vertical, value: visible)
        .task(id: url ?? "-") {
            guard let url, let address = URL(string: url) else { return }
            guard let full = try? await ArtworkStore.fetch(address, decode: .init(size: .pixels(320), fill: true, scale: 1)),
                  let cg = full.cgImage else { return }
            let blurred = await Task.detached(priority: .utility) { () -> UIImage? in
                OrbitAmbient.blur(cg)
            }.value
            guard !Task.isCancelled, let blurred else { return }
            image = blurred
            shown = url
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    nonisolated static func blur(_ cg: CGImage) -> UIImage? {
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(18, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let rendered = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: rendered)
    }
}
