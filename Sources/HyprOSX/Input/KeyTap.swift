import CoreGraphics
import Foundation
import HyprCore

private struct TapKey: Hashable {
    let code: UInt16
    let modifiers: Modifiers
}

private let tapModifiers: Modifiers = [.command, .option, .control, .shift]

private func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let consumed = Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

final class KeyTap {
    private let run: ([Bind]) -> Void
    private let lock = NSLock()
    private var groups: [TapKey: HotkeyGroup] = [:]
    private var held: [UInt16: TapKey] = [:]
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    init(run: @escaping ([Bind]) -> Void) { self.run = run }

    func update(_ newGroups: [HotkeyGroup]) -> Bool {
        guard !newGroups.isEmpty else {
            stop()
            return true
        }
        var table: [TapKey: HotkeyGroup] = [:]
        for group in newGroups {
            table[TapKey(code: group.keyCode, modifiers: group.modifiers.intersection(tapModifiers))] = group
        }
        lock.lock()
        groups = table
        let running = port != nil
        lock.unlock()
        return running || start()
    }

    func stop() {
        lock.lock()
        groups = [:]
        held = [:]
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
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue | 1 << CGEventType.flagsChanged.rawValue)
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
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            held = [:]
            let port = port
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let key = TapKey(code: code, modifiers: Self.modifiers(event.flags))
            lock.lock()
            guard let group = groups[key] else {
                lock.unlock()
                return false
            }
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeated { held[code] = key }
            lock.unlock()
            if !repeated {
                dispatch(group.press, repeatingOnly: false)
            } else if group.repeats {
                dispatch(group.press, repeatingOnly: true)
            }
            return true
        case .keyUp:
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            lock.lock()
            guard let key = held.removeValue(forKey: code) else {
                lock.unlock()
                return false
            }
            let group = groups[key]
            lock.unlock()
            if let group { dispatch(group.release, repeatingOnly: false) }
            return true
        default:
            return false
        }
    }

    private func dispatch(_ binds: [Bind], repeatingOnly: Bool) {
        guard !binds.isEmpty else { return }
        let run = run
        DispatchQueue.main.async { run(repeatingOnly ? binds.filter { $0.flags.contains(.repeating) } : binds) }
    }

    private static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        return m
    }
}
