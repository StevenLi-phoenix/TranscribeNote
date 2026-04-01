import Testing
import Foundation
@testable import TranscribeNote

@Suite("SoundEffectService")
struct SoundEffectTests {
    @Test func allEffects_haveSoundURLs() {
        for effect in SoundEffectService.Effect.allCases {
            #expect(effect.soundURL != nil)
        }
    }

    @Test func effectCount() {
        #expect(SoundEffectService.Effect.allCases.count == 4)
    }

    @Test func soundURLs_pointToSystemSounds() {
        for effect in SoundEffectService.Effect.allCases {
            let url = effect.soundURL!
            #expect(url.path().hasPrefix("/System/Library/Sounds/"))
            #expect(url.path().hasSuffix(".aiff"))
        }
    }

    @Test func recordingStart_soundURL() {
        #expect(SoundEffectService.Effect.recordingStart.soundURL?.lastPathComponent == "Purr.aiff")
    }

    @Test func pause_soundURL() {
        #expect(SoundEffectService.Effect.pause.soundURL?.lastPathComponent == "Pop.aiff")
    }

    @Test func resume_soundURL() {
        #expect(SoundEffectService.Effect.resume.soundURL?.lastPathComponent == "Tink.aiff")
    }

    @Test func stop_soundURL() {
        #expect(SoundEffectService.Effect.stop.soundURL?.lastPathComponent == "Tink.aiff")
    }
}
