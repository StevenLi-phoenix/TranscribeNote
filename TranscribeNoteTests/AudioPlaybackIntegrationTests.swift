import Testing
import Foundation
@testable import TranscribeNote

@Suite("AudioPlaybackService – Real File")
struct AudioPlaybackIntegrationTests {

    @Test func loadRealFileSetsDuration() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        #expect(service.duration > 0)
        #expect(service.playbackState == .idle)
        #expect(service.currentTime == 0)
        #expect(service.errorMessage == nil)
    }

    @Test func playAfterLoadChangesState() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        service.play()
        #expect(service.playbackState == .playing)
        service.stop()
    }

    @Test func pauseAfterPlayChangesState() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        service.play()
        service.pause()
        #expect(service.playbackState == .paused)
        service.stop()
    }

    @Test func seekAfterLoadUpdatesCurrentTime() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        service.seek(to: 10)
        #expect(abs(service.currentTime - 10) < 0.5)
    }

    @Test func seekClampsBeyondDuration() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        let dur = service.duration
        service.seek(to: dur + 100)
        #expect(service.currentTime <= dur)
    }

    @Test func stopAfterPlayResetsState() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        service.play()
        service.stop()
        #expect(service.playbackState == .idle)
        #expect(service.currentTime == 0)
        #expect(service.duration == 0)
    }

    @Test func togglePlayPauseRoundTrip() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)

        service.togglePlayPause()
        #expect(service.playbackState == .playing)

        service.togglePlayPause()
        #expect(service.playbackState == .paused)

        service.togglePlayPause()
        #expect(service.playbackState == .playing)

        service.stop()
    }

    @Test func reloadDifferentFileResetsPrevious() throws {
        let service = AudioPlaybackService()
        let url = try sampleSpeechURL()
        service.load(url: url)
        service.play()
        #expect(service.isPlaying)

        // Reload same file — should reset
        service.load(url: url)
        #expect(service.playbackState == .idle)
        #expect(service.currentTime == 0)
        #expect(service.duration > 0)
    }
}
