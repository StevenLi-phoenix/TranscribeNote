import AVFoundation

enum PlaybackState {
    case idle
    case playing
    case paused
}

@Observable
final class AudioPlaybackService: NSObject, AVAudioPlayerDelegate {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var isPlaying: Bool { playbackState == .playing }

    func load(url: URL) {
        stop()
        errorMessage = nil
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            self.player = audioPlayer
            self.duration = audioPlayer.duration
            self.currentTime = 0
            self.playbackState = .idle
        } catch {
            self.player = nil
            self.duration = 0
            self.errorMessage = "Failed to load audio: \(error.localizedDescription)"
        }
    }

    func play() {
        guard let player, playbackState != .playing else { return }
        player.play()
        playbackState = .playing
        startTimer()
    }

    func pause() {
        guard let player, playbackState == .playing else { return }
        player.pause()
        playbackState = .paused
        stopTimer()
    }

    func togglePlayPause() {
        switch playbackState {
        case .idle:
            play()
        case .playing:
            pause()
        case .paused:
            play()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        playbackState = .idle
        currentTime = 0
        duration = 0
        errorMessage = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopTimer()
            self.player?.currentTime = 0
            self.playbackState = .idle
            self.currentTime = 0
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
