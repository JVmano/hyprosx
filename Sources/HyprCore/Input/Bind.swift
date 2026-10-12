import Foundation

public enum ScrollDirection: String, Codable, Sendable { case up, down, left, right }

public enum BindTrigger: Hashable, Sendable {
    case key(UInt16)
    case mouse(Int)
    case scroll(ScrollDirection)
    case catchall
}

public struct BindFlags: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let release = BindFlags(rawValue: 1 << 0)
    public static let repeating = BindFlags(rawValue: 1 << 1)
    public static let mouse = BindFlags(rawValue: 1 << 2)
    public static let universal = BindFlags(rawValue: 1 << 3)
    public static let description = BindFlags(rawValue: 1 << 4)
    public static let locked = BindFlags(rawValue: 1 << 5)
    public static let transparent = BindFlags(rawValue: 1 << 6)
    public static let bypass = BindFlags(rawValue: 1 << 7)
    public static let nonConsuming = BindFlags(rawValue: 1 << 8)
    public static let ignoreMods = BindFlags(rawValue: 1 << 9)
    public static let separate = BindFlags(rawValue: 1 << 10)
    public static let longPress = BindFlags(rawValue: 1 << 11)
    public static let click = BindFlags(rawValue: 1 << 12)
    public static let drag = BindFlags(rawValue: 1 << 13)
    public static let perDevice = BindFlags(rawValue: 1 << 14)

    static let letters: [Character: BindFlags] = [
        "l": .locked, "r": .release, "c": .click, "g": .drag, "o": .longPress, "e": .repeating, "n": .nonConsuming,
        "m": .mouse, "t": .transparent, "i": .ignoreMods, "s": .separate, "d": .description, "p": .bypass,
        "u": .universal, "k": .perDevice,
    ]
    static let unsupported: Set<Character> = ["n", "i", "s", "o", "c", "g", "k"]
}

public struct Bind: Equatable, Sendable {
    public var modifiers: Modifiers
    public var trigger: BindTrigger
    public var flags: BindFlags
    public var dispatcher: String
    public var arguments: String
    public var description: String?
    public var submap: String
    public var location: SourceLocation
    public init(modifiers: Modifiers, trigger: BindTrigger, flags: BindFlags, dispatcher: String, arguments: String,
                description: String?, submap: String, location: SourceLocation) {
        self.modifiers = modifiers; self.trigger = trigger; self.flags = flags; self.dispatcher = dispatcher
        self.arguments = arguments; self.description = description; self.submap = submap; self.location = location
    }
}

public enum BindParser {
    public static func parseTrigger(_ key: String) -> BindTrigger? {
        let k = key.trimmingCharacters(in: .whitespaces)
        let lower = k.lowercased()
        if lower.hasPrefix("code:") { return UInt16(lower.dropFirst(5)).map { .key($0) } }
        if lower.hasPrefix("mouse:") { return Int(lower.dropFirst(6)).map { .mouse($0) } }
        switch lower {
        case "mouse_up": return .scroll(.up)
        case "mouse_down": return .scroll(.down)
        case "mouse_left": return .scroll(.left)
        case "mouse_right": return .scroll(.right)
        case "catchall": return .catchall
        default: return Keysym.keyCode(for: k).map { .key($0) }
        }
    }

    public static func parseUnbind(_ value: String) -> (Modifiers, BindTrigger)? {
        let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let mods = Modifiers.parse(parts[0]), let trigger = parseTrigger(parts[1]) else { return nil }
        return (mods, trigger)
    }

    public static func parse(keyword: String, value: String, submap: String, location: SourceLocation) -> (bind: Bind?, diagnostics: [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        var flags: BindFlags = []
        for letter in keyword.dropFirst(4) {
            guard let flag = BindFlags.letters[letter] else {
                return (nil, [Diagnostic(location, "invalid bind flag '\(letter)'")])
            }
            if BindFlags.unsupported.contains(letter) {
                diagnostics.append(Diagnostic(location, "bind flag '\(letter)' is not supported on macOS; loaded as a plain bind", isWarning: true))
            }
            flags.insert(flag)
        }
        var fixed = 3
        if flags.contains(.description) { fixed += 1 }
        if flags.contains(.perDevice) { fixed += 1 }
        let isMouse = flags.contains(.mouse)
        let raw = value.split(separator: ",", maxSplits: isMouse ? fixed - 1 : fixed, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard raw.count >= fixed, !raw[fixed - 1].isEmpty else { return (nil, diagnostics + [Diagnostic(location, "missing dispatcher")]) }
        guard let mods = Modifiers.parse(raw[0]) else { return (nil, diagnostics + [Diagnostic(location, "invalid modifiers '\(raw[0])'")]) }
        guard let trigger = parseTrigger(raw[1]) else { return (nil, diagnostics + [Diagnostic(location, "invalid key '\(raw[1])'")]) }
        if trigger == .catchall {
            return (nil, diagnostics + [Diagnostic(location, "catchall binds are not supported on macOS", isWarning: true)])
        }
        if mods.contains(.function), case .key = trigger {
            return (nil, diagnostics + [Diagnostic(location, "FN works only with mouse and scroll binds")])
        }
        var index = 2
        if flags.contains(.perDevice) { index += 1 }
        var description: String?
        if flags.contains(.description) { description = raw[index]; index += 1 }
        let dispatcher = raw[index]
        let arguments = isMouse ? "" : (raw.count > index + 1 ? raw[index + 1] : "")
        let bind = Bind(modifiers: mods, trigger: trigger, flags: flags, dispatcher: dispatcher, arguments: arguments,
                        description: description, submap: submap, location: location)
        return (bind, diagnostics)
    }
}
