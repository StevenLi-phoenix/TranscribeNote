import Testing
import Cocoa
@testable import notetaker

@Suite("Global Hotkey")
struct GlobalHotkeyTests {
    @Test func modifierSymbols_controlOption() {
        let mods = NSEvent.ModifierFlags([.control, .option]).rawValue
        let symbols = HotkeyDisplayHelper.modifierSymbols(UInt(mods))
        #expect(symbols.contains("⌃"))
        #expect(symbols.contains("⌥"))
    }

    @Test func modifierSymbols_commandShift() {
        let mods = NSEvent.ModifierFlags([.command, .shift]).rawValue
        let symbols = HotkeyDisplayHelper.modifierSymbols(UInt(mods))
        #expect(symbols.contains("⌘"))
        #expect(symbols.contains("⇧"))
    }

    @Test func modifierSymbols_empty() {
        #expect(HotkeyDisplayHelper.modifierSymbols(0) == "")
    }

    @Test func keyName_commonKeys() {
        #expect(HotkeyDisplayHelper.keyName(for: 15) == "R")
        #expect(HotkeyDisplayHelper.keyName(for: 0) == "A")
        #expect(HotkeyDisplayHelper.keyName(for: 49) == "Space")
        #expect(HotkeyDisplayHelper.keyName(for: 53) == "Escape")
    }

    @Test func keyName_unknownKey() {
        #expect(HotkeyDisplayHelper.keyName(for: 255).hasPrefix("Key"))
    }

    @MainActor @Test func displayString_defaultHotkey() {
        let display = HotkeyDisplayHelper.displayString(
            keyCode: GlobalHotkeyService.defaultKeyCode,
            modifiers: UInt(GlobalHotkeyService.defaultModifiers)
        )
        #expect(display.contains("R"))
        #expect(display.contains("⌃"))
        #expect(display.contains("⌥"))
    }

    @Test func displayString_format() {
        let display = HotkeyDisplayHelper.displayString(
            keyCode: 12,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )
        #expect(display == "⌘Q")
    }

    @Test func modifierSymbols_order() {
        // Should be ⌃⌥⇧⌘ order
        let mods = NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue
        let symbols = HotkeyDisplayHelper.modifierSymbols(UInt(mods))
        let controlIdx = symbols.firstIndex(of: "⌃")!
        let optionIdx = symbols.firstIndex(of: "⌥")!
        let shiftIdx = symbols.firstIndex(of: "⇧")!
        let cmdIdx = symbols.firstIndex(of: "⌘")!
        #expect(controlIdx < optionIdx)
        #expect(optionIdx < shiftIdx)
        #expect(shiftIdx < cmdIdx)
    }

    @Test func keyName_allLetters() {
        #expect(HotkeyDisplayHelper.keyName(for: 1) == "S")
        #expect(HotkeyDisplayHelper.keyName(for: 13) == "W")
        #expect(HotkeyDisplayHelper.keyName(for: 46) == "M")
    }

    @Test func keyName_numbers() {
        #expect(HotkeyDisplayHelper.keyName(for: 18) == "1")
        #expect(HotkeyDisplayHelper.keyName(for: 29) == "0")
    }

    @Test func keyName_specialKeys() {
        #expect(HotkeyDisplayHelper.keyName(for: 36) == "Return")
        #expect(HotkeyDisplayHelper.keyName(for: 48) == "Tab")
        #expect(HotkeyDisplayHelper.keyName(for: 51) == "Delete")
    }

    @Test func keyName_arrowKeys() {
        #expect(HotkeyDisplayHelper.keyName(for: 123) == "←")
        #expect(HotkeyDisplayHelper.keyName(for: 124) == "→")
        #expect(HotkeyDisplayHelper.keyName(for: 125) == "↓")
        #expect(HotkeyDisplayHelper.keyName(for: 126) == "↑")
    }

    @Test func modifierSymbols_singleModifier() {
        #expect(HotkeyDisplayHelper.modifierSymbols(NSEvent.ModifierFlags.control.rawValue) == "⌃")
        #expect(HotkeyDisplayHelper.modifierSymbols(NSEvent.ModifierFlags.option.rawValue) == "⌥")
        #expect(HotkeyDisplayHelper.modifierSymbols(NSEvent.ModifierFlags.shift.rawValue) == "⇧")
        #expect(HotkeyDisplayHelper.modifierSymbols(NSEvent.ModifierFlags.command.rawValue) == "⌘")
    }

    @MainActor @Test func defaultKeyCode_isR() {
        #expect(GlobalHotkeyService.defaultKeyCode == 15)
    }

    @MainActor @Test func defaultModifiers_isControlOption() {
        let expected = NSEvent.ModifierFlags([.control, .option]).rawValue
        #expect(GlobalHotkeyService.defaultModifiers == expected)
    }
}
