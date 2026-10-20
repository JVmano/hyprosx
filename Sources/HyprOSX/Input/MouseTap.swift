import CoreGraphics
import Foundation
import QuartzCore
import HyprCore

private func mouseTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let consumed = Unmanaged<MouseTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

final class MouseTap {
    private let onDecision: (MouseDecision) -> Void
    private let lock = NSLock()
    private var matcher = MouseBindMatcher()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    init(onDecision: @escaping (MouseDecision) -> Void) { self.onDecision = onDecision }

    func update(_ binds: [Bind], dragThreshold: Int, scrollEventDelayMs: Int) -> Bool {
        var next = MouseBindMatcher()
        next.setBinds(binds, dragThreshold: dragThreshold, scrollEventDelayMs: scrollEventDelayMs)
        guard !next.isEmpty else {
            stop()
            return true
        }
        lock.lock()
        let current = port
        lock.unlock()
        if let current, !CGEvent.tapIsEnabled(tap: current) {
            CGEvent.tapEnable(tap: current, enable: true)
            if !CGEvent.tapIsEnabled(tap: current) { stop() }
        }
        lock.lock()
        matcher.setBinds(binds, dragThreshold: dragThreshold, scrollEventDelayMs: scrollEventDelayMs)
        let running = port != nil
        lock.unlock()
        return running || start()
    }

    func stop() {
        lock.lock()
        let ended = matcher.cancel(at: Screens.cursor())
        matcher = MouseBindMatcher()
        let stopped = (port: port, runLoop: runLoop)
        port = nil
        runLoop = nil
        lock.unlock()
        if case .end = ended { onDecision(ended) }
        guard let port = stopped.port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let rl = stopped.runLoop {
            CFRunLoopStop(rl)
            _ = finished.wait(timeout: .now() + 1)
        }
    }

    private static let mask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ].reduce(0) { $0 | (1 << $1.rawValue) }

    private func start() -> Bool {
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: Self.mask, callback: mouseTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }
        lock.lock()
        self.port = port
        lock.unlock()
        let thread = Thread { [self] in
            lock.lock()
            runLoop = CFRunLoopGetCurrent()
            lock.unlock()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
            finished.signal()
        }
        thread.name = "HyprOSX mouse tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return true
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

    private func deliver(_ decisions: [MouseDecision]) {
        DispatchQueue.main.async { [onDecision] in decisions.forEach(onDecision) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let ended = matcher.cancel(at: Screens.cursor())
            let port = port
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            if case .end = ended { deliver([ended]) }
            return false
        }
        let p = Point(x: Double(event.location.x), y: Double(event.location.y))
        let mods = Self.modifiers(event.flags)
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        var followUp: [MouseDecision] = []
        lock.lock()
        let decision: MouseDecision
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            decision = matcher.down(button: button, modifiers: mods, at: p)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            decision = matcher.dragged(to: p)
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
        switch decision {
        case .pass: return false
        case .consume: return true
        default:
            deliver([decision] + followUp)
            return true
        }
    }
}
