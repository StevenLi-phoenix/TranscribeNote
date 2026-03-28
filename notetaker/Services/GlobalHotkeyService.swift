import Cocoa
import os

/// Manages a system-wide keyboard shortcut for toggling recording.
@MainActor
final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "GlobalHotkey")

    /// Callback when hotkey is triggered
    var onToggleRecording: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Default: Ctrl+Option+R
    static let defaultKeyCode: UInt16 = 15 // R key
    static let defaultModifiers: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue

    private init() {}

    /// Register global and local hotkey monitors
    func register() {
        unregister() // Clear any existing monitors

        guard UserDefaults.standard.bool(forKey: "globalHotkeyEnabled") else {
            Self.logger.info("Global hotkey disabled, skipping registration")
            return
        }

        let keyCode = UInt16(UserDefaults.standard.integer(forKey: "globalHotkeyKeyCode"))
        let modRaw = UInt(UserDefaults.standard.integer(forKey: "globalHotkeyModifiers"))

        // Use defaults if not configured
        let targetKeyCode = keyCode == 0 ? Self.defaultKeyCode : keyCode
        let targetMods = modRaw == 0 ? Self.defaultModifiers : modRaw
        let targetModFlags = NSEvent.ModifierFlags(rawValue: targetMods).intersection(.deviceIndependentFlagsMask)

        // Global monitor (when app is NOT focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == targetKeyCode && eventMods == targetModFlags {
                Task { @MainActor [weak self] in
                    self?.onToggleRecording?()
                }
            }
        }

        // Local monitor (when app IS focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == targetKeyCode && eventMods == targetModFlags {
                Task { @MainActor [weak self] in
                    self?.onToggleRecording?()
                }
                return nil // Consume the event
            }
            return event
        }

        Self.logger.info("Global hotkey registered: keyCode=\(targetKeyCode), modifiers=\(targetMods)")
    }

    /// Unregister all monitors
    func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

/// Utilities for displaying hotkey information
nonisolated enum HotkeyDisplayHelper {
    /// Convert modifier flags to display string (e.g., "⌃⌥")
    static func modifierSymbols(_ rawValue: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols
    }

    /// Convert key code to display name
    static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
            28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }

    /// Full display string like "⌃⌥R"
    static func displayString(keyCode: UInt16, modifiers: UInt) -> String {
        modifierSymbols(modifiers) + keyName(for: keyCode)
    }
}
