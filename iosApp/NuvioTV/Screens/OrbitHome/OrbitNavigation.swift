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
    /// Steven (device): out of sight while a trailer plays full screen on a title's page.
    @Published var hidden = false
    /// The tab's stack is going back to its root: the house goes at once (Steven: back to Search
    /// it showed a second, the time the pushed page took to go).
    @Published var poppingToRoot = false

    var mode: Mode { ownBars > 0 ? .ownBar : (canvases > 0 ? .onRequest : .free) }

    func enter(_ kind: Mode) {
        switch kind {
        case .ownBar: ownBars += 1
        case .onRequest: canvases += 1
        case .free: break
        }
    }

    func leave(_ kind: Mode) {
        // Steven (simulator: back from a platform or a studio, the house showed for a second on the
        // Plateformes / Studios page): the page leaving gives its house back a moment later — the
        // bar's own return (one turn later) comes first, so the house never shows in between.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            switch kind {
            case .ownBar: self.ownBars = max(0, self.ownBars - 1)
            case .onRequest: self.canvases = max(0, self.canvases - 1)
            case .free: break
            }
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

    private var shown: Bool { immersive && host.mode != .ownBar && !host.hidden && !host.poppingToRoot }
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
            if host.poppingToRoot { host.poppingToRoot = false }
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

// MARK: - Platform curtain

/// Steven (2026-10-27: "il faudrait que l'animation s'ouvre avant la page"): pressing a platform
/// on the Plateformes page first darkens the screen (over the grid), and only then is the page
/// pushed — under the black. The page's own opening lifts the curtain once its logo shows, so the
/// page is never seen before its opening.
@MainActor
final class OrbitPlatformCurtain: ObservableObject {
    static let shared = OrbitPlatformCurtain()
    @Published private(set) var down = false
    /// The platform's opening drawn on the curtain itself (nil: plain black, a studio's).
    @Published private(set) var look: OrbitPlatformLook?
    /// The logo shown (it grows in as the screen darkens).
    @Published private(set) var logoIn = false
    /// The logo's neon, played on the curtain itself (Steven: it sat dark too long — it switches
    /// on right at the press; the page under it takes over lit).
    @Published private(set) var dim: Double = 1
    @Published private(set) var glow: Double = 0
    private var token = 0
    /// The neon is over (lit, its glow settled): the page under it can show.
    static let litAfter: Double = 1.25

    /// Steven (2026-10-27, "plus naturel"): the press opens the platform straight away — its colour
    /// and logo come up over the grid as an app opening — and its page is pushed under it, already
    /// showing the very same opening, which then carries on (the logo to its corner).
    func drop(look: OrbitPlatformLook? = nil, then: @escaping () -> Void) {
        token &+= 1
        let mine = token
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { self.look = look; logoIn = false; dim = 1; glow = 0 }
        withAnimation(.easeOut(duration: 0.25)) { down = true }
        withAnimation(.easeOut(duration: 0.3)) { logoIn = true }
        if look != nil {
            OrbitNeon.play(at: 0.2) { [weak self] d, g, animation in
                guard let self, self.token == mine, self.down else { return }
                withAnimation(animation) { self.dim = d; self.glow = g }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { then() }
        // Never left over the app (a page with no opening).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.token == mine { self?.lift() }
        }
    }

    /// `instant`: the page under it shows the same thing — it simply goes.
    func lift(instant: Bool = false) {
        guard down else { return }
        if instant {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { down = false; logoIn = false }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { down = false }
        }
    }
}

struct OrbitPlatformCurtainView: View {
    @ObservedObject private var curtain = OrbitPlatformCurtain.shared

    var body: some View {
        let W = OrbitHomeLayout.screenWidth, H = OrbitHomeLayout.screenHeight
        ZStack {
            Color.black
            if let look = curtain.look {
                RadialGradient(colors: [look.brand.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 900)
                if look.studio {
                    OrbitStudioIntroLogo(name: look.title, logoUrl: look.logoUrl, corner: false)
                        .frame(width: OrbitStudioIntro.cornerBox.width, height: OrbitStudioIntro.cornerBox.height)
                        .modifier(OrbitLightUp(dim: curtain.dim, glow: curtain.glow, tint: look.brand))
                        .scaleEffect(OrbitStudioIntro.splashScale * (curtain.logoIn ? 1 : 0.92))
                        .opacity(curtain.logoIn ? 1 : 0)
                        .position(x: W / 2, y: H / 2)
                } else {
                    OrbitPlatformIntroLogo(look: look)
                        .frame(width: OrbitPlatformIntro.logoSize.width, height: OrbitPlatformIntro.logoSize.height)
                        .modifier(OrbitLightUp(dim: curtain.dim, glow: curtain.glow, tint: look.brand))
                        .scaleEffect(OrbitPlatformIntro.splashScale * (curtain.logoIn ? 1 : 0.85))
                        .opacity(curtain.logoIn ? 1 : 0)
                        .position(x: W / 2, y: H / 2)
                }
            }
        }
        .frame(width: W, height: H)
        .ignoresSafeArea()
        .opacity(curtain.down ? 1 : 0)
        .allowsHitTesting(false)
    }
}

private struct OrbitPushStudioKey: EnvironmentKey {
    static let defaultValue: ((OrbitStudioRoute) -> Void)? = nil
}

private struct OrbitPushFolderKey: EnvironmentKey {
    static let defaultValue: ((FolderRoute) -> Void)? = nil
}

extension EnvironmentValues {
    /// Pushes a platform's page onto the current tab's stack; nil outside one.
    var orbitPushFolder: ((FolderRoute) -> Void)? {
        get { self[OrbitPushFolderKey.self] }
        set { self[OrbitPushFolderKey.self] = newValue }
    }
    /// Pushes a studio's page onto the current tab's stack; nil outside one.
    var orbitPushStudio: ((OrbitStudioRoute) -> Void)? {
        get { self[OrbitPushStudioKey.self] }
        set { self[OrbitPushStudioKey.self] = newValue }
    }
}

// MARK: - Simulator trace

/// A line in ~/Orbit/logs/focus.log on the Mac (simulator only: Claude reads it to see what the
/// focus really did — Steven's videos cannot show the system's own landings).
enum OrbitTrace {
    #if targetEnvironment(simulator)
    nonisolated(unsafe) private static var handle: FileHandle? = {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        let path = home + "/Orbit/logs/focus.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()
    nonisolated(unsafe) private static let start = ProcessInfo.processInfo.systemUptime
    #endif

    nonisolated static func log(_ text: @autoclosure () -> String) {
        #if targetEnvironment(simulator)
        let t = String(format: "%8.3f", ProcessInfo.processInfo.systemUptime - start)
        if let data = "\(t) \(text())\n".data(using: .utf8) { handle?.seekToEndOfFile(); handle?.write(data) }
        #endif
    }
}


extension View {
    /// The house goes the moment this stack heads back to its root (not once the page has gone).
    func orbitHouseFollows(_ depth: Int) -> some View {
        onChange(of: depth) { old, new in
            if new == 0, old > 0 { OrbitHomeButtonHost.shared.poppingToRoot = true }
        }
    }
}
