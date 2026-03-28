import Foundation
import Testing
@testable import notetaker

@Suite("SystemAudioCaptureService")
struct SystemAudioCaptureServiceTests {
    @Test func audioSourceEnumCases() {
        #expect(AudioSource.allCases.count == 3)
        #expect(AudioSource.microphone.rawValue == "microphone")
        #expect(AudioSource.systemAudio.rawValue == "systemAudio")
        #expect(AudioSource.both.rawValue == "both")
    }

    @Test func audioSourceDisplayNames() {
        #expect(AudioSource.microphone.displayName == "Microphone")
        #expect(AudioSource.systemAudio.displayName == "System Audio")
        #expect(AudioSource.both.displayName == "Both")
    }

    @Test func audioSourceFromRawValue() {
        #expect(AudioSource(rawValue: "microphone") == .microphone)
        #expect(AudioSource(rawValue: "systemAudio") == .systemAudio)
        #expect(AudioSource(rawValue: "both") == .both)
        #expect(AudioSource(rawValue: "invalid") == nil)
    }

    @Test func serviceInitialState() {
        let service = SystemAudioCaptureService()
        #expect(!service.isCapturing)
    }

    @Test func errorDescriptions() {
        let errors: [SystemAudioCaptureService.SystemAudioError] = [
            .noDisplayAvailable, .permissionDenied, .captureAlreadyRunning,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func permissionCheckCompletes() async {
        // Just verify it doesn't hang — result depends on system state
        let result = await SystemAudioCaptureService.checkPermission()
        _ = result
    }

    @Test func stopCaptureWhenNotRunning() async {
        let service = SystemAudioCaptureService()
        // Should not crash when stopping without starting
        await service.stopCapture()
        #expect(!service.isCapturing)
    }

    @Test func audioSourceDefaultIsMicrophone() {
        let defaults = UserDefaults.standard
        let key = "audioSource"
        let original = defaults.string(forKey: key)
        defaults.removeObject(forKey: key)

        let source = AudioSource(rawValue: defaults.string(forKey: key) ?? AudioSource.microphone.rawValue)
        #expect(source == .microphone)

        // Restore
        if let original {
            defaults.set(original, forKey: key)
        }
    }
}
