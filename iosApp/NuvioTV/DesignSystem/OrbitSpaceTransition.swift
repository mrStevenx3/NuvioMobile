import SwiftUI

/// Steven's fork (Orbit bar): the "portal" — a short Orbit-logo transition when the bar enters
/// Plateformes / Studios from another page, or leaves them for another page (never between those
/// two). The logo fades in on black, then the planet's tilted ring opens out of it and uncovers the
/// page as it grows (the collection intro's "logo big on black" language). Drawn over the whole
/// screen by `OrbitTopBar`, never hit-tested and never focusable, so the remote keeps working.
struct OrbitSpaceTransition: View {
    let onDone: () -> Void

    // Portal
    @State private var black: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.7
    @State private var hole: CGFloat = 0
    @State private var ringOpacity: Double = 0
    /// The redrawn bunny-planet (`OrbitMark`, 722 × 631 px @2x). Its ring is the portal: same
    /// tilt, same aspect, centred on the screen, so the portal opens straight out of it.
    private static let logoWidth: CGFloat = 520
    private static let logoAspect: CGFloat = 631.0 / 722.0
    /// The ring's centre, as a fraction of the mark's height (it sits low, under the ears).
    private static let ringCentreY: CGFloat = 448.0 / 631.0
    private static let ringAspect: CGFloat = 192.0 / 715.0
    private static let ringTilt = Angle.degrees(-14)
    /// The mark's ring: half its major axis and its stroke, in points.
    private static let ringStart: CGFloat = logoWidth * 715.0 / 722.0 / 2
    private static let ringStroke: CGFloat = logoWidth * 22.0 / 722.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                portal(size: size, centre: centre)
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
            .stroke(Color.white, lineWidth: Self.ringStroke)
            .frame(width: max(hole, 1) * 2, height: max(hole, 1) * 2 * Self.ringAspect)
            .rotationEffect(Self.ringTilt)
            .opacity(ringOpacity)
        mark
            .frame(width: Self.logoWidth, height: Self.logoWidth * Self.logoAspect)
            // Ring centre on the screen centre (the portal's centre).
            .offset(y: -(Self.ringCentreY - 0.5) * Self.logoWidth * Self.logoAspect)
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
    }

    private var mark: some View {
        Image("OrbitMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    // MARK: Timeline

    private func run() {
            withAnimation(.easeOut(duration: 0.2)) {
                black = 1
                logoOpacity = 1
                logoScale = 1
            }
            after(0.4) {
                // The portal starts as the mark's own ring and opens out of it.
                hole = Self.ringStart
                ringOpacity = 1
            }
            after(0.44) {
                withAnimation(.easeIn(duration: 0.6)) {
                    hole = 2400
                    logoScale = 1.3
                    logoOpacity = 0
                }
                withAnimation(.easeIn(duration: 0.6).delay(0.2)) { ringOpacity = 0 }
            }
            after(1.3) { onDone() }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
