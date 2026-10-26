import SharedCore
import SwiftUI

// Orbit mobile title page (v1): the backdrop, the logo, the meta line, the synopsis, Lire / Ma liste
// / Vu, the episodes of a series and the cast. Data and actions are `DetailViewModel`'s and playback
// is the TV's own source picker (`StreamPickerView`), presented exactly as `OrbitDetailView` does.

struct OrbitMobileDetail: View {
    let preview: MetaPreview

    @StateObject private var model: DetailViewModel
    @ObservedObject private var metaStore = OrbitMetaStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showStreams = false
    @State private var seriesPlay: OrbitSeriesPlayRoute?
    @State private var postPlayPending: MetaPreview?
    @State private var postPlayRoute: TitleRoute?
    @State private var synopsisOpen = false
    @State private var season: Int?

    init(preview: MetaPreview) {
        self.preview = preview
        _model = StateObject(wrappedValue: DetailViewModel(preview: preview))
    }

    // MARK: Derived (as OrbitDetailView)

    private var meta: MetaDetails? { model.meta }
    private var isSeries: Bool { meta.map(EpisodesSection.isSeriesLike) ?? (preview.type == "series") }
    private var title: String { meta?.name ?? preview.name }
    private var overview: String? {
        let text: String? = meta?.description_ ?? preview.description_
        return (text ?? "").isEmpty ? nil : text
    }
    private var logoCandidates: [String] {
        var seen = Set<String>()
        let tmdb: String? = metaStore.meta(for: preview)?.logo
        let previewLogo: String? = preview.logo
        let metaLogo: String? = meta?.logo
        return [tmdb, previewLogo, metaLogo].compactMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private var posterURL: String? { meta?.poster ?? preview.poster }
    private var backdropURL: String? {
        let raw: String? = meta?.background ?? preview.banner ?? metaStore.meta(for: preview)?.backdrop ?? preview.poster
        guard let raw, !raw.isEmpty else { return nil }
        return DetailBackdropURL.upgraded(raw)
    }
    private var streamVideoId: String { meta?.id ?? preview.id }
    private var playbackMeta: PlaybackMeta? { meta.map(PlaybackMeta.init(details:)) }

    // MARK: Body

    var body: some View {
        let margin = OrbitMobileMetrics.margin(sizeClass)
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 22) {
                    header(width: width, margin: margin)
                    VStack(alignment: .leading, spacing: 18) {
                        OrbitMetaLine(info: OrbitInfo.make(preview, meta: metaStore.meta(for: preview)),
                                      size: sizeClass == .regular ? 17 : 14)
                        actions
                        if let overview {
                            Text(overview)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(synopsisOpen ? nil : 4)
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { synopsisOpen.toggle() } }
                        }
                    }
                    .padding(.horizontal, margin)
                    if isSeries, let meta { episodes(meta, margin: margin) }
                    cast(margin: margin)
                }
                .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(OrbitHomeLayout.background.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            OrbitMetaStore.shared.request([preview])
            HeroTrailerAudioState.shared.setMuted(value: true)
            model.start()
        }
        .onDisappear { model.stop() }
        // Playback: as OrbitDetailView (the film's picker, a series episode's).
        .fullScreenCover(isPresented: $showStreams, onDismiss: openPostPlayPick) {
            StreamPickerView(type: preview.type, videoId: streamVideoId, title: title,
                             poster: posterURL, synopsis: overview, meta: playbackMeta,
                             logoUrl: logoCandidates.first, backdrop: backdropURL,
                             onOpenTitle: { postPlayPending = $0 })
        }
        .fullScreenCover(item: $seriesPlay, onDismiss: openPostPlayPick) { route in
            StreamPickerView(type: route.meta.type, videoId: route.videoId, title: route.pickerTitle,
                             parentMetaId: route.meta.id, season: route.season, episode: route.episode,
                             episodes: route.meta.videos, poster: route.meta.poster,
                             episodeStill: route.episodeStill, synopsis: route.synopsis, meta: playbackMeta,
                             logoUrl: logoCandidates.first, backdrop: backdropURL,
                             startFromBeginning: route.startFromBeginning,
                             onOpenTitle: { postPlayPending = $0 })
        }
        .navigationDestination(item: $postPlayRoute) { route in
            OrbitMobileDetail(preview: route.preview)
        }
    }

    // MARK: Header

    private func header(width: CGFloat, margin: CGFloat) -> some View {
        let height = width * 9 / 16 + 60
        return ZStack(alignment: .bottomLeading) {
            Color(white: 0.08)
            OrbitImage(url: backdropURL, fallback: posterURL, size: CGSize(width: width, height: height))
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                   .init(color: .clear, location: 0.3),
                                   .init(color: OrbitHomeLayout.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            OrbitTitleMark(name: title, logo: logoCandidates.first,
                           maxSize: CGSize(width: width * 0.66, height: height * 0.3),
                           textSize: sizeClass == .regular ? 44 : 32,
                           moreLogos: Array(logoCandidates.dropFirst()))
                .padding(.horizontal, margin)
                .padding(.bottom, 6)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label(playLabel, systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(OrbitPlainStyle())
            .disabled(!model.isPlayEnabled || (isSeries && model.seriesAction == nil))
            roundButton(model.isSaved ? "checkmark" : "plus",
                        label: model.isSaved ? String(localized: "Dans ma liste") : String(localized: "Ajouter à ma liste")) {
                model.toggleLibrary()
            }
            roundButton(model.isWatched ? "eye.fill" : "eye",
                        label: model.isWatched ? String(localized: "Vu") : String(localized: "Marquer comme vu")) {
                model.toggleWatched()
            }
        }
    }

    private var playLabel: String {
        if !model.isPlayEnabled { return String(localized: "Lecture indisponible") }
        if isSeries { return model.seriesAction.map { OrbitDetailFormat.playLabel($0.label) } ?? String(localized: "Lire") }
        return model.hasResumableProgress ? String(localized: "Reprendre") : String(localized: "Lire")
    }

    private func play() {
        if isSeries {
            guard let action = model.seriesAction, let meta else { return }
            model.noteSeriesPlayStarted(action)
            seriesPlay = OrbitSeriesPlayRoute(meta: meta, action: action)
        } else {
            showStreams = true
        }
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(OrbitPlainStyle())
        .accessibilityLabel(label)
    }

    private func openPostPlayPick() {
        guard let pick = postPlayPending else { return }
        postPlayPending = nil
        postPlayRoute = TitleRoute(preview: pick)
    }

    // MARK: Episodes

    @ViewBuilder
    private func episodes(_ meta: MetaDetails, margin: CGFloat) -> some View {
        let videos = meta.videos
        // Specials (season 0) last.
        let seasons = Set(videos.compactMap { $0.season?.value }).sorted { a, b in a == 0 ? false : (b == 0 ? true : a < b) }
        let current = season ?? model.seriesAction?.seasonNumber?.value ?? seasons.first
        let list = videos.filter { $0.season?.value == current }
            .sorted { ($0.episode?.value ?? 0) < ($1.episode?.value ?? 0) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "Épisodes")).font(.title3.bold()).foregroundStyle(.white)
                Spacer()
                if seasons.count > 1 {
                    Menu {
                        ForEach(seasons, id: \.self) { number in
                            Button(seasonName(number)) { season = number }
                        }
                    } label: {
                        Label(current.map { seasonName($0) } ?? "", systemImage: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(list, id: \.id) { (video: MetaVideo) in
                    Button { seriesPlay = OrbitSeriesPlayRoute(meta: meta, episode: video) } label: {
                        episodeRow(video)
                    }
                    .buttonStyle(OrbitPlainStyle())
                }
            }
        }
        .padding(.horizontal, margin)
    }

    private func seasonName(_ number: Int) -> String {
        number == 0 ? String(localized: "Épisodes spéciaux") : String(localized: "Saison \(number)")
    }

    private func episodeRow(_ video: MetaVideo) -> some View {
        let still: String? = video.thumbnail
        let overview: String? = video.overview
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Color(white: 0.12)
                OrbitImage(url: still, fallback: backdropURL, size: CGSize(width: 140, height: 79))
            }
            .frame(width: 140, height: 79)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(video.episode.map { "\($0.value). \(video.title)" } ?? video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: Cast

    @ViewBuilder
    private func cast(margin: CGFloat) -> some View {
        let people = meta?.cast ?? []
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Casting"))
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, margin)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                            castCard(person)
                        }
                    }
                    .padding(.horizontal, margin)
                }
            }
        }
    }

    private func castCard(_ person: MetaPerson) -> some View {
        let photo: String? = person.photo
        let role: String? = person.role
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                if let photo, !photo.isEmpty {
                    CachedAsyncImage(string: photo, decodeSize: .points(width: 80, height: 80))
                        .clipShape(Circle())
                } else {
                    Text(String(person.name.prefix(1)))
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 76, height: 76)
            Text(person.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let role, !role.isEmpty {
                Text(role.replacingOccurrences(of: " (voice)", with: String(localized: " (voix)")))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(width: 86)
    }
}
