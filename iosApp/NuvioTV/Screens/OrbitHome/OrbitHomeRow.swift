import Combine
import SharedCore
import SwiftUI

// Orbit Home (Steven's fork): one row, drawn rather than scrolled. Every card sits at a computed x
// for its distance from the row's lead (`OrbitHomeLayout.cardX`), all moving together on one curve
// when the lead changes; the lead's landscape frame is drawn OVER the row, opaque, so the card
// entering it slides under it and the card leaving it comes out from under it, as in the
// reference. Only the cards near the lead exist (two before, six after).

/// One card of a row.
struct OrbitCard: Identifiable, Equatable {
    let id: String
    let preview: MetaPreview
    let poster: String?
    let landscape: String?
    /// Continue Watching: "S2:E4" (or the time left) in the frame's corner.
    var badge: String?
    /// Continue Watching: 0…1.
    var progress: Double?
    /// Continue Watching: the entry to resume.
    var entry: WatchProgressEntry?

    static func == (a: OrbitCard, b: OrbitCard) -> Bool {
        a.id == b.id && a.poster == b.poster && a.landscape == b.landscape && a.badge == b.badge
            && a.progress == b.progress
    }

    static func catalog(_ item: MetaPreview) -> OrbitCard {
        OrbitCard(id: "\(item.type):\(item.id)", preview: item, poster: item.poster,
                  landscape: InlineTrailerCard.landscapeArtworkURL(item))
    }

    static func continueWatching(_ entry: WatchProgressEntry) -> OrbitCard {
        let preview = StageCopy.preview(from: entry)
        let badge: String? = {
            if let s = entry.seasonNumber?.intValue, let e = entry.episodeNumber?.intValue { return "S\(s):E\(e)" }
            return StageCopy.remainingLabel(positionMs: entry.lastPositionMs, durationMs: entry.durationMs)
        }()
        let progress: Double? = entry.durationMs > 0
            ? min(1, max(0, Double(entry.lastPositionMs) / Double(entry.durationMs))) : nil
        let background: String? = entry.background
        let thumbnail: String? = entry.episodeThumbnail
        return OrbitCard(id: "cw:\(entry.videoId)", preview: preview, poster: entry.poster ?? preview.poster,
                         landscape: background ?? thumbnail ?? InlineTrailerCard.landscapeArtworkURL(preview),
                         badge: badge, progress: progress, entry: entry)
    }
}

/// One row of the page.
struct OrbitRow: Identifiable, Equatable {
    let id: String
    let title: String
    let cards: [OrbitCard]
    /// The catalog section (localization warm-up), nil for Continue Watching.
    var sectionKey: String?
    /// Steven (pass 3): the kind of tiles (the classic frame and posters, landscape, cards…).
    var style: OrbitRowStyle = .classic
    /// A looping row (its titles repeated): the title it starts on, in the middle copy.
    var loopStart: String? = nil

    /// Steven (2026-10-28: "les lignes doivent être en boucle et pas avoir de fin"): the row's
    /// titles repeated, the row starting in the middle — the system never reaches an end. Not the
    /// Top 10 (its ranks), Prochainement (its dates) nor Reprendre (his own list).
    func looped(copies: Int = 7) -> OrbitRow {
        guard style != .ranked, id != "continue-watching", !id.hasPrefix("orbit-soon"), cards.count >= 4 else { return self }
        var out: [OrbitCard] = []
        for k in 0..<copies {
            for card in cards {
                out.append(OrbitCard(id: "\(k)~\(card.id)", preview: card.preview, poster: card.poster,
                                     landscape: card.landscape, badge: card.badge, progress: card.progress,
                                     entry: card.entry))
            }
        }
        var row = OrbitRow(id: id, title: title, cards: out, sectionKey: sectionKey, style: style)
        row.loopStart = "\(copies / 2)~\(cards[0].id)"
        return row
    }
}

/// A poster in a row.
struct OrbitPosterCard: View {
    let card: OrbitCard

