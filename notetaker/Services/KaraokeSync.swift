import Foundation

/// Pure-logic helper for karaoke-style transcript sync.
/// Binary search to find the active segment at a given playback time.
nonisolated enum KaraokeSync {
    /// Find the index of the active segment via binary search.
    /// Returns the index of the last segment whose `start <= time`,
    /// or nil if `time` is before all segments.
    ///
    /// - Parameters:
    ///   - time: The current playback time.
    ///   - segments: Sorted array of (start, end) time ranges.
    /// - Returns: The index of the active segment, or nil.
    static func findActiveIndex(
        at time: TimeInterval,
        in segments: [(start: TimeInterval, end: TimeInterval)]
    ) -> Int? {
        guard !segments.isEmpty else { return nil }

        var lo = 0
        var hi = segments.count - 1
        var best: Int?

        while lo <= hi {
            let mid = (lo + hi) / 2
            if segments[mid].start <= time {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        return best
    }
}
