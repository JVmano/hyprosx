import Foundation

public struct HotkeyGroup: Equatable, Sendable {
    public var modifiers: Modifiers
    public var keyCode: UInt16
    public var press: [Bind] = []
    public var release: [Bind] = []
    public var repeats = false
}

public enum HotkeyPlan {
    public static func groups(_ binds: [Bind]) -> [HotkeyGroup] {
        var groups: [HotkeyGroup] = []
        for b in binds where !b.flags.contains(.mouse) {
            guard case .key(let code) = b.trigger else { continue }
            let index = groups.firstIndex { $0.modifiers == b.modifiers && $0.keyCode == code } ?? {
                groups.append(HotkeyGroup(modifiers: b.modifiers, keyCode: code))
                return groups.count - 1
            }()
            if b.flags.contains(.release) {
                groups[index].release.append(b)
            } else {
                groups[index].press.append(b)
                if b.flags.contains(.repeating) { groups[index].repeats = true }
            }
        }
        return groups
    }

    public static func usesTap(_ m: Modifiers) -> Bool {
        m.contains(.option) && !m.contains(.command) && !m.contains(.control)
    }

    public static func split(_ groups: [HotkeyGroup]) -> (carbon: [HotkeyGroup], tap: [HotkeyGroup]) {
        (groups.filter { !usesTap($0.modifiers) }, groups.filter { usesTap($0.modifiers) })
    }

    public static func carbonModifiers(_ m: Modifiers) -> UInt32 {
        (m.contains(.command) ? 0x0100 : 0) | (m.contains(.shift) ? 0x0200 : 0) | (m.contains(.option) ? 0x0800 : 0) | (m.contains(.control) ? 0x1000 : 0)
    }
}
