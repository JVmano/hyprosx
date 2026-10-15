import Foundation

public struct KeyTapDecision: Sendable {
    public var consume: Bool
    public var binds: [Bind]
    public static let pass = KeyTapDecision(consume: false, binds: [])
}

public struct KeyTapMatcher: Sendable {
    public enum Kind: Sendable { case keyDown, keyUp }

    private struct Key: Hashable {
        let code: UInt16
        let modifiers: Modifiers
    }

    private struct Entry {
        let group: HotkeyGroup
        let repeating: [Bind]
    }

    private static let compared: Modifiers = [.command, .option, .control, .shift]

    private var table: [Key: Entry] = [:]
    private var held: [UInt16: Key] = [:]

    public init() {}

    public mutating func setGroups(_ groups: [HotkeyGroup]) {
        table = [:]
        for group in groups {
            table[Key(code: group.keyCode, modifiers: group.modifiers.intersection(Self.compared))] =
                Entry(group: group, repeating: group.press.filter { $0.flags.contains(.repeating) })
        }
    }

    public mutating func reset() { held = [:] }

    public mutating func handle(_ kind: Kind, keyCode: UInt16, modifiers: Modifiers, autorepeat: Bool) -> KeyTapDecision {
        let key = Key(code: keyCode, modifiers: modifiers.intersection(Self.compared))
        switch kind {
        case .keyUp:
            guard let heldKey = held.removeValue(forKey: keyCode) else { return .pass }
            return KeyTapDecision(consume: true, binds: table[heldKey]?.group.release ?? [])
        case .keyDown where autorepeat:
            guard let heldKey = held[keyCode] ?? (table[key] != nil ? key : nil) else { return .pass }
            held[keyCode] = heldKey
            return KeyTapDecision(consume: true, binds: table[heldKey]?.repeating ?? [])
        case .keyDown:
            guard let entry = table[key] else {
                held.removeValue(forKey: keyCode)
                return .pass
            }
            held[keyCode] = key
            return KeyTapDecision(consume: true, binds: entry.group.press)
        }
    }
}
