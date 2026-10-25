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
}

extension View {
    /// Pops this stack to its root on `orbitGoHome`.
    func orbitPopsToRootOnGoHome(_ path: Binding<NavigationPath>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .orbitGoHome)) { _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if !path.wrappedValue.isEmpty { path.wrappedValue = NavigationPath() }
            }
        }
    }
}

/// Steven (2026-10-25): a house top left on every pushed page (the Orbit bar is hidden there), so
/// Home is one press away instead of several Backs. Up from the page's top left reaches it.
struct OrbitHomeButton: View {
    let tabBarVisibility: TabBarVisibility
    @Binding var selectedTab: Int

    @State private var shown = false
    /// Out of the focus engine's first pick on a push (top left), for a beat.
    @State private var ready = false
    @State private var readyGeneration = 0
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: goHome) {
            Image(systemName: "house.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(focused ? Color.black : Color.white)
                .frame(width: 66, height: 66)
                .background(Circle().fill(focused ? Color.white : Color.white.opacity(0.12)))
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 0 : 0.24), lineWidth: 1))
                .scaleEffect(focused ? 1.08 : 1)
                .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 14, y: 6)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(OrbitHomeButtonStyle())
        .focused($focused)
        .accessibilityLabel(Text("Accueil"))
        .disabled(!shown || !ready)
        // The band top left only: the collection bar sits top right.
        .frame(width: 560, alignment: .leading)
        .focusSection()
        .padding(.top, 22)
        .padding(.leading, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(.easeOut(duration: 0.2), value: shown)
        .onReceive(tabBarVisibility.$immersiveHidden) { hidden in
            guard hidden != shown else { return }
            shown = hidden
            ready = false
            readyGeneration &+= 1
            let generation = readyGeneration
            guard hidden else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if generation == readyGeneration { ready = true }
            }
        }
    }

    private func goHome() {
        NotificationCenter.default.post(name: .orbitGoHome, object: nil)
        HomeContentFilterModel.shared.set(.movies)
        selectedTab = 0
    }
}

private struct OrbitHomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
