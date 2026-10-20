import CoreGraphics
import Foundation
import HyprCore

final class KeyTap {
    private static let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue)

    private let run: ([Bind]) -> Void
    private let lock = NSLock()
    private let tap = EventTap()
    private var matcher = KeyTapMatcher()

    init(run: @escaping ([Bind]) -> Void) { self.run = run }

    func update(_ groups: [HotkeyGroup], keepRunning: Bool) -> Bool {
        guard keepRunning || !groups.isEmpty else {
            stop()
            return true
        }
        if !tap.ensureEnabled() { stop() }
        lock.lock()
        matcher.setGroups(groups)
        lock.unlock()
        return tap.isRunning || start()
    }

    func stop() {
        lock.lock()
        matcher = KeyTapMatcher()
        lock.unlock()
        tap.stop()
    }

    private func start() -> Bool {
        tap.start(mask: Self.mask, name: "HyprOSX key tap") { [weak self] type, event in self?.handle(type, event) ?? false }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let kind: KeyTapMatcher.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            matcher.reset()
            lock.unlock()
            tap.reenable()
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
