import Foundation

public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    private static let names: [(String, Modifiers)] = [
        ("COMMAND", .command), ("CONTROL", .control), ("OPTION", .option), ("SUPER", .command), ("SHIFT", .shift),
        ("LOGO", .command), ("MOD4", .command), ("MOD1", .option), ("CTRL", .control), ("WIN", .command),
        ("CMD", .command), ("ALT", .option), ("OPT", .option), ("FN", .function),
    ]

    public static func parse(_ s: String) -> Modifiers? {
        let upper = s.uppercased().replacingOccurrences(of: " AND ", with: " ")
        let chars = Array(upper)
        var result: Modifiers = []
        var i = 0
        while i < chars.count {
            if !(chars[i].isLetter || chars[i].isNumber) { i += 1; continue }
            let rest = String(chars[i...])
            guard let match = names.filter({ rest.hasPrefix($0.0) }).max(by: { $0.0.count < $1.0.count }) else { return nil }
            result.insert(match.1)
            i += match.0.count
        }
        return result
    }
}

public enum Keysym {
    private static let table: [String: UInt16] = {
        var t: [String: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "section": 0x0A, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18, "9": 0x19, "7": 0x1A,
            "minus": 0x1B, "8": 0x1C, "0": 0x1D, "bracketright": 0x1E, "o": 0x1F, "u": 0x20, "bracketleft": 0x21,
            "i": 0x22, "p": 0x23, "return": 0x24, "enter": 0x24, "l": 0x25, "j": 0x26, "apostrophe": 0x27, "k": 0x28,
            "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E, "period": 0x2F,
            "tab": 0x30, "space": 0x31, "grave": 0x32, "backspace": 0x33, "escape": 0x35,
            "kp_decimal": 0x41, "kp_multiply": 0x43, "kp_add": 0x45, "kp_divide": 0x4B, "kp_enter": 0x4C,
            "kp_subtract": 0x4E, "kp_equal": 0x51, "kp_0": 0x52, "kp_1": 0x53, "kp_2": 0x54, "kp_3": 0x55, "kp_4": 0x56,
            "kp_5": 0x57, "kp_6": 0x58, "kp_7": 0x59, "kp_8": 0x5B, "kp_9": 0x5C,
            "insert": 0x72, "help": 0x72, "home": 0x73, "prior": 0x74, "page_up": 0x74, "delete": 0x75, "end": 0x77,
            "next": 0x79, "page_down": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        let f: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]
        for (i, code) in f.enumerated() { t["f\(i + 1)"] = code }
        return t
    }()

    public static func keyCode(for name: String) -> UInt16? { table[name.lowercased()] }

    public static func name(for keyCode: UInt16) -> String? {
        table.filter { $0.value == keyCode }.map(\.key).min(by: { $0.count < $1.count })
    }
}
