import AudioToolbox
import os

/// Plays subtle sound effects for recording state transitions.
/// Uses AudioServicesPlayAlertSound instead of NSSound to avoid:
/// - NSSound stale cache bug (Apple Bug #12506583)
/// - NSSound crashes on macOS Sonoma+ (AudioToolbox/MEDeviceStreamClient)
/// - Wrong audio device routing (NSSound uses default output, not alert device)
@MainActor
final class SoundEffectService {
    static let shared = SoundEffectService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SoundEffect")

    enum Effect: String, CaseIterable, Sendable {
        case recordingStart
        case pause
        case resume
        case stop

        /// Path to system sound file.
        var soundURL: URL? {
            let name: String
            switch self {
            case .recordingStart: name = "Purr"
            case .pause:          name = "Pop"
            case .resume:         name = "Tink"
            case .stop:           name = "Tink"
            }
            return URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        }
    }

    private init() {}

    /// Play a sound effect if enabled in settings.
    /// Uses AudioServicesPlayAlertSound — fire-and-forget, plays on system alert device,
    /// respects system alert volume, no ARC retention needed.
    static func play(_ effect: Effect) {
        guard UserDefaults.standard.bool(forKey: "soundEffectsEnabled") else { return }

        guard let url = effect.soundURL else {
            logger.warning("Sound URL not found for: \(effect.rawValue)")
            return
        }

        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else {
            logger.error("Failed to create system sound: \(status)")
            return
        }

        AudioServicesPlayAlertSound(soundID)
        logger.debug("Played sound effect: \(effect.rawValue)")

        // Dispose after playback completes
        AudioServicesAddSystemSoundCompletion(soundID, nil, nil, { id, _ in
            AudioServicesDisposeSystemSoundID(id)
        }, nil)
    }
}
