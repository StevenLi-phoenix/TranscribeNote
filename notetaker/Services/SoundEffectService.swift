import Cocoa
import os

/// Plays subtle sound effects for recording state transitions.
nonisolated enum SoundEffectService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SoundEffect")

    enum Effect: String, CaseIterable {
        case recordingStart
        case pause
        case resume
        case stop

        /// System sound name for this effect.
        var soundName: String {
            switch self {
            case .recordingStart: "Tink"
            case .pause: "Pop"
            case .resume: "Tink"
            case .stop: "Purr"
            }
        }
    }

    /// Play a sound effect if enabled in settings.
    @MainActor
    static func play(_ effect: Effect) {
        guard UserDefaults.standard.bool(forKey: "soundEffectsEnabled") else { return }

        if let sound = NSSound(named: effect.soundName) {
            sound.volume = 0.6
            sound.play()
            logger.debug("Played sound effect: \(effect.rawValue) (\(effect.soundName))")
        } else {
            logger.warning("Sound not found: \(effect.soundName)")
        }
    }
}