    var body: some View {
        let L = OrbitHomeLayout.self
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.12)
            OrbitImage(url: card.poster, fallback: card.landscape,
                       size: CGSize(width: L.posterWidth, height: L.cardHeight))
            if let progress = card.progress {
                OrbitProgressBar(progress: progress)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: L.posterWidth, height: L.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: L.posterRadius, style: .continuous))
    }
}

struct OrbitProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 5)
    }
}

/// The focused title's landscape frame: art, logo, badge, the trailer when it plays.
struct OrbitLeadFrame: View {
    let card: OrbitCard
    let meta: OrbitMeta?
    let focused: Bool
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void
    /// Another size than the first row's (the Top 10's open title keeps its poster's height).
    var frameSize: CGSize? = nil

    var body: some View {
        let L = OrbitHomeLayout.self
        let size = frameSize ?? CGSize(width: L.frameWidth, height: L.cardHeight)
        ZStack(alignment: .topLeading) {
            // Opaque at all times: the row slides under it.
            Color(white: 0.1)
            // The art persists across titles and swaps once the new image is ready.
            OrbitSwapImage(url: card.landscape ?? meta?.backdrop, fallback: card.poster, size: size)
            ZStack(alignment: .bottomLeading) {
                if let trailerURL {
                    TrailerHeroPlayer(urlString: trailerURL,
                                      onFailure: onTrailerFailure,
                                      zoomKey: TrailerResolutionCache.key(type: card.preview.type, id: card.preview.id),
                                      loops: false,
                                      onPlaybackEnded: onTrailerEnded,
                                      cornerRadius: L.frameRadius)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.4)))
                }
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                // The title's own marks change with it.
                ZStack(alignment: .bottomLeading) {
                    // (Steven: a little smaller in the Top 10's frame.)
                    OrbitTitleMark(name: card.preview.name, logo: OrbitInfo.make(card.preview, meta: meta).logo,
                                   maxSize: frameSize == nil ? CGSize(width: 350, height: 102) : CGSize(width: 370, height: 108),
                                   textSize: frameSize == nil ? 44 : 46)
                        .padding(.leading, 28)
                        .padding(.bottom, 24)
                    if let badge = card.badge {
                        Text(badge)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, 22)
                            .padding(.bottom, 26)
                    }
                    if let progress = card.progress {
                        OrbitProgressBar(progress: progress)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 10)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                .id(card.id)
                .transition(.opacity.animation(OrbitHomeLayout.crossfade))
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        // Where it can be watched (Steven: Orbit gathers the platforms), top right; nothing for a
        // title on none.
        .overlay(alignment: .topTrailing) {
            if let kind = OrbitPlatformBadgeKind.original(meta) {
                OrbitPlatformBadge(kind: kind, size: 20)
                    .padding(18)
                    .id(card.id)
                    .transition(.opacity.animation(OrbitHomeLayout.crossfade))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: L.frameRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.frameRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(focused ? 1 : 0.2), lineWidth: focused ? L.frameBorder : 1.5)
        }
    }
}

/// A title's logo, or its name when it has none.
struct OrbitTitleMark: View {
    let name: String
    let logo: String?
    let maxSize: CGSize
    let textSize: CGFloat
    /// Tried when `logo` does not load (Steven, 2026-10-25: titles with a logo showed their name).
    var fallbackLogo: String? = nil
    /// Tried after those two, in order.
    var moreLogos: [String] = []
    /// The mark takes the logo's own height (Steven: a wide logo left "N FILM" floating high above it).
    var hugsLogo = false

    @State private var aspect: CGFloat?
    /// Logos' shapes, by address, once measured.
    @MainActor static var aspects: [String: CGFloat] = [:]

