import SwiftUI

/// Steven's fork (Orbit bar): a short Orbit-logo transition when the bar opens Plateformes or
/// Studios from another page (Films, Séries, Search…). Never between those two. Drawn over the
/// whole screen by `OrbitTopBar`, never hit-tested and never focusable, so the remote keeps working
/// under it and the page is live the whole time. Settings › Appearance › "Animation Plateformes /
/// Studios" picks the style (`defaultsKey`).
///
/// - Portal: the wordmark fades in on black, then the planet's tilted ring opens out of it and
///   uncovers the page as it grows (the collection intro's "logo big on black" language).
/// - Fly: the wordmark leaves the bar item, grows to the centre over a dimmed page, then dissolves.
struct OrbitSpaceTransition: View {
    enum Style: String, CaseIterable {
        case portal, fly, off

        var label: String {
            switch self {
            case .portal: return String(localized: "Portail")
            case .fly: return String(localized: "Logo qui s'envole")
            case .off: return String(localized: "Aucune")
            }
        }
    }

    static let defaultsKey = "orbit_space_transition"

    static var currentStyle: Style {
        Style(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .portal
    }

    let style: Style
    /// The bar item's centre, in screen points (the fly's start).
    let origin: CGPoint
    let onDone: () -> Void

    // Portal
    @State private var black: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.7
    @State private var hole: CGFloat = 0
    @State private var ringOpacity: Double = 0
    // Fly
    @State private var flyProgress: CGFloat = 0
    @State private var flyOut = false

    private static let logoWidth: CGFloat = 760
    private static let ringAspect: CGFloat = 0.42
    private static let ringTilt = Angle.degrees(-14)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                switch style {
                case .portal: portal(size: size, centre: centre)
                case .fly: fly(centre: centre)
                case .off: EmptyView()
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: run)
    }

    // MARK: Portal

    @ViewBuilder
    private func portal(size: CGSize, centre: CGPoint) -> some View {
        Color.black
            .opacity(black)
            .mask {
                ZStack {
                    Rectangle()
                    Ellipse()
                        .frame(width: hole * 2, height: hole * 2 * Self.ringAspect)
                        .rotationEffect(Self.ringTilt)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        Ellipse()
            .stroke(Color.white, lineWidth: 10)
            .frame(width: max(hole, 1) * 2, height: max(hole, 1) * 2 * Self.ringAspect)
            .rotationEffect(Self.ringTilt)
            .opacity(ringOpacity)
        wordmark
            .frame(width: Self.logoWidth)
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
    }

    // MARK: Fly

    @ViewBuilder
    private func fly(centre: CGPoint) -> some View {
        let p = flyProgress
        let width = 70 + (Self.logoWidth - 70) * p
        Color.black.opacity(flyOut ? 0 : 0.72 * Double(p))
        wordmark
            .frame(width: width)
            .scaleEffect(flyOut ? 1.18 : 1)
            .opacity(flyOut ? 0 : 1)
            .position(x: origin.x + (centre.x - origin.x) * p,
                      y: origin.y + (centre.y - origin.y) * p)
    }

    private var wordmark: some View {
        Image("OrbitWordmark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    // MARK: Timeline

    private func run() {
        switch style {
        case .off:
            onDone()
        case .portal:
            withAnimation(.easeOut(duration: 0.2)) {
                black = 1
                logoOpacity = 1
                logoScale = 1
            }
            after(0.42) {
                ringOpacity = 1
                withAnimation(.easeIn(duration: 0.6)) {
                    hole = 2400
                    logoScale = 1.3
                    logoOpacity = 0
                }
                withAnimation(.easeIn(duration: 0.6).delay(0.2)) { ringOpacity = 0 }
            }
            after(1.1) { onDone() }
        case .fly:
            withAnimation(.easeInOut(duration: 0.5)) { flyProgress = 1 }
            after(0.62) {
                withAnimation(.easeOut(duration: 0.4)) { flyOut = true }
            }
            after(1.1) { onDone() }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
