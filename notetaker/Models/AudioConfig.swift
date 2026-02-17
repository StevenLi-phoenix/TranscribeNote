import Foundation

nonisolated struct AudioConfig: Sendable {
    let sampleRate: Double
    let channels: UInt32
    let bufferDurationSeconds: Int

    static let `default` = AudioConfig(
        sampleRate: 16_000,
        channels: 1,
        bufferDurationSeconds: 30
    )

    var bufferCapacity: Int {
        Int(sampleRate) * bufferDurationSeconds
    }
}
