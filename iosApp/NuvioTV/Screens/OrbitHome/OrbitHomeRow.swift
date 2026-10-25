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
}

struct OrbitHomeRowView: View {
    let row: OrbitRow
    let lead: Int
    /// The row is the page's current section (its text shows).
    let isCurrent: Bool
    /// The page holds focus on this row (the frame's white border).
    let focused: Bool
    /// The trailer playing in the frame, if it is this row's lead.
    let trailerURL: String?
    let onTrailerFailure: (TrailerFailureReport) -> Void
    let onTrailerEnded: () -> Void

    @ObservedObject private var metaStore = OrbitMetaStore.shared

    var body: some View {
        let L = OrbitHomeLayout.self
        let window = max(0, lead - 2)...max(max(0, lead - 2), min(row.cards.count - 1, lead + 6))
        ZStack(alignment: .topLeading) {
            Text(row.title)
                .font(.system(size: L.headingFont, weight: .bold))
                // The whole title dimmed (not its colour): an emoji in a catalogue's name dims
                // with the text instead of staying bright.
                .foregroundStyle(Color.white)
                .opacity(isCurrent ? 1 : 0.55)
                .lineLimit(1)
                .frame(height: 40, alignment: .center)
                .offset(x: L.margin + 4, y: -20)

            // The posters.
            ZStack(alignment: .topLeading) {
                if !row.cards.isEmpty {
                    ForEach(Array(zip(window, row.cards[window])), id: \.1.id) { index, card in
                        OrbitPosterCard(card: card)
                            .offset(x: L.cardX(index - lead))
                            .transition(.identity)
                    }
                }
            }
            .offset(y: L.cardsTop)

            // The frame, over them.
            if row.cards.indices.contains(lead) {
                OrbitLeadFrame(card: row.cards[lead], meta: metaStore.meta(for: row.cards[lead].preview),
                               focused: focused, trailerURL: trailerURL,
                               onTrailerFailure: onTrailerFailure, onTrailerEnded: onTrailerEnded)
                    .offset(x: L.margin, y: L.cardsTop)

                // Always there, shown only on the current row: a text block created mid-move was
                // laid out at its final place at once and floated over the posters while the row
                // was still gliding (Steven's video). Only the title change cross-fades.
                let card = row.cards[lead]
                let info = OrbitInfo.make(card.preview, meta: metaStore.meta(for: card.preview))
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 16) {
                        OrbitMetaLine(info: info)
                            .frame(height: 36)
                        Text(info.synopsis)
                            .font(.system(size: L.synopsisFont, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineSpacing(L.synopsisLineSpacing)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(width: L.synopsisWidth, alignment: .topLeading)
                    }
                    .frame(width: L.synopsisWidth, alignment: .topLeading)
                    .id(card.id)
                    .transition(.opacity.animation(L.crossfade))
                }
                .opacity(isCurrent ? 1 : 0)
                .offset(x: L.margin + 12, y: L.metaCentre - 18)
            }
        }
        .frame(width: L.screenWidth, height: L.rowPitch, alignment: .topLeading)
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

    var body: some View {
        let L = OrbitHomeLayout.self
        let size = CGSize(width: L.frameWidth, height: L.cardHeight)
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
                    OrbitTitleMark(name: card.preview.name, logo: OrbitInfo.make(card.preview, meta: meta).logo,
                                   maxSize: CGSize(width: 440, height: 130), textSize: 54)
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
            if let kind = OrbitPlatformBadgeKind.of(meta) {
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
                let fitted: CGSize = aspect.map { a in
                    let h = min(maxSize.height, maxSize.width / max(a, 0.01))
                    return CGSize(width: h * a, height: h)
                } ?? maxSize
                image
                    .onImageLoaded { loaded in
                        let a = loaded.size.width / max(loaded.size.height, 1)
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

    var body: some View {
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
                         failure: { Color.clear })
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

    @Environment(\.displayScale) private var displayScale
    @State private var shown: UIImage?
    @State private var generation = 0

    var body: some View {
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .id(generation)
                    .zIndex(Double(generation))
                    .transition(.asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.24)),
                                            removal: .opacity.animation(.linear(duration: 0.01).delay(0.26))))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(url ?? "-")|\(fallback ?? "-")") { await load() }
    }

    private func show(_ image: UIImage) {
        generation &+= 1
        shown = image
    }

    private func load() async {
        let frame = ArtworkDecodeRequest(size: .points(width: size.width, height: size.height), fill: true, scale: displayScale)
        let poster = ArtworkDecodeRequest(size: .points(width: OrbitHomeLayout.posterWidth, height: OrbitHomeLayout.cardHeight),
                                          fill: true, scale: displayScale)
        let main = url.flatMap(URL.init(string:))
        let backup = fallback.flatMap(URL.init(string:))
        if let main, let image = ArtworkStore.cached(main, decode: frame) { show(image); return }
        if shown == nil, let backup, let image = ArtworkStore.cached(backup, decode: poster) { show(image) }
        for candidate in [main, backup].compactMap({ $0 }) {
            if let image = try? await ArtworkStore.fetch(candidate, decode: frame) {
                guard !Task.isCancelled else { return }
                show(image)
                return
            }
            if Task.isCancelled { return }
        }
    }
}
