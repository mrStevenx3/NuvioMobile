import Combine
import SwiftUI

// Pushing a page from a page drawn on a canvas (Steven's fork, 2026-10-25). Each tab's navigation
// stack hands its pages a way to push a title onto its own path, so every page opened from any
// depth is an ordinary entry of that path. (A page pushed with `navigationDestination(item:)`
// broke the stack: a title opened from it — "Voir aussi" — showed the first one again.)

private struct OrbitPushKey: EnvironmentKey {
    static let defaultValue: ((TitleRoute) -> Void)? = nil
}

extension EnvironmentValues {
    /// Pushes a title onto the current tab's stack; nil outside one.
    var orbitPush: ((TitleRoute) -> Void)? {
        get { self[OrbitPushKey.self] }
        set { self[OrbitPushKey.self] = newValue }
    }
}

// MARK: - Back to Home

extension Notification.Name {
    /// Every tab's stack pops to its root, and the shell shows Home (Films).
    static let orbitGoHome = Notification.Name("orbit.goHome")
    /// Back from the house (Steven, 2026-10-25: Menu there closed the app): the shown tab's stack
    /// pops one page. `object`: the tab's index.
    static let orbitGoBack = Notification.Name("orbit.goBack")
}

/// The shell's selected tab, for the house's Back (it lives outside every tab's stack).
@MainActor
enum OrbitShownTab {
    static var index = 0
}

extension View {
    /// Pops this stack to its root on `orbitGoHome`. `delay`: the other tabs' stacks pop once Home
    /// is on screen (Steven: from a film opened in Search, the search page showed before Home).
    func orbitPopsToRootOnGoHome(_ path: Binding<NavigationPath>, tab: Int, delay: TimeInterval = 0.5) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .orbitGoBack)) { note in
            guard (note.object as? Int) == tab, !path.wrappedValue.isEmpty else { return }
            path.wrappedValue.removeLast()
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitGoHome)) { _ in
            let pop = {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if !path.wrappedValue.isEmpty { path.wrappedValue = NavigationPath() }
                }
            }
            if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: pop) } else { pop() }
        }
    }
}

/// How the pushed page on screen takes the house (Steven, 2026-10-25, pass 2).
@MainActor
final class OrbitHomeButtonHost: ObservableObject {
    static let shared = OrbitHomeButtonHost()

    enum Mode { case free, ownBar, onRequest }

    /// The pages on screen that draw their own house (a collection: in its bar).
    @Published private var ownBars = 0
    /// The pages on screen drawn on a canvas: the house is reached from their top only (else the
    /// focus engine sent every Up there instead of to the row above).
    @Published private var canvases = 0

    var mode: Mode { ownBars > 0 ? .ownBar : (canvases > 0 ? .onRequest : .free) }

    func enter(_ kind: Mode) {
        switch kind {
        case .ownBar: ownBars += 1
        case .onRequest: canvases += 1
        case .free: break
        }
    }

    func leave(_ kind: Mode) {
        switch kind {
        case .ownBar: ownBars = max(0, ownBars - 1)
        case .onRequest: canvases = max(0, canvases - 1)
        case .free: break
        }
    }
}

extension Notification.Name {
    /// A canvas page's Up at its top: the house takes the focus.
    static let orbitHomeButtonFocus = Notification.Name("orbit.homeButton.focus")
    /// Down from the house: the canvas page takes the focus back.
    static let orbitHomeButtonLeave = Notification.Name("orbit.homeButton.leave")
}

/// Steven (2026-10-25): a house top left on every pushed page (the Orbit bar is hidden there), so
/// Home is one press away instead of several Backs. Up from the page's top left reaches it; a
/// collection has it in its own bar instead, and a canvas page hands it the focus from its top.
struct OrbitHomeButton: View {
    let tabBarVisibility: TabBarVisibility
    @ObservedObject private var host = OrbitHomeButtonHost.shared

    @State private var immersive = false
    /// Out of the focus engine's first pick on a push (top left), for a beat.
    @State private var ready = false
    @State private var readyGeneration = 0
    /// A canvas page handed it the focus.
    @State private var requested = false
    @FocusState private var focused: Bool

    private var shown: Bool { immersive && host.mode != .ownBar }
    private var reachable: Bool { shown && ready && (host.mode == .free || requested) }

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .orbitGoHome, object: nil)
        } label: {
            Image(systemName: "house")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(focused ? Color.black : Color.white)
                .frame(width: 62, height: 62)
                .background(Circle().fill(focused ? Color.white : Color.white.opacity(0.10)))
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 0 : 0.24), lineWidth: 1))
                .scaleEffect(focused ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(OrbitHomeButtonStyle())
        .focused($focused)
        .accessibilityLabel(Text("Accueil"))
        .disabled(!reachable)
        // Steven: Back from the house goes back one page (it closed the app: the house is outside
        // the tab's stack, so the system took Menu as leaving Orbit).
        .onExitCommand {
            requested = false
            focused = false
            NotificationCenter.default.post(name: .orbitGoBack, object: OrbitShownTab.index)
        }
        .onMoveCommand { direction in
            guard direction == .down, host.mode == .onRequest else { return }
            requested = false
            NotificationCenter.default.post(name: .orbitHomeButtonLeave, object: nil)
        }
        // Where the collection bar's own items sit (the same top and left, one item's height).
        .padding(.top, 22 + 6)
        .padding(.leading, 60 + 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(.easeOut(duration: 0.2), value: shown)
        .onReceive(tabBarVisibility.$immersiveHidden) { hidden in
            guard hidden != immersive else { return }
            immersive = hidden
            ready = false
            requested = false
            readyGeneration &+= 1
            let generation = readyGeneration
            guard hidden else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if generation == readyGeneration { ready = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .orbitHomeButtonFocus)) { _ in
            guard immersive, host.mode == .onRequest else { return }
            ready = true
            requested = true
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: focused) { _, isFocused in
            // Left by any other way (Menu, a page taking the focus back): asked again next time.
            if !isFocused, host.mode == .onRequest { requested = false }
        }
    }
}

private struct OrbitHomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
