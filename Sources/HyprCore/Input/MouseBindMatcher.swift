import Foundation

public enum MouseBindAction: Equatable, Sendable { case move, resize }

public enum MouseDecision: Equatable, Sendable {
    case pass
    case consume
    case run([Bind])
    case start(MouseBindAction, Point)
    case move(Point)
    case end(Point)
}

public struct MouseBindMatcher: Sendable {
    public static let buttonBase = 272

    private struct Press: Sendable {
        var button: Int
        var action: MouseBindAction
        var origin: Point
        var started: Bool
    }

    private var binds: [Bind] = []
    private var threshold = 0.0
    private var scrollDelay = 0.0
    private var press: Press?
    private var claimed: Set<Int> = []
    private var lastScroll = -Double.infinity

    public init() {}

    public var isEmpty: Bool { binds.isEmpty }

    public mutating func setBinds(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int) {
        self.binds = binds.filter {
            switch $0.trigger {
            case .mouse, .scroll: return true
            case .key, .catchall: return false
            }
        }
        threshold = Double(max(0, dragThreshold))
        scrollDelay = Double(max(0, scrollEventDelayMs)) / 1000
    }

    static func clean(_ m: Modifiers) -> Modifiers { m.intersection([.command, .option, .control, .shift, .function]) }

    static func action(_ dispatcher: String) -> MouseBindAction? {
        switch dispatcher.lowercased() {
        case "movewindow": return .move
        case "resizewindow": return .resize
        default: return nil
        }
    }

    public mutating func down(button: Int, modifiers: Modifiers, at p: Point) -> MouseDecision {
        let trigger = BindTrigger.mouse(Self.buttonBase + button)
        let mods = Self.clean(modifiers)
        let matching = binds.filter { $0.trigger == trigger && $0.modifiers == mods }
        guard !matching.isEmpty else { return .pass }
        claimed.insert(button)
        if let drag = matching.first(where: { $0.flags.contains(.mouse) && Self.action($0.dispatcher) != nil }),
           let action = Self.action(drag.dispatcher) {
            guard press == nil else { return .consume }
            press = Press(button: button, action: action, origin: p, started: threshold == 0)
            return threshold == 0 ? .start(action, p) : .consume
        }
        let onPress = matching.filter { !$0.flags.contains(.mouse) && !$0.flags.contains(.release) }
        return onPress.isEmpty ? .consume : .run(onPress)
    }

    public mutating func dragged(to p: Point) -> MouseDecision {
        guard var current = press else { return claimed.isEmpty ? .pass : .consume }
        if !current.started {
            guard hypot(p.x - current.origin.x, p.y - current.origin.y) >= threshold else { return .consume }
            current.started = true
            press = current
            return .start(current.action, current.origin)
        }
        return .move(p)
    }

    public mutating func up(button: Int, modifiers: Modifiers, at p: Point) -> MouseDecision {
        guard claimed.remove(button) != nil else { return .pass }
        if let current = press, current.button == button {
            press = nil
            return current.started ? .end(p) : .consume
        }
        let trigger = BindTrigger.mouse(Self.buttonBase + button)
        let mods = Self.clean(modifiers)
        let onRelease = binds.filter { $0.trigger == trigger && $0.modifiers == mods && $0.flags.contains(.release) }
        return onRelease.isEmpty ? .consume : .run(onRelease)
    }

    public mutating func scroll(_ direction: ScrollDirection, modifiers: Modifiers, now: Double) -> MouseDecision {
        let mods = Self.clean(modifiers)
        let matching = binds.filter { $0.trigger == .scroll(direction) && $0.modifiers == mods }
        guard !matching.isEmpty else { return .pass }
        guard now - lastScroll >= scrollDelay else { return .consume }
        lastScroll = now
        return .run(matching)
    }
}
