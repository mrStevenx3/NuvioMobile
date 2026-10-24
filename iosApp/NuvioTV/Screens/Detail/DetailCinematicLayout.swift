import CoreGraphics
import Foundation
import SharedCore

// MARK: - Start Over

nonisolated enum DetailStartOver {
    /// Series: the primary action carries a resume position, or the primary action's episode has a
    /// resumable entry with progress (review r1 #3: Trakt/Simkl rows carry only a percentage, which
    /// Play already resumes). Movie: a not-yet-finished entry with a saved position or a progress
    /// fraction (percentage-only rows have `lastPositionMs == 0`).
    static func isAvailable(isSeries: Bool, seriesResumePositionMs: Int64?,
                            seriesEntryFraction: Float? = nil, seriesEntryResumable: Bool = false,
                            movieEntryPositionMs: Int64?, movieEntryFraction: Float? = nil,
                            movieEntryResumable: Bool) -> Bool {
        if isSeries {
            if (seriesResumePositionMs ?? 0) > 0 { return true }
            return seriesEntryResumable && (seriesEntryFraction ?? 0) > 0
        }
        guard movieEntryResumable else { return false }
        return (movieEntryPositionMs ?? 0) > 0 || (movieEntryFraction ?? 0) > 0
    }
}

