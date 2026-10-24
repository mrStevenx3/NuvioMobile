import SwiftUI
import SharedCore
import Combine

/// The typed text, observed only by `SearchFieldLayer`. Never `@State`: see `SearchView`.
/// BUG-155: `SearchContent` no longer reads it either (it reads the view model's debounced
/// `displayQuery` and `queryIsEmpty`); it only WRITES it, when a Recent or suggestion chip is picked.
final class SearchQueryBox: ObservableObject {
    @Published var text = "" {
        didSet {
            #if DEBUG
            if text != oldValue { SearchPerfProbe.keystroke() }
            #endif
        }
    }
}

