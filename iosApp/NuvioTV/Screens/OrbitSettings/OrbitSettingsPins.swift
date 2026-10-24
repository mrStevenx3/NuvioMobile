import Foundation
import SharedCore

// Orbit Réglages (Steven, 2026-10-24): the settings that left with Chris's screens are pinned to
// Orbit's choices, so no hidden value can still change the app.
//
// - Every launch: Orbit's home stays on (its switch is gone).
// - Once: Chris's test switches and probes ("debug.…" keys: A/B legs, diagnostics) go back to
//   their normal values, and the custom poster service (RPDB…) is cleared — Orbit has one look.
//   The other look settings keep what this Apple TV shows today (the screens Steven validated).
enum OrbitSettingsPins {
    private static let onceKey = "orbit.settingsPins.v1"
    /// The crash guard of the seek preview harvester is not a test switch: it stays.
    private static let keptDebugKeys: Set<String> = [HarvestCrashSentinel.disabledKey]

    static func apply() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: OrbitHomeSetting.enabledKey)

        guard !defaults.bool(forKey: onceKey) else { return }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("debug.") && !keptDebugKeys.contains(key) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: onceKey)
        // After launch (the shared repositories are up by then).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            CustomPosterUrlRepository.shared.clearPattern()
        }
    }
}
