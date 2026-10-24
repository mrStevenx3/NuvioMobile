import SwiftUI

/// F (FEAT-54): the row edge fade setting, `row_edge_fade` (device-local, not synced — like every
/// other Appearance look key read with `@AppStorage`). `-row_edge_fade off` works as a launch
/// argument.
nonisolated enum RowEdgeFadeSetting: String, CaseIterable, Sendable {
    /// The app-drawn eased mask, system scroll-edge effect hidden. Opt-in: the F.5 frame-time gate
    /// (Living Room Apple TV, 2026-10-04) measured it at +1.1 ms vertical p95 and +6 dropped frames
    /// against Off, past the 1.0 ms / max(2, 10 %) bar, so it is not the default.
    case soft
    /// tvOS's own `.automatic` scroll-edge effect.
    case system
    /// `scrollEdgeEffectHidden(true)`, no mask. DEFAULT (the F.5 gate, see `soft`).
    case off

    static let defaultsKey = "row_edge_fade"
    /// The BUG-118 Developer A/B this setting replaces (Int: 0 hard, 1 soft, 2 automatic, 3 off).
    static let legacyKey = "debug.rowEdgeFade"
    /// The legacy A/B's legs that carry across (`legacySetting`); 0 (Hard) does not.
    static let legacySoftValue = 1
    static let legacyAutomaticValue = 2
    static let legacyOffValue = 3
    static let defaultValue: RowEdgeFadeSetting = .off

    /// Unknown, blank or nil → `defaultValue`. Trimmed and lower-cased, so a hand-typed launch
    /// argument (`-row_edge_fade Soft`) still resolves.
    static func resolve(_ raw: String?) -> RowEdgeFadeSetting {
        guard let raw else { return defaultValue }
        return RowEdgeFadeSetting(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? defaultValue
    }

    static func current(_ defaults: UserDefaults = .standard) -> RowEdgeFadeSetting {
        resolve(defaults.string(forKey: defaultsKey))
    }

    /// Carries the BUG-118 Developer A/B (`debug.rowEdgeFade`) across as `row_edge_fade` per
    /// `legacySetting`. The legacy key is removed either way. Never overwrites an existing
    /// `row_edge_fade`. Runs once per launch from `NuvioTVApp.init`; a no-op once the legacy key is
    /// gone.
    static func migrateLegacy(_ defaults: UserDefaults) {
        guard defaults.object(forKey: legacyKey) != nil else { return }
        if defaults.object(forKey: defaultsKey) == nil,
           let carried = legacySetting(defaults.integer(forKey: legacyKey)) {
            defaults.set(carried.rawValue, forKey: defaultsKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }

    /// The setting an old A/B value (0 hard, 1 soft, 2 automatic, 3 off) carries across as, or nil
    /// to land on `defaultValue`. Christian 2026-10-04, once the F.5 gate made Off the default: an
    /// explicit Soft, Automatic (now System) or Off choice carries across, so a tester who picked
    /// Soft keeps it and an Off pick stays Off if the default ever moves again. Hard has no
    /// counterpart and follows the default.
    static func legacySetting(_ legacy: Int) -> RowEdgeFadeSetting? {
        switch legacy {
        case legacySoftValue: return .soft
        case legacyAutomaticValue: return .system
        case legacyOffValue: return .off
        default: return nil
        }
    }

    /// The picker label. All three strings already exist in the catalog (the Developer A/B used
    /// them).
    var label: String {
        switch self {
        case .soft: return String(localized: "Soft")
        case .system: return String(localized: "System")
        case .off: return String(localized: "Off")
        }
    }
}

