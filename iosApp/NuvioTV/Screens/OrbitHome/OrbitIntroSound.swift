import AVFoundation
import Foundation

/// Steven (2026-10-31: "le son d'ouverture de l'application officielle"): a platform's own opening
/// sound as its page opens (the Plateformes page's opening). His files, trimmed of their leading
/// silence and brought to one loudness (`Resources/Sounds/orbit-intro-*.m4a`). The sound plays
/// to its end as the page shows (as the apps do); a press during the opening, a trailer with
/// its sound, or leaving the page fades it out. Réglages › Lecture can turn it off.
@MainActor
enum OrbitIntroSound {
    static let enabledKey = "orbit_intro_sound"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// A touch under full: the files are at -24 LUFS, the system's volume does the rest.
    private static let volume: Float = 0.9
    private static var players: [String: AVAudioPlayer] = [:]
    private static var current: AVAudioPlayer?
    private static var startedAt: TimeInterval = 0
    private static var stopWork: DispatchWorkItem?

    /// The sound's file for a platform's title (nil: no sound, the opening stays silent).
    static func file(for title: String) -> String? {
        let t = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("netflix") { return "orbit-intro-netflix" }
        if t.contains("disney") { return "orbit-intro-disney" }
        if t.contains("prime") || t.contains("amazon") { return "orbit-intro-prime" }
        if t.contains("hbo") || t == "max" || t.hasPrefix("max") { return "orbit-intro-hbo" }
        if t.contains("paramount") { return "orbit-intro-paramount" }
        if t.contains("appletv") || t == "apple" { return "orbit-intro-appletv" }
        return nil
    }

    private static func player(_ name: String) -> AVAudioPlayer? {
        if let ready = players[name] { return ready }
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let made = try? AVAudioPlayer(contentsOf: url) else { return nil }
        made.prepareToPlay()
        players[name] = made
        return made
    }

    /// The opening of a platform's page starts: its sound with it.
    static func play(title: String) {
        guard enabled, let name = file(for: title), let next = player(name) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // (The curtain and the page's own opening both say it: once.)
        if next === current, next.isPlaying, now - startedAt < 2 { return }
        stopWork?.cancel()
        current?.stop()
        next.currentTime = 0
        next.volume = volume
        next.play()
        current = next
        startedAt = now
    }

    /// A press during the opening, a trailer with its sound, the page left: the sound goes, softly.
    static func fadeOut(_ duration: TimeInterval = 0.4) {
        guard let playing = current, playing.isPlaying else { return }
        playing.setVolume(0, fadeDuration: duration)
        stopWork?.cancel()
        let work = DispatchWorkItem { playing.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: work)
    }
}
