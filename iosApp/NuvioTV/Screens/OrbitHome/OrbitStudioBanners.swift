import Combine
import SharedCore
import SwiftUI

/// Steven (2026-10-30): each studio's banner on the Studios page is the official backdrop, without
/// any text, of one of its emblematic films (TMDB's), chosen with him — the studio is known at a
/// glance. The studio's own configured image stays the fallback while it loads, or if it never does.
@MainActor
final class OrbitStudioBanners: ObservableObject {
    static let shared = OrbitStudioBanners()

    /// The film chosen for each studio (TMDB movie ids).
    static func movieId(forTitle raw: String) -> Int? {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        if t.contains("pixar") { return 14160 }            // Là-haut
        if t.contains("dreamworks") { return 10191 }       // Dragons
        if t.contains("ghibli") { return 129 }             // Le Voyage de Chihiro
        if t.contains("marvel") { return 299534 }          // Avengers: Endgame
        if t.hasPrefix("dc") || t.contains("dcstudios") || t.contains("dccomics") { return 414906 }  // The Batman
        if t.contains("lucas") || t.contains("starwars") { return 11 }  // Star Wars : Un nouvel espoir
        if t.contains("illumination") { return 211672 }   // Les Minions
        if t.contains("universal") { return 329 }          // Jurassic Park
        if t.contains("warner") { return 671 }             // Harry Potter à l'école des sorciers (Steven)
        if t.contains("pathe") { return 1084736 }          // Le Comte de Monte-Cristo (2024)
        if t.contains("blum") { return 419430 }            // Get Out
        if t.contains("disney") { return 38757 }           // Raiponce
        return nil
    }

    @Published private(set) var urls: [Int: String] = [:]
    private var asked = Set<Int>()

    /// Steven's own choice of image for a studio (2026-10-30), fixed for good.
    static func pinnedURL(forTitle raw: String) -> String? {
        let t = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        let base = "https://image.tmdb.org/t/p/original/"
        if t.contains("pixar") { return base + "pBhZUIXrtwqcztVuiP39d5dHjJb.jpg" }
        if t.contains("dreamworks") { return base + "1pmXyN3sKeYoUhu5VBZiDU4BX21.jpg" }  // Steven
        if t.contains("blum") { return base + "wwARk7hRIfHfh2n2ubN6N7lvTne.jpg" }        // Steven
        if t.contains("ghibli") { return base + "r1Y5atOqXMiuwHHWV0vOKnxYaJD.jpg" }
        if t.contains("marvel") { return base + "r0jfRKIIKl34kZCeTxInYu5bVPf.jpg" }
        if t.hasPrefix("dc") || t.contains("dcstudios") || t.contains("dccomics") { return base + "tRS6jvPM9qPrrnx2KRp3ew96Yot.jpg" }
        if t.contains("lucas") || t.contains("starwars") { return base + "zqkmTXzjkAgXmEWLRsY4UpTWCeo.jpg" }
        if t.contains("illumination") { return base + "xQ3UtAgWbOfwXBBsBmJTimac8Ku.jpg" }
        if t.contains("universal") { return base + "yDouuYvRwt1Z8oAyi2ZplngPDrZ.jpg" }
        if t.contains("warner") { return base + "geApSZDagp7679GPkrK4cq7dfxI.jpg" }
        if t.contains("pathe") { return base + "bxT8jFcWNuWK5LmVo1oGhAm4dnZ.jpg" }
        if t.contains("disney") { return base + "3nZcBNylPokL1QwvTu1PaIaetun.jpg" }
        return nil
    }

    func url(forTitle title: String) -> String? {
        Self.pinnedURL(forTitle: title) ?? Self.movieId(forTitle: title).flatMap { urls[$0] }
    }

    /// Each studio's film backdrop asked once (cached for the session).
    func load(titles: [String]) {
        let key = TmdbSettingsRepository.shared.effectiveApiKey()
        guard !key.isEmpty else { return }
        for id in titles.filter({ Self.pinnedURL(forTitle: $0) == nil }).compactMap(Self.movieId(forTitle:)) where !asked.contains(id) {
            asked.insert(id)
            Task { [weak self] in
                guard let path = await Self.backdropPath(movie: id, apiKey: key) else { return }
                self?.urls[id] = "https://image.tmdb.org/t/p/original\(path)"
            }
        }
    }

    /// The film's best backdrop with no language (no text on it); else its best one.
    nonisolated private static func backdropPath(movie: Int, apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.themoviedb.org/3/movie/\(movie)/images?api_key=\(apiKey)&include_image_language=null,fr,en"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let backdrops = json["backdrops"] as? [[String: Any]], !backdrops.isEmpty else { return nil }
        func score(_ b: [String: Any]) -> Double { (b["vote_average"] as? Double) ?? 0 }
        let clean = backdrops.filter { ($0["iso_639_1"] as? String) == nil }
        var pool = clean.isEmpty ? backdrops : clean
        // Full HD at least (the banner spans the whole screen), when the film has one.
        let sharp = pool.filter { (($0["width"] as? Int) ?? 0) >= 1920 }
        if !sharp.isEmpty { pool = sharp }
        return pool.max { score($0) < score($1) }?["file_path"] as? String
    }
}
