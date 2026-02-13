import Testing
import Foundation
@testable import notetaker

@Suite("AudioPlaybackService")
struct AudioPlaybackServiceTests {

    @Test func initialState() {
        let service = AudioPlaybackService()
        #expect(service.playbackState == .idle)
        #expect(service.currentTime == 0)
        #expect(service.duration == 0)
        #expect(service.isPlaying == false)
    }

    @Test func stopResetsState() {
        let service = AudioPlaybackService()
        service.stop()
        #expect(service.playbackState == .idle)
        #expect(service.currentTime == 0)
        #expect(service.duration == 0)
    }

    @Test func seekClampsToBounds() {
        let service = AudioPlaybackService()
        // Without a loaded file, seek should be a no-op (no player)
        service.seek(to: -10)
        #expect(service.currentTime == 0)
        service.seek(to: 999)
        #expect(service.currentTime == 0)
    }

    @Test func togglePlayPauseFromIdle() {
        let service = AudioPlaybackService()
        // Without a loaded file, play won't actually start (no player)
        service.togglePlayPause()
        // State stays idle because there's no AVAudioPlayer
        #expect(service.playbackState == .idle)
    }

    @Test func playWithoutLoadIsNoop() {
        let service = AudioPlaybackService()
        service.play()
        #expect(service.playbackState == .idle)
    }

    @Test func pauseWithoutPlayIsNoop() {
        let service = AudioPlaybackService()
        service.pause()
        #expect(service.playbackState == .idle)
    }

    @Test func loadInvalidURLKeepsIdle() {
        let service = AudioPlaybackService()
        let badURL = URL(fileURLWithPath: "/nonexistent/file.wav")
        service.load(url: badURL)
        #expect(service.playbackState == .idle)
        #expect(service.duration == 0)
        #expect(service.errorMessage != nil)
    }
}
