import CoreGraphics
import Foundation

private func eventTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let consumed = Unmanaged<EventTap>.fromOpaque(info).takeUnretainedValue().consumes(type, event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

final class EventTap {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var finished: DispatchSemaphore?
    private var handler: ((CGEventType, CGEvent) -> Bool)?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return port != nil
    }

    func start(mask: CGEventMask, name: String, handler: @escaping (CGEventType, CGEvent) -> Bool) -> Bool {
        lock.lock()
        self.handler = handler
        lock.unlock()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                           callback: eventTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }
        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        lock.lock()
        self.port = port
        self.finished = finished
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
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        return true
    }

    @discardableResult
    func stop() -> Bool {
        lock.lock()
        let stopped = (port: port, runLoop: runLoop, finished: finished)
        port = nil
        runLoop = nil
        finished = nil
        lock.unlock()
        guard let port = stopped.port else { return false }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let rl = stopped.runLoop {
            CFRunLoopStop(rl)
            _ = stopped.finished?.wait(timeout: .now() + 1)
        }
        return true
    }

    func ensureEnabled() -> Bool {
        lock.lock()
        let current = port
        lock.unlock()
        guard let current, !CGEvent.tapIsEnabled(tap: current) else { return true }
        CGEvent.tapEnable(tap: current, enable: true)
        return CGEvent.tapIsEnabled(tap: current)
    }

    func reenable() {
        lock.lock()
        let current = port
        lock.unlock()
        if let current { CGEvent.tapEnable(tap: current, enable: true) }
    }

    fileprivate func consumes(_ type: CGEventType, _ event: CGEvent) -> Bool {
        lock.lock()
        let handler = handler
        lock.unlock()
        return handler?(type, event) ?? false
    }
}
