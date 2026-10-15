import CoreGraphics
import Foundation
import HyprCore

private func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let consumed = Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

final class KeyTap {
    private let run: ([Bind]) -> Void
    private let lock = NSLock()
    private var matcher = KeyTapMatcher()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    init(run: @escaping ([Bind]) -> Void) { self.run = run }

    func update(_ groups: [HotkeyGroup], keepRunning: Bool) -> Bool {
        guard keepRunning || !groups.isEmpty else {
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
        matcher.setGroups(groups)
        let running = port != nil
        lock.unlock()
        return running || start()
    }

    func stop() {
        lock.lock()
        matcher = KeyTapMatcher()
        let stopped = (port: port, runLoop: runLoop)
        port = nil
        runLoop = nil
        lock.unlock()
        guard let port = stopped.port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let rl = stopped.runLoop {
            CFRunLoopStop(rl)
            _ = finished.wait(timeout: .now() + 1)
        }
    }

    private func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                           callback: tapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
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
        thread.name = "HyprOSX key tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let kind: KeyTapMatcher.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            matcher.reset()
            let port = port
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        default: return false
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let repeated = kind == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags
        var modifiers: Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        lock.lock()
        let decision = matcher.handle(kind, keyCode: code, modifiers: modifiers, autorepeat: repeated)
        lock.unlock()
        if !decision.binds.isEmpty {
            let run = run
            let binds = decision.binds
            DispatchQueue.main.async { run(binds) }
        }
        return decision.consume
    }
}
