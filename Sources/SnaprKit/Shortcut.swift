import Carbon.HIToolbox

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(key: Int, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        var flags = 0
        if command { flags |= cmdKey }
        if shift { flags |= shiftKey }
        if option { flags |= optionKey }
        if control { flags |= controlKey }
        self.init(keyCode: UInt32(key), modifiers: UInt32(flags))
    }

    public var hasCommand: Bool { modifiers & UInt32(cmdKey) != 0 }
    public var hasShift: Bool { modifiers & UInt32(shiftKey) != 0 }
    public var hasOption: Bool { modifiers & UInt32(optionKey) != 0 }
    public var hasControl: Bool { modifiers & UInt32(controlKey) != 0 }

    /// A global shortcut needs a modifier, except for function keys.
    public var isValid: Bool {
        hasCommand || hasOption || hasControl || Self.functionKeys.contains(Int(keyCode))
    }

    /// "⌃⌥⇧⌘2", in Apple's modifier order.
    public var display: String {
        var text = ""
        if hasControl { text += "⌃" }
        if hasOption { text += "⌥" }
        if hasShift { text += "⇧" }
        if hasCommand { text += "⌘" }
        return text + keyName
    }

    public var keyName: String { Self.names[Int(keyCode)] ?? "#\(keyCode)" }

    /// The character a menu shows for this key, when it has one.
    public var menuCharacter: Character? {
        let name = keyName
        return name.count == 1 ? Character(name.lowercased()) : nil
    }

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                                         kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15]

    static let names: [Int: String] = {
        var map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                     kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15]
        for (index, code) in fKeys.enumerated() { map[code] = "F\(index + 1)" }
        return map
    }()
}
