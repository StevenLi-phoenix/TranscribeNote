import AVFoundation
import os

enum PlaybackState {
    case idle
    case playing
    case paused
}

@Observable
final class AudioPlaybackService: NSObject, AVAudioPlayerDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "AudioPlayback")

    private(set) var playbackState: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    // Multi-clip state
    private var clips: [URL] = []
    private var clipDurations: [TimeInterval] = []
    private var clipStartOffsets: [TimeInterval] = []  // cumulative start time of each clip
    private var currentClipIndex: Int = 0

    var isPlaying: Bool { playbackState == .playing }

    /// Load a single audio file (backward compatible).
    func load(url: URL) {
        loadMultiple(urls: [url])
    }

    /// Load multiple audio clips for sequential playback.
    /// First clip is loaded synchronously for immediate playback readiness.
    /// Remaining clip durations are computed asynchronously to avoid blocking the main thread.
    func loadMultiple(urls: [URL]) {
        stop()
        errorMessage = nil
        clips = urls
        clipDurations = []
        clipStartOffsets = []

        self.currentTime = 0
        self.currentClipIndex = 0

        guard !urls.isEmpty else { return }

        // Load first clip synchronously — get its duration from the player
        loadClip(at: 0)
        let firstDuration = player?.duration ?? 0
        clipDurations = [firstDuration]
        clipStartOffsets = [0]
        duration = firstDuration

        // For single-clip case (most common), we're done synchronously
        guard urls.count > 1 else { return }

        // Compute remaining clip durations asynchronously
        let capturedURLs = urls
        Task.detached(priority: .userInitiated) {
            var durations: [TimeInterval] = [firstDuration]
            for i in 1..<capturedURLs.count {
                let asset = AVURLAsset(url: capturedURLs[i])
                let assetDuration: TimeInterval
                do {
                    let cmDuration = try await asset.load(.duration)
                    assetDuration = cmDuration.seconds.isFinite ? cmDuration.seconds : 0
                } catch {
                    Self.logger.error("Failed to read clip duration \(capturedURLs[i].lastPathComponent): \(error.localizedDescription)")
                    assetDuration = 0
                }
                durations.append(assetDuration)
            }
            // Build cumulative offsets
            let finalDurations = durations
            var offsets: [TimeInterval] = []
            var total: TimeInterval = 0
            for d in finalDurations {
                offsets.append(total)
                total += d
            }
            let finalOffsets = offsets
            let finalTotal = total
            await MainActor.run {
                guard self.clips == capturedURLs else { return }
                self.clipDurations = finalDurations
                self.clipStartOffsets = finalOffsets
                self.duration = finalTotal
            }
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
        let clamped = max(0, min(time, duration))

        // Find which clip this time falls into
        let (clipIndex, localTime) = mapToClip(cumulativeTime: clamped)

        if clipIndex != currentClipIndex {
            let wasPlaying = playbackState == .playing
            loadClip(at: clipIndex)
            player?.currentTime = localTime
            if wasPlaying {
                player?.play()
            }
        } else {
            player?.currentTime = localTime
        }
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
        clips = []
        clipDurations = []
        clipStartOffsets = []
        currentClipIndex = 0
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.advanceToNextClip()
        }
    }

    // MARK: - Multi-clip Helpers

    /// Load a specific clip by index, preparing it for playback.
    private func loadClip(at index: Int) {
        guard index >= 0, index < clips.count else { return }
        currentClipIndex = index
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: clips[index])
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            self.player = audioPlayer
        } catch {
            Self.logger.error("Failed to load clip \(index): \(error.localizedDescription)")
            self.player = nil
            self.errorMessage = "Failed to load audio clip: \(error.localizedDescription)"
        }
    }

    /// Advance to the next clip after current one finishes, or stop if last clip.
    private func advanceToNextClip() {
        let nextIndex = currentClipIndex + 1
        if nextIndex < clips.count {
            loadClip(at: nextIndex)
            player?.play()
            // Timer continues running, currentTime will update from updateCurrentTime()
        } else {
            // All clips finished
            stopTimer()
            playbackState = .idle
            currentTime = 0
            currentClipIndex = 0
            if !clips.isEmpty {
                loadClip(at: 0)
            }
        }
    }

    /// Map a cumulative time to (clipIndex, localTime).
    private func mapToClip(cumulativeTime: TimeInterval) -> (Int, TimeInterval) {
        guard !clipStartOffsets.isEmpty else { return (0, cumulativeTime) }
        for i in stride(from: clipStartOffsets.count - 1, through: 0, by: -1) {
            if cumulativeTime >= clipStartOffsets[i] {
                return (i, cumulativeTime - clipStartOffsets[i])
            }
        }
        return (0, cumulativeTime)
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
        t.tolerance = 0.05
        timer = t
    }

    private func updateCurrentTime() {
        guard let player else { return }
        let offset = currentClipIndex < clipStartOffsets.count ? clipStartOffsets[currentClipIndex] : 0
        currentTime = offset + player.currentTime
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
