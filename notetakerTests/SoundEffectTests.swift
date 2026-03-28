import Testing
@testable import notetaker

@Suite("SoundEffectService")
struct SoundEffectTests {
    @Test func allEffects_haveSoundNames() {
        for effect in SoundEffectService.Effect.allCases {
            #expect(!effect.soundName.isEmpty)
        }
    }

    @Test func effectCount() {
        #expect(SoundEffectService.Effect.allCases.count == 4)
    }

    @Test func soundNames_areSystemSounds() {
        let validNames = ["Tink", "Pop", "Purr", "Funk", "Basso", "Blow", "Bottle", "Frog", "Glass", "Hero", "Morse", "Ping", "Submarine", "Sosumi"]
        for effect in SoundEffectService.Effect.allCases {
            #expect(validNames.contains(effect.soundName), "Sound '\(effect.soundName)' for \(effect) should be a valid system sound")
        }
    }

    @Test func recordingStart_soundName() {
        #expect(SoundEffectService.Effect.recordingStart.soundName == "Tink")
    }

    @Test func pause_soundName() {
        #expect(SoundEffectService.Effect.pause.soundName == "Pop")
    }

    @Test func resume_soundName() {
        #expect(SoundEffectService.Effect.resume.soundName == "Tink")
    }

    @Test func stop_soundName() {
        #expect(SoundEffectService.Effect.stop.soundName == "Purr")
    }
}
