import Foundation
import Testing
@testable import notetaker

@Suite("WaveformExtractor")
struct WaveformExtractorTests {
    @Test func downsampleBasic() {
        let input: [Float] = [0.5, 0.5, 1.0, 1.0, 0.0, 0.0]
        let result = WaveformExtractor.downsample(input, to: 3)
        #expect(result.count == 3)
        for val in result {
            #expect(val >= 0 && val <= 1)
        }
    }

    @Test func downsampleEmpty() {
        let result = WaveformExtractor.downsample([], to: 100)
        #expect(result.isEmpty)
    }

    @Test func downsampleZeroTarget() {
        let result = WaveformExtractor.downsample([1.0, 0.5], to: 0)
        #expect(result.isEmpty)
    }

    @Test func downsampleSilence() {
        let input = [Float](repeating: 0, count: 100)
        let result = WaveformExtractor.downsample(input, to: 10)
        #expect(result.count == 10)
        for val in result {
            #expect(val == 0)
        }
    }

    @Test func downsamplePreservesRelativeAmplitudes() {
        var input = [Float](repeating: 1.0, count: 50)
        input += [Float](repeating: 0.1, count: 50)
        let result = WaveformExtractor.downsample(input, to: 2)
        #expect(result.count == 2)
        #expect(result[0] > result[1])
    }

    @Test func downsampleTargetLargerThanInput() {
        let input: [Float] = [0.5, 1.0]
        let result = WaveformExtractor.downsample(input, to: 100)
        #expect(result.count == 2)
    }

    @Test func downsampleNormalizesToOne() {
        let input: [Float] = [0.3, 0.3, 0.3, 0.3]
        let result = WaveformExtractor.downsample(input, to: 2)
        let maxVal = result.max() ?? 0
        #expect(maxVal > 0.99 && maxVal <= 1.0)
    }

    @Test func waveformDataEmptyIsValid() {
        let empty = WaveformExtractor.WaveformData.empty
        #expect(empty.samples.isEmpty)
        #expect(empty.duration == 0)
    }

    @Test func downsampleSingleSample() {
        let result = WaveformExtractor.downsample([0.7], to: 1)
        #expect(result.count == 1)
        #expect(result[0] > 0.99)
    }

    @Test func downsampleLargeInput() {
        let input = (0..<10000).map { Float(sin(Double($0) * 0.01)) }
        let result = WaveformExtractor.downsample(input, to: 100)
        #expect(result.count == 100)
        for val in result {
            #expect(val >= 0 && val <= 1)
        }
    }
}
