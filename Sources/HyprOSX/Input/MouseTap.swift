import CoreGraphics
import Foundation
import QuartzCore
import HyprCore

final class MouseTap {
    private static let mask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    private let onDecision: (MouseDecision) -> Void
    private let onLeftUp: () -> Void
    private let lock = NSLock()
    private let tap = EventTap()
    private var matcher = MouseBindMatcher()
    private var generation = 0

    init(onDecision: @escaping (MouseDecision) -> Void, onLeftUp: @escaping () -> Void) {
        self.onDecision = onDecision
        self.onLeftUp = onLeftUp
    }

    func update(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int) -> Bool {
        var next = MouseBindMatcher()
        next.setBinds(binds, dragThreshold: dragThreshold, scrollEventDelayMs: scrollEventDelayMs)
        guard !next.isEmpty else {
            stop()
            return true
        }
        if !tap.ensureEnabled() { stop() }
        lock.lock()
        matcher.setBinds(binds, dragThreshold: dragThreshold, scrollEventDelayMs: scrollEventDelayMs)
        lock.unlock()
        return tap.isRunning || start()
    }

    func stop() {
        let cursor = Screens.cursor()
        lock.lock()
        matcher = MouseBindMatcher()
        generation += 1
        lock.unlock()
        if tap.isRunning { onDecision(.end(cursor)) }
        tap.stop()
    }

    private func start() -> Bool {
        tap.start(mask: Self.mask, name: "HyprOSX mouse tap") { [weak self] type, event in self?.handle(type, event) ?? false }
    }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { m.insert(.function) }
        return m
    }

    private func deliver(_ decisions: [MouseDecision], leftUp: Bool = false, generation: Int) {
        DispatchQueue.main.async { [self] in
            lock.lock()
            let current = self.generation
            lock.unlock()
            guard current == generation else {
                if leftUp { onLeftUp() }
                return
            }
            decisions.forEach(onDecision)
            if leftUp { onLeftUp() }
        }
    }

    private static func button(_ type: CGEventType, _ event: CGEvent) -> Int {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return 0
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
        default: return Int(event.getIntegerValueField(.mouseEventButtonNumber))
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let cursor = Screens.cursor()
            lock.lock()
            let ended = matcher.cancel(at: cursor)
            let generation = generation
            lock.unlock()
            tap.reenable()
            if case .end = ended { deliver([ended], generation: generation) }
            return false
        }
        let p = Point(x: Double(event.location.x), y: Double(event.location.y))
        let mods = Self.modifiers(event.flags)
        let button = Self.button(type, event)
        var lost: [MouseDecision] = []
        var followUp: [MouseDecision] = []
        lock.lock()
        let generation = generation
        let decision: MouseDecision
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let recovered = matcher.recover(button: button)
            if recovered != .pass { lost = [recovered] }
            decision = matcher.down(button: button, modifiers: mods, at: p)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            decision = matcher.dragged(button: button, to: p)
            if case .start = decision { followUp = [.move(p)] }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            decision = matcher.up(button: button, modifiers: mods, at: p)
        case .scrollWheel:
            let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let horizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let direction: ScrollDirection? = vertical > 0 ? .up : vertical < 0 ? .down : horizontal > 0 ? .left : horizontal < 0 ? .right : nil
            decision = direction.map { matcher.scroll($0, modifiers: mods, now: CACurrentMediaTime()) } ?? .pass
        default:
            decision = .pass
        }
        lock.unlock()
        let consumed = decision != .pass
        let batch: [MouseDecision]
        switch decision {
        case .pass, .consume: batch = lost
        default: batch = lost + [decision] + followUp
        }
        let leftUp = consumed && type == .leftMouseUp
        if !batch.isEmpty || leftUp { deliver(batch, leftUp: leftUp, generation: generation) }
        return consumed
    }
}
