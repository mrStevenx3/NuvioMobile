import Foundation

/// Steven's fork (2026-10-24): Orbit's top bar (`OrbitTopBar`) is the only navigation. Chris's rail
/// and the system tab bar are gone, whatever an old install stored; only the keys stay, so the
/// one-time reset (`OrbitSettingsPins`) can clear what they left behind.
nonisolated enum NavigationChrome {
    static let styleKey = "sidebar_style"
    static let railVisibilityKey = "rail_visibility"
    static let railPositionKey = "rail_position"
    static let railLabelsKey = "rail_labels"
    static let railStyleKey = "rail_style"

    enum Style: String, Equatable, Sendable {
        case tabs
        case rail
        case orbit
    }

    static func isRail(_ defaults: UserDefaults = .standard) -> Bool { false }

    static func isOrbitBar(_ defaults: UserDefaults = .standard) -> Bool { true }
}
