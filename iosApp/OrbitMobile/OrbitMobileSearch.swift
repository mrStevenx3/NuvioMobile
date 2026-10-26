import SharedCore
import SwiftUI

// Orbit mobile Search: the system search field (.searchable) over a poster grid, the data the TV's
// Search uses (`SearchViewModel`; every title found, top result first, as `SearchGridResults.items`).

struct OrbitMobileSearch: View {
    @StateObject private var model = SearchViewModel()
    @State private var query = ""
    @State private var path = NavigationPath()
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var items: [MetaPreview] { SearchGridResults.items(top: model.topResult, rows: model.rows) }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    content(width: geo.size.width)
                        .padding(.bottom, 30)
                }
            }
            .background(OrbitHomeLayout.background.ignoresSafeArea())
            .navigationTitle(String(localized: "Recherche"))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: String(localized: "Films, séries…"))
            .autocorrectionDisabled()
            .onChange(of: query) { _, text in model.queryChanged(text) }
            .onSubmit(of: .search) { record() }
            .navigationDestination(for: TitleRoute.self) { route in
                OrbitMobileDetail(preview: route.preview)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        let margin = OrbitMobileMetrics.margin(sizeClass)
        if model.queryIsEmpty {
            history(margin: margin)
        } else if items.isEmpty {
            VStack(spacing: 12) {
                if model.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(emptyText).font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    if case .manifestFailure = model.emptyState {
                        Button(String(localized: "Réessayer")) { model.retrySearch() }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(.horizontal, margin)
        } else {
            grid(width: width, margin: margin)
        }
    }

    private func grid(width: CGFloat, margin: CGFloat) -> some View {
        let columns = sizeClass == .regular ? 6 : 3
        let spacing: CGFloat = 10
        let cell = max(60, floor((width - 2 * margin - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
        let poster = OrbitTileLayout.poster
        let factor = cell / poster.width
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: columns),
                         alignment: .leading, spacing: 14) {
            ForEach(items, id: \.id) { (item: MetaPreview) in
                Button {
                    record()
                    path.append(TitleRoute(preview: item))
                } label: {
                    OrbitMobileScaled(size: poster, factor: factor) {
                        OrbitSmallPoster(card: OrbitCard.catalog(item), meta: OrbitMetaStore.shared.meta(for: item), focused: false)
                    }
                }
                .buttonStyle(OrbitPlainStyle())
                .onAppear { OrbitMetaStore.shared.request([item]) }
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func history(margin: CGFloat) -> some View {
        if !model.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Recherches récentes"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                ForEach(model.history, id: \.self) { entry in
                    HStack {
                        Button { query = entry } label: {
                            Label(entry, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button { model.removeHistory(entry) } label: {
                            Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                        }
                        .accessibilityLabel(String(localized: "Supprimer"))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 10)
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
            .padding(.horizontal, margin)
        }
    }

    private var emptyText: String {
        switch model.emptyState {
        case .manifestFailure(let message): return message
        case .noneCanSearch: return String(localized: "Aucune de vos extensions ne permet la recherche.")
        case .allSourcesOff: return String(localized: "Toutes les sources de recherche sont désactivées.")
        case .noResults: return String(localized: "Aucun résultat")
        case nil: return String(localized: "Aucun résultat")
        }
    }

    private func record() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { model.recordSearch(text) }
    }
}
