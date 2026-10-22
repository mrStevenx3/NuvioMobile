import SwiftUI
import SharedCore

/// Steven's fork (Orbit, Netflix-style Search): a typed query shows a column of text suggestions on
/// the left (completions, then the titles found) and every title found as one poster grid on the
/// right, instead of the suggestion chips, Top result card and per-type rows. The system search
/// field and its keyboard stay above (Linear keyboard: one row of letters, like Netflix).
struct SearchGridResults: View {
    /// Text entries for the left column; selecting one puts it in the search field.
    let entries: [String]
    /// Every title found, deduplicated, in result order.
    let items: [MetaPreview]
    let onPick: (String) -> Void
    let onFocus: (MetaPreview) -> Void

    @FocusState private var focusedEntry: String?
    @FocusState private var focusedItem: String?

    static let listWidth: CGFloat = 440
    static let columnGap: CGFloat = 60
    static let columns = 4
    static let gridSpacing: CGFloat = 36

    var body: some View {
        let gridWidth = UIScreen.main.bounds.width - 2 * Theme.Spacing.screen - Self.listWidth - Self.columnGap
        let posterWidth = floor((gridWidth - CGFloat(Self.columns - 1) * Self.gridSpacing) / CGFloat(Self.columns))
        let posterHeight = floor(posterWidth * 1.5)
        HStack(alignment: .top, spacing: Self.columnGap) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries, id: \.self) { entry in
                    Button { onPick(entry) } label: {
                        Text(entry)
                            .font(.system(size: 30, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(focusedEntry == entry ? Color.black : Color.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .frame(width: Self.listWidth, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(focusedEntry == entry ? Color.white : Color.clear)
                            }
                            .animation(.easeOut(duration: 0.15), value: focusedEntry == entry)
                    }
                    .buttonStyle(SearchEntryButtonStyle())
                    .focused($focusedEntry, equals: entry)
                }
            }
            .frame(width: Self.listWidth, alignment: .leading)
            .focusSection()

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(posterWidth), spacing: Self.gridSpacing, alignment: .top),
                                     count: Self.columns),
                      alignment: .leading, spacing: Self.gridSpacing) {
                ForEach(items, id: \.id) { item in
                    NavigationLink(value: TitleRoute(preview: item)) {
                        PosterCard(title: item.name, imageURL: item.poster, fallbackImageURL: item.rawPosterUrl,
                                   width: posterWidth, height: posterHeight, showTitle: false)
                    }
                    .cardFocusButtonStyle()
                    .posterButtonShape()
                    .titleHoldMenu(preview: item)
                    .focused($focusedItem, equals: item.id)
                }
            }
            .focusSection()
        }
        .onChange(of: focusedItem) { _, id in
            guard let id, let item = items.first(where: { $0.id == id }) else { return }
            onFocus(item)
        }
    }

    /// The left column's entries: the completions (minus the quoted query), then the titles found.
    static func entries(suggestions: [String], items: [MetaPreview], limit: Int = 12) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for text in suggestions.dropFirst() + items.map(\.name) {
            let key = text.lowercased()
            guard !text.isEmpty, seen.insert(key).inserted else { continue }
            out.append(text)
            if out.count == limit { break }
        }
        return out
    }

    /// Every row's titles, top result first, without repeats.
    static func items(top: MetaPreview?, rows: [HomeCatalogSection]) -> [MetaPreview] {
        var out: [MetaPreview] = []
        var seen = Set<String>()
        for item in [top].compactMap({ $0 }) + rows.flatMap(\.items) {
            if seen.insert(item.id).inserted { out.append(item) }
        }
        return out
    }
}

/// No system lift (the label draws its own white highlight).
private struct SearchEntryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}