    private var candidates: [String] {
        var seen = Set<String>()
        return ([logo, fallbackLogo].compactMap { $0 } + moreLogos)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        let list = candidates
        if let first = list.first {
            let image = CachedAsyncImage(string: first, fallback: list.count > 1 ? list[1] : nil, contentMode: .fit,
                                         decodeSize: .points(width: maxSize.width, height: maxSize.height),
                                         loading: { Color.clear }, failure: { rest(list) })
            if hugsLogo {
                // Fitted by hand: the logo's own width and height inside the box, nothing above it.
                // The shape already measured for this logo (a tile opened again, another page):
                // fitted from its first frame, never the full box first (Steven: the N tag floated).
                let known = aspect ?? Self.aspects[first]
                let fitted: CGSize = known.map { a in
                    let h = min(maxSize.height, maxSize.width / max(a, 0.01))
                    return CGSize(width: h * a, height: h)
                } ?? maxSize
                image
                    .onImageLoaded { loaded in
                        let a = loaded.size.width / max(loaded.size.height, 1)
                        Self.aspects[first] = a
                        if aspect != a { aspect = a }
                    }
                    .frame(width: fitted.width, height: fitted.height, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            } else {
                image
                    .frame(maxWidth: maxSize.width, maxHeight: maxSize.height, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            }
        } else {
            nameText
        }
    }

    /// The candidates after the first two, else the name.
    private func rest(_ list: [String]) -> AnyView {
        guard list.count > 2 else { return AnyView(nameText) }
        return AnyView(OrbitTitleMark(name: name, logo: list[2], maxSize: maxSize, textSize: textSize,
                                      moreLogos: Array(list.dropFirst(3))))
    }

    private var nameText: some View {
        Text(name)
            .font(.system(size: textSize, weight: .heavy))
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: maxSize.width, alignment: .leading)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }
}

/// An image with no shimmer while it loads and nothing on failure (the frames are opaque already).
struct OrbitImage: View {
    let url: String?
    var fallback: String? = nil
    var mode: ContentMode = .fill
    let size: CGSize
    /// Shown while `url` loads (the frame shows the poster, already loaded by the row, until its
    /// landscape art lands; it stayed an empty grey pane on a slow network).
    var placeholder: String? = nil
    /// Tried when `url` and `fallback` both fail (Steven: Buddy showed only its title in Discover).
    var lastResort: String? = nil

    var body: some View {
        // (Steven: grey panes between steps — an image with no address yet drew the grey surface;
        // its fallback stands in, or nothing.)
        let address = (url?.isEmpty == false ? url : nil) ?? fallback ?? lastResort
        if address == nil {
            Color.clear.frame(width: size.width, height: size.height)
        } else {
            image(address, fallback: address == url ? fallback : nil)
        }
    }

