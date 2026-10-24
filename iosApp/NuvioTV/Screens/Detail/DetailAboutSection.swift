import SwiftUI

/// beta.19-rc1 verdict (D1, BUG-137): the Status value. TMDB's status words ("Released", "Ended", …)
/// reach the page as English text, which stayed English in Steven's French screenshot ("Statut
/// Released"). Known words map to a `String(localized:)` key so they translate with the rest of the
/// page; an unknown value (an add-on's own wording) is shown as given, and a blank one is no row.
nonisolated enum DetailStatusText {
    /// Matching is case-insensitive and ignores surrounding whitespace. TMDB's movie statuses are
    /// Rumored, Planned, In Production, Post Production, Released and Canceled; its series statuses
    /// are Returning Series, Planned, In Production, Ended, Canceled and Pilot. "Continuing" is
    /// the word several add-ons and TVDB use for a running series; "Cancelled" is the British spelling.
    static func localized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Own `detail.status.*` keys, never the bare English word: the catalog populate script
        // harvests translations from the phone app by English text, and the phone app uses
        // "Released" as a row LABEL (fr "Date de sortie"), so a bare key would pick up that label as
        // the status value. The catalog carries an explicit English value for each key.
        switch trimmed.lowercased() {
        case "released": return String(localized: "detail.status.released", defaultValue: "Released")
        case "ended": return String(localized: "detail.status.ended", defaultValue: "Ended")
        case "returning series": return String(localized: "detail.status.returningSeries", defaultValue: "Returning Series")
        case "continuing": return String(localized: "detail.status.continuing", defaultValue: "Continuing")
        case "canceled", "cancelled": return String(localized: "detail.status.canceled", defaultValue: "Canceled")
        case "in production": return String(localized: "detail.status.inProduction", defaultValue: "In Production")
        case "planned": return String(localized: "detail.status.planned", defaultValue: "Planned")
        case "post production": return String(localized: "detail.status.postProduction", defaultValue: "Post Production")
        case "rumored": return String(localized: "detail.status.rumored", defaultValue: "Rumored")
        case "pilot": return String(localized: "detail.status.pilot", defaultValue: "Pilot")
        default: return trimmed
        }
    }
}

