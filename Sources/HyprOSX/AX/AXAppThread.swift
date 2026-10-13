import AppKit
import ApplicationServices
import HyprCore

enum AXAppEvent {
    case appeared(WindowSnapshot)
    case disappeared(WindowID)
    case minimized(WindowID, Bool)
    case nativeFullscreen(WindowID, Bool)
    case title(WindowID, String)
    case frame(WindowID, Rect)
    case focused(WindowID?)
    case registrationDelayed
    case scanned
}

private enum FrameJob {
    case frame(Rect)
    case position(Point)
}

private let windowNotifications = [
    kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification,
]

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<AXAppThread>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element)
}

final class AXAppThread {
    let pid: pid_t
    let bundleID: String
    let appName: String
    private let isAccessory: Bool
    private let onEvent: (AXAppEvent) -> Void
    private let app: AXUIElement
    private var runLoop: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)
    private var observer: AXObserver?
    private var windows: [WindowID: AXUIElement] = [:]
    private var fullscreen: Set<WindowID> = []
    private var delayed: [AXUIElement] = []
    private var suppressUntil: [WindowID: UInt64] = [:]
    private let lock = NSLock()
    private var jobs: [WindowID: FrameJob] = [:]
    private var draining = false
    private var latency = 0.0
    private var calls = 0
    private var errors = 0
    private var screenSizes: [Size] = []

    init(pid: pid_t, bundleID: String, appName: String, isAccessory: Bool, onEvent: @escaping (AXAppEvent) -> Void) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.isAccessory = isAccessory
        self.onEvent = onEvent
        self.app = AXUIElementCreateApplication(pid)
    }

    var averageLatencyMs: Double { lock.lock(); defer { lock.unlock() }; return latency }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var errorCount: Int { lock.lock(); defer { lock.unlock() }; return errors }

    func start() {
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "AX \(appName) \(pid)"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = started.wait(timeout: .now() + 2)
    }

    func stop() {
        perform { [weak self] in
            guard let self else { return }
            if let obs = self.observer {
                for (_, e) in self.windows { for n in windowNotifications { AXObserverRemoveNotification(obs, e, n as CFString) } }
                AXObserverRemoveNotification(obs, self.app, kAXWindowCreatedNotification as CFString)
                AXObserverRemoveNotification(obs, self.app, kAXFocusedWindowChangedNotification as CFString)
            }
            self.windows = [:]
            self.lock.lock()
            self.runLoop = nil
            self.lock.unlock()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    func updateScreenSizes(_ sizes: [Size]) {
        lock.lock()
        screenSizes = sizes
        lock.unlock()
    }

    private func threadMain() {
        lock.lock()
        runLoop = CFRunLoopGetCurrent()
        lock.unlock()
        started.signal()
        RunLoop.current.add(NSMachPort(), forMode: .default)
        AXUIElementSetMessagingTimeout(app, 1.0)
        var obs: AXObserver?
        if AXObserverCreate(pid, axCallback, &obs) == .success, let obs {
            observer = obs
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
            let ref = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, ref)
            AXObserverAddNotification(obs, app, kAXFocusedWindowChangedNotification as CFString, ref)
        }
        scan()
        emit(.scanned)
        CFRunLoopRun()
    }

    @discardableResult
    private func perform(_ block: @escaping () -> Void) -> Bool {
        lock.lock()
        let rl = runLoop
        lock.unlock()
        guard let rl else { return false }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
        return true
    }

    private func emit(_ event: AXAppEvent) {
        let handler = onEvent
        DispatchQueue.main.async { handler(event) }
    }

    func rescan() { perform { [weak self] in self?.scan() } }

    func flush(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        guard perform({ done.signal() }) else { return }
        _ = done.wait(timeout: .now() + timeout)
    }

    func flushDelayed() {
        perform { [weak self] in
            guard let self else { return }
            let pending = self.delayed
            self.delayed = []
            if pending.isEmpty { return }
            for e in pending { if let id = AX.windowID(e), self.windows[id] == nil { self.register(e, id: id) } }
            self.reportFocused()
        }
    }

    private func scan() {
        if let list = AX.elementList(app, kAXWindowsAttribute) {
            for e in list {
                guard let id = AX.windowID(e) else { continue }
                if windows[id] == nil { register(e, id: id) }
            }
        }
        for (id, e) in Array(windows) where AX.windowID(e) == nil { forget(id) }
        reportFocused()
    }

    private func register(_ e: AXUIElement, id: WindowID) {
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            if !delayed.contains(where: { CFEqual($0, e) }) { delayed.append(e) }
            emit(.registrationDelayed)
            return
        }
        AXUIElementSetMessagingTimeout(e, 1.0)
        let kind = WindowClassifier.classify(AXWindowAttributes(window: e, app: app, windowID: id), bundleID: bundleID,
                                             isAccessoryApp: isAccessory, windowLevel: AX.windowLevel(id))
        guard kind != .notAWindow else { return }
        windows[id] = e
        if let obs = observer {
            let ref = Unmanaged.passUnretained(self).toOpaque()
            for n in windowNotifications { AXObserverAddNotification(obs, e, n as CFString, ref) }
        }
        let snapshot = WindowSnapshot(id: id, pid: pid, bundleID: bundleID, appName: appName, title: AX.string(e, kAXTitleAttribute) ?? "",
                                      frame: AX.frame(e) ?? .zero, kind: kind == .dialog ? .dialog : .normal)
        emit(.appeared(snapshot))
        if AX.bool(e, kAXMinimizedAttribute) == true { emit(.minimized(id, true)) }
    }

    private func forget(_ id: WindowID) {
        guard let e = windows.removeValue(forKey: id) else { return }
        if let obs = observer { for n in windowNotifications { AXObserverRemoveNotification(obs, e, n as CFString) } }
        fullscreen.remove(id)
        suppressUntil[id] = nil
        emit(.disappeared(id))
    }

    private func reportFocused() {
        guard let e = AX.element(app, kAXFocusedWindowAttribute), let id = AX.windowID(e) else {
            emit(.focused(nil))
            return
        }
        if windows[id] == nil { register(e, id: id) }
        emit(.focused(windows[id] == nil ? nil : id))
    }

    private func knownID(_ e: AXUIElement) -> WindowID? {
        if let id = AX.windowID(e), windows[id] != nil { return id }
        return windows.first { CFEqual($0.value, e) }?.key
    }

    fileprivate func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            if let id = AX.windowID(element), windows[id] == nil { register(element, id: id) }
        case kAXFocusedWindowChangedNotification:
            reportFocused()
        case kAXUIElementDestroyedNotification:
            if let id = windows.first(where: { CFEqual($0.value, element) })?.key { forget(id) }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = knownID(element) { emit(.minimized(id, notification == kAXWindowMiniaturizedNotification)) }
        case kAXMovedNotification, kAXResizedNotification:
            guard let id = knownID(element) else { return }
            if let until = suppressUntil[id], DispatchTime.now().uptimeNanoseconds < until { return }
            guard let frame = AX.frame(element) else { return }
            if notification == kAXResizedNotification {
                lock.lock()
                let sizes = screenSizes
                lock.unlock()
                let fillsScreen = sizes.contains { abs($0.width - frame.width) < 1 && abs($0.height - frame.height) < 1 }
                if fillsScreen || fullscreen.contains(id) {
                    let isFull = AX.bool(element, "AXFullScreen") == true
                    if isFull != fullscreen.contains(id) {
                        if isFull { fullscreen.insert(id) } else { fullscreen.remove(id) }
                        emit(.nativeFullscreen(id, isFull))
                        return
                    }
                }
            }
            emit(.frame(id, frame))
        case kAXTitleChangedNotification:
            if let id = knownID(element) { emit(.title(id, AX.string(element, kAXTitleAttribute) ?? "")) }
        default:
            break
        }
    }

    func setFrame(_ id: WindowID, _ frame: Rect) { enqueue(id, .frame(frame)) }

    func setPosition(_ id: WindowID, _ p: Point) { enqueue(id, .position(p)) }

    private func enqueue(_ id: WindowID, _ job: FrameJob) {
        lock.lock()
        if case .frame(let pending)? = jobs[id], case .position(let p) = job {
            jobs[id] = .frame(Rect(origin: p, size: pending.size))
        } else {
            jobs[id] = job
        }
        let schedule = !draining
        draining = true
        lock.unlock()
        if schedule { scheduleDrain() }
    }

    private func scheduleDrain() {
        if perform({ [weak self] in self?.drain() }) { return }
        lock.lock()
        draining = false
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        let batch = jobs
        jobs = [:]
        if batch.isEmpty {
            draining = false
            lock.unlock()
            return
        }
        lock.unlock()
        let eui = AX.bool(app, "AXEnhancedUserInterface") == true
        if eui { AX.setBool(app, "AXEnhancedUserInterface", false) }
        var written: [WindowID] = []
        for (id, job) in batch {
            guard let e = windows[id] else { continue }
            written.append(id)
            let start = DispatchTime.now().uptimeNanoseconds
            var result: AXError
            switch job {
            case .frame(let r):
                let size = CGSize(width: r.width, height: r.height)
                AX.setSize(e, size)
                AX.setPosition(e, CGPoint(x: r.x, y: r.y))
                result = AX.setSize(e, size)
            case .position(let p):
                result = AX.setPosition(e, CGPoint(p))
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            lock.lock()
            calls += 1
            if result != .success { errors += 1 }
            latency = calls == 1 ? ms : latency * 0.8 + ms * 0.2
            lock.unlock()
            if result == .invalidUIElement { forget(id) }
        }
        if eui { AX.setBool(app, "AXEnhancedUserInterface", true) }
        let until = DispatchTime.now().uptimeNanoseconds + 150_000_000
        for id in written where windows[id] != nil { suppressUntil[id] = until }
        lock.lock()
        let more = !jobs.isEmpty
        if !more { draining = false }
        lock.unlock()
        if more { scheduleDrain() }
    }

    func focus(_ id: WindowID) {
        perform { [weak self] in
            guard let self, let e = self.windows[id] else { return }
            AX.setBool(e, kAXMainAttribute, true)
            AX.perform(e, kAXRaiseAction)
            AX.setBool(self.app, kAXFrontmostAttribute, true)
            NSRunningApplication(processIdentifier: self.pid)?.activate()
        }
    }

    func raise(_ id: WindowID) {
        perform { [weak self] in
            guard let e = self?.windows[id] else { return }
            AX.perform(e, kAXRaiseAction)
        }
    }

    func close(_ id: WindowID) {
        perform { [weak self] in
            guard let e = self?.windows[id], let button = AX.element(e, kAXCloseButtonAttribute) else { return }
            AX.perform(button, kAXPressAction)
        }
    }
}
