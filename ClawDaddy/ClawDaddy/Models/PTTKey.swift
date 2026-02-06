import AppKit

struct PTTKey: Codable, Equatable {
    let keyCode: UInt16
    let isModifier: Bool
    let modifierFlag: UInt?
    let displayName: String

    static let defaultKey = PTTKey(
        keyCode: 59,
        isModifier: true,
        modifierFlag: NSEvent.ModifierFlags.control.rawValue,
        displayName: "Left Control"
    )

    var nsModifierFlag: NSEvent.ModifierFlags? {
        guard let raw = modifierFlag else { return nil }
        return NSEvent.ModifierFlags(rawValue: raw)
    }

    static func displayName(forKeyCode keyCode: UInt16) -> String {
        keyCodeNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyCodeNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Escape",
        // Modifier keys
        54: "Right Command", 55: "Left Command",
        56: "Left Shift", 57: "Caps Lock", 58: "Left Option",
        59: "Left Control", 60: "Right Shift", 61: "Right Option",
        62: "Right Control",
        // Function keys
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15",
        118: "F4", 120: "F2", 122: "F1",
        // Navigation
        115: "Home", 116: "Page Up", 117: "Forward Delete",
        119: "End", 121: "Page Down",
        123: "Left Arrow", 124: "Right Arrow",
        125: "Down Arrow", 126: "Up Arrow",
    ]

    static let modifierKeyCodes: [UInt16: NSEvent.ModifierFlags] = [
        54: .command, 55: .command,
        56: .shift, 60: .shift,
        58: .option, 61: .option,
        59: .control, 62: .control,
    ]

    static let rejectedKeyCodes: Set<UInt16> = [57, 63] // Caps Lock, Fn
}
