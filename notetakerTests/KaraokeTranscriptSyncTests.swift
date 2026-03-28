import Foundation
import Testing
@testable import notetaker

@Suite("KaraokeSync")
struct KaraokeTranscriptSyncTests {

    @Test func findActiveIndex_emptySegments() {
        #expect(KaraokeSync.findActiveIndex(at: 5.0, in: []) == nil)
    }

    @Test func findActiveIndex_exactStart() {
        let segments: [(start: TimeInterval, end: TimeInterval)] = [
            (0, 5), (5, 10), (10, 15),
        ]
        #expect(KaraokeSync.findActiveIndex(at: 0.0, in: segments) == 0)
        #expect(KaraokeSync.findActiveIndex(at: 5.0, in: segments) == 1)
        #expect(KaraokeSync.findActiveIndex(at: 10.0, in: segments) == 2)
    }

    @Test func findActiveIndex_midSegment() {
        let segments: [(start: TimeInterval, end: TimeInterval)] = [
            (0, 5), (5, 10), (10, 15),
        ]
        #expect(KaraokeSync.findActiveIndex(at: 2.5, in: segments) == 0)
        #expect(KaraokeSync.findActiveIndex(at: 7.5, in: segments) == 1)
        #expect(KaraokeSync.findActiveIndex(at: 12.0, in: segments) == 2)
    }

    @Test func findActiveIndex_gap() {
        // Gap between 5 and 8
        let segments: [(start: TimeInterval, end: TimeInterval)] = [
            (0, 5), (8, 12),
        ]
        // In the gap - returns last segment before gap
        #expect(KaraokeSync.findActiveIndex(at: 6.0, in: segments) == 0)
    }

    @Test func findActiveIndex_beforeFirstSegment() {
        let segments: [(start: TimeInterval, end: TimeInterval)] = [
            (5, 10), (10, 15),
        ]
        #expect(KaraokeSync.findActiveIndex(at: 2.0, in: segments) == nil)
    }

    @Test func findActiveIndex_afterLastSegment() {
        let segments: [(start: TimeInterval, end: TimeInterval)] = [
            (0, 5), (5, 10),
        ]
        #expect(KaraokeSync.findActiveIndex(at: 20.0, in: segments) == 1)
    }

    @Test func findActiveIndex_singleSegment() {
        let segments: [(start: TimeInterval, end: TimeInterval)] = [(3, 8)]
        #expect(KaraokeSync.findActiveIndex(at: 3.0, in: segments) == 0)
        #expect(KaraokeSync.findActiveIndex(at: 5.0, in: segments) == 0)
        #expect(KaraokeSync.findActiveIndex(at: 1.0, in: segments) == nil)
    }

    @Test func findActiveIndex_manySegments() {
        // Stress test with many segments to exercise binary search
        let segments: [(start: TimeInterval, end: TimeInterval)] = (0..<100).map {
            (start: Double($0) * 10, end: Double($0) * 10 + 8)
        }
        #expect(KaraokeSync.findActiveIndex(at: 0.0, in: segments) == 0)
        #expect(KaraokeSync.findActiveIndex(at: 505.0, in: segments) == 50)
        #expect(KaraokeSync.findActiveIndex(at: 999.0, in: segments) == 99)
    }
}
