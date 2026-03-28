import Foundation
import Testing
@testable import notetaker

@Suite("FocusModeService", .serialized)
struct FocusModeServiceTests {
    @Test func currentStatusDoesNotCrash() {
        // Just verify the API call works without crashing
        let status = FocusModeService.currentStatus()
        // Status could be any value depending on system state
        switch status {
        case .enabled, .disabled, .unknown:
            break // All valid
        }
    }

    @Test func focusStatusEnumCoverage() {
        // Verify all enum cases exist
        let cases: [FocusModeService.FocusStatus] = [.enabled, .disabled, .unknown]
        #expect(cases.count == 3)
    }

    @Test func reminderEnabledDefaultsToTrue() {
        // Clean slate -- if key doesn't exist, should default to true
        let defaults = UserDefaults.standard
        let key = "focusReminderEnabled"
        let original = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defaults.synchronize()

        #expect(FocusModeService.isReminderEnabled == true)

        // Restore
        if let original {
            defaults.set(original, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    @Test func reminderDisabledWhenSettingOff() {
        let defaults = UserDefaults.standard
        let key = "focusReminderEnabled"
        let original = defaults.object(forKey: key)

        defaults.set(false, forKey: key)
        #expect(FocusModeService.isReminderEnabled == false)
        #expect(!FocusModeService.shouldShowReminder())

        // Restore
        if let original {
            defaults.set(original, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    @Test func shouldShowReminderRespectsDisabledSetting() {
        let defaults = UserDefaults.standard
        let key = "focusReminderEnabled"
        let original = defaults.object(forKey: key)

        defaults.set(false, forKey: key)
        // When reminders are disabled, should never show
        #expect(!FocusModeService.shouldShowReminder())

        // Restore
        if let original {
            defaults.set(original, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    @Test func requestAuthorizationCompletes() async {
        // Just verify it completes without hanging
        let result = await FocusModeService.requestAuthorization()
        // Result depends on system state -- just verify it returns
        _ = result
    }
}