    private func image(_ url: String?, fallback: String?) -> some View {
        CachedAsyncImage(string: url, fallback: fallback, contentMode: mode,
                         decodeSize: .points(width: size.width, height: size.height),
                         loading: {
                             if let placeholder {
                                 CachedAsyncImage(string: placeholder, contentMode: .fill,
                                                  decodeSize: .points(width: OrbitHomeLayout.posterWidth,
                                                                      height: OrbitHomeLayout.cardHeight),
                                                  loading: { Color.clear }, failure: { Color.clear })
                                     .frame(width: size.width, height: size.height)
                                     .clipped()
                             } else {
                                 Color.clear
                             }
                         },
                         failure: {
                             if let lastResort {
                                 CachedAsyncImage(string: lastResort, contentMode: mode,
                                                  decodeSize: .points(width: size.width, height: size.height),
                                                  loading: { Color.clear }, failure: { Color.clear })
                                     .frame(width: size.width, height: size.height)
                                     .clipped()
                             } else {
                                 Color.clear
                             }
                         })
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

/// The frame's art. It never shows an empty pane: a new title's image is fetched first and cross-
/// fades in OVER the current one once it is ready (the poster stands in for a first image that is
/// not loaded yet). The frame's logo and text change at once; the art follows as soon as it can.
struct OrbitSwapImage: View {
    let url: String?
    let fallback: String?
    let size: CGSize
    /// A vertical shift belonging to this image (it cross-fades with it, never jumps on the old one).
    var shiftY: CGFloat = 0
    /// Shown (from memory only) while this image has nothing yet: Home's hero at launch, the art
    /// shown there last time (`OrbitLaunchArt`), the real one fading in over it.
    var standIn: String? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var shown: UIImage?
    @State private var shownShift: CGFloat = 0
    @State private var generation = 0
    /// The first image was already in memory: drawn at once, no fade (Steven: Netflix's open tile
    /// redrew itself at each step).
    @State private var instant = false

    /// What memory already holds for this frame (drawn in the very first frame, before `load`).
    private var seed: UIImage? {
        let frame = ArtworkDecodeRequest(size: .points(width: size.width, height: size.height), fill: true, scale: displayScale)
        let main = url.flatMap(URL.init(string:))
        if let best = main.flatMap({ ArtworkURLUpgrade.upgraded($0, role: .backdrop) }),
           let image = ArtworkStore.cached(best, decode: frame) { return image }
        if let main, let image = ArtworkStore.cached(main, decode: frame) { return image }
        if let backup = fallback.flatMap(URL.init(string:)) { return ArtworkStore.cachedLargest(backup) }
        return nil
    }

    /// The stand-in, if memory holds it at this frame's size.
    private var standInImage: UIImage? {
        guard let standIn, let main = URL(string: standIn) else { return nil }
        let frame = ArtworkDecodeRequest(size: .points(width: size.width, height: size.height), fill: true, scale: displayScale)
        if let best = ArtworkURLUpgrade.upgraded(main, role: .backdrop), let image = ArtworkStore.cached(best, decode: frame) {
            return image
        }
        return ArtworkStore.cached(main, decode: frame)
    }

    var body: some View {
        ZStack {
            if shown == nil, seed == nil, let standInImage {
                Image(uiImage: standInImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .zIndex(-1)
                    // (It stays until the real one has faded in over it.)
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .opacity.animation(.linear(duration: 0.01).delay(0.26))))
            }
            if shown == nil, let seed {
                Image(uiImage: seed)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .offset(y: shownShift)
                    .id(generation)
                    .zIndex(Double(generation))
                    .transition(instant ? .identity
                                : .asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.24)),
                                              removal: .opacity.animation(.linear(duration: 0.01).delay(0.26))))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(url ?? "-")|\(fallback ?? "-")") { await load() }
    }

    private func show(_ image: UIImage, instantly: Bool = false) {
        instant = instantly && shown == nil
        generation &+= 1
        shownShift = shiftY
        shown = image
    }

    private func load() async {
        let frame = ArtworkDecodeRequest(size: .points(width: size.width, height: size.height), fill: true, scale: displayScale)
        let poster = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.posterWidth, height: OrbitHomeLayout.cardHeight),
                                          fill: true, scale: displayScale)
        let main = url.flatMap(URL.init(string:))
        let backup = fallback.flatMap(URL.init(string:))
        // Steven (device: the best images): a full-screen art is TMDB's original, not its 1280 px
        // copy (soft on a 4K TV); the 1280 one if the original fails.
        let best = main.flatMap { ArtworkURLUpgrade.upgraded($0, role: .backdrop) }
        if let best, let image = ArtworkStore.cached(best, decode: frame) { show(image, instantly: true); return }
        if let main, let image = ArtworkStore.cached(main, decode: frame) { show(image, instantly: true) }
        else if shown == nil, let backup,
                let image = ArtworkStore.cached(backup, decode: poster) ?? ArtworkStore.cachedLargest(backup) {
            // (Any size of the poster already drawn: Netflix's tiles decode it at their own.)
            show(image, instantly: true)
        }
        for candidate in [best, main, backup].compactMap({ $0 }) {
            if let image = try? await ArtworkStore.fetch(candidate, decode: frame) {
                guard !Task.isCancelled else { return }
                show(image)
                return
            }
            if Task.isCancelled { return }
        }
    }
}
