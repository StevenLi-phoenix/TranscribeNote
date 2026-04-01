import Testing
import Foundation
@testable import TranscribeNote

struct AudioConfigTests {
    @Test func defaultConfig() {
        let config = AudioConfig.default
        #expect(config.sampleRate == 16_000)
        #expect(config.channels == 1)
        #expect(config.bufferDurationSeconds == 30)
    }

    @Test func bufferCapacity() {
        let config = AudioConfig.default
        #expect(config.bufferCapacity == 480_000)
    }

    @Test func customConfig() {
        let config = AudioConfig(sampleRate: 44_100, channels: 2, bufferDurationSeconds: 60)
        #expect(config.sampleRate == 44_100)
        #expect(config.channels == 2)
        #expect(config.bufferCapacity == 2_646_000)
    }
}
