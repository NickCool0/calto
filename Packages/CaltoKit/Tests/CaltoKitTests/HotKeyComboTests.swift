import Carbon.HIToolbox
import Foundation
import Testing
import CaltoKit

struct HotKeyComboTests {
    @Test("Default is ⌃⌥⌘C")
    func defaultCombo() {
        let combo = HotKeyCombo.default
        #expect(combo.keyCode == UInt32(kVK_ANSI_C))
        #expect(combo.modifierSymbols == "⌃⌥⌘")
        #expect(combo.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test("Each modifier maps to its Carbon flag", arguments: [
        (HotKeyCombo.Modifiers.control, controlKey),
        (.option, optionKey),
        (.shift, shiftKey),
        (.command, cmdKey),
    ])
    func carbonMapping(modifier: HotKeyCombo.Modifiers, carbon: Int) {
        #expect(HotKeyCombo(keyCode: 0, modifiers: modifier).carbonModifiers == UInt32(carbon))
    }

    @Test("Symbols follow the macOS order ⌃⌥⇧⌘ regardless of how the set was built")
    func symbolOrder() {
        let combo = HotKeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(combo.modifierSymbols == "⌃⌥⇧⌘")
    }

    @Test("Display string and menu key equivalent")
    func display() {
        #expect(HotKeyCombo.default.displayString == "⌃⌥⌘C")
        #expect(HotKeyCombo.default.keyCharacter == "c")
        #expect(HotKeyCombo(keyCode: UInt32(kVK_ANSI_7), modifiers: .option).displayString == "⌥7")
        #expect(HotKeyCombo(keyCode: UInt32(kVK_F5), modifiers: .command).keyCharacter == nil)
    }

    @Test("Survives a JSON round trip (stored in settings)")
    func codable() throws {
        let combo = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.option, .shift])
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
    }
}
