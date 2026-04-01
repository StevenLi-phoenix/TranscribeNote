import Testing
import Foundation
@testable import TranscribeNote

struct AudioLevelMeterTests {
    @Test func initialLevelIsZero() {
        let meter = AudioLevelMeter()
        #expect(meter.level == 0)
    }

    @Test func updateSetsLevel() {
        let meter = AudioLevelMeter()
        meter.update(0.75)
        #expect(meter.level == 0.75)
    }

    @Test func resetClearsLevel() {
        let meter = AudioLevelMeter()
        meter.update(0.5)
        meter.reset()
        #expect(meter.level == 0)
    }
}
