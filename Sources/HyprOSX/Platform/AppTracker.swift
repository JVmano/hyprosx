import AppKit
import HyprCore

final class AppTracker {
    static let skippedBundleIDs: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]
    static let earlyTitleWindow: TimeInterval = 2

    private let onEvent: (PlatformEvent) -> Void
    var onDelayedRegistration: () -> Void = {}
    var onDragStarted: () -> Void = {}
    var onInitialScanDone: () -> Void = {}
    var screenSizes: [Size] = [] {
        didSet { threads.values.forEach { $0.updateScreenSizes(screenSizes) } }
    }
    private(set) var threads: [pid_t: AXAppThread] = [:]
    private var observers: [NSObjectProtocol] = []
    private var pendingScans: Set<pid_t> = []
    private var appearedAt: [WindowID: (pid: pid_t, at: TimeInterval)] = [:]
    private var hiddenByUs: Set<pid_t> = []

    init(onEvent: @escaping (PlatformEvent) -> Void) { self.onEvent = onEvent }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let handlers: [(Notification.Name, (NSRunningApplication) -> Void)] = [
            (NSWorkspace.didLaunchApplicationNotification, { [weak self] in self?.launched($0) }),
            (NSWorkspace.didTerminateApplicationNotification, { [weak self] in self?.terminated($0) }),
            (NSWorkspace.didActivateApplicationNotification, { [weak self] in self?.activated($0) }),
            (NSWorkspace.didHideApplicationNotification, { [weak self] in self?.hidden($0) }),
            (NSWorkspace.didUnhideApplicationNotification, { [weak self] in self?.unhidden($0) }),
        ]
        observers = handlers.map { name, handler in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { handler(app) }
            }
        }
        let apps = NSWorkspace.shared.runningApplications.filter(isTracked)
        pendingScans = Set(apps.map(\.processIdentifier))
        apps.forEach(register)
        if pendingScans.isEmpty { onInitialScanDone() }
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        threads.values.forEach { $0.stop() }
        threads = [:]
        pendingScans = []
        appearedAt = [:]
        hiddenByUs = []
    }

    func isTracked(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid() && !Self.skippedBundleIDs.contains(app.bundleIdentifier ?? "")
    }

    private func register(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard threads[pid] == nil else { return }
        let thread = AXAppThread(pid: pid, bundleID: app.bundleIdentifier ?? "", appName: app.localizedName ?? "",
                                 isAccessory: app.activationPolicy == .accessory) { [weak self] event in self?.received(event, pid: pid) }
        thread.updateScreenSizes(screenSizes)
        threads[pid] = thread
        thread.start()
    }

    private func received(_ event: AXAppEvent, pid: pid_t) {
        guard threads[pid] != nil else { return }
        switch event {
        case .appeared(let s):
            appearedAt[s.id] = (pid, ProcessInfo.processInfo.systemUptime)
            onEvent(.windowAppeared(s))
        case .disappeared(let id):
            appearedAt[id] = nil
            onEvent(.windowDisappeared(id))
        case .minimized(let id, let on):
            onEvent(on ? .windowSuspended(id, .minimized) : .windowResumed(id))
        case .nativeFullscreen(let id, let on):
            onEvent(on ? .windowSuspended(id, .nativeFullscreen) : .windowResumed(id))
        case .title(let id, let title):
            let early = appearedAt[id].map { ProcessInfo.processInfo.systemUptime - $0.at < Self.earlyTitleWindow } ?? false
            onEvent(.windowTitleChanged(id, title, early: early))
        case .frame(let id, let frame):
            let userDriven = CGEventSource.buttonState(.combinedSessionState, button: .left)
            if userDriven { onDragStarted() }
            onEvent(.windowFrameChanged(id, frame, userDriven: userDriven))
        case .focused(let id):
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            onEvent(.focusChanged(id))
        case .registrationDelayed:
            onDelayedRegistration()
        case .scanned:
            if pendingScans.remove(pid) != nil && pendingScans.isEmpty { onInitialScanDone() }
        }
    }

    private func launched(_ app: NSRunningApplication) {
        if isTracked(app) { register(app) }
    }

    private func terminated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        hiddenByUs.remove(pid)
        guard let thread = threads.removeValue(forKey: pid) else { return }
        thread.stop()
        appearedAt = appearedAt.filter { $0.value.pid != pid }
        if pendingScans.remove(pid) != nil && pendingScans.isEmpty { onInitialScanDone() }
        onEvent(.appTerminated(pid: pid))
    }

    private func activated(_ app: NSRunningApplication) {
        if let thread = threads[app.processIdentifier] {
            thread.rescan()
        } else if isTracked(app) {
            register(app)
        } else {
            onEvent(.focusChanged(nil))
        }
    }

    private func hidden(_ app: NSRunningApplication) {
        guard threads[app.processIdentifier] != nil else { return }
        onEvent(.appHidden(pid: app.processIdentifier, byUser: !hiddenByUs.contains(app.processIdentifier)))
    }

    private func unhidden(_ app: NSRunningApplication) {
        hiddenByUs.remove(app.processIdentifier)
        guard threads[app.processIdentifier] != nil else { return }
        onEvent(.appUnhidden(pid: app.processIdentifier))
    }

    func hide(_ pid: pid_t) {
        hiddenByUs.insert(pid)
        if NSRunningApplication(processIdentifier: pid)?.hide() != true { hiddenByUs.remove(pid) }
    }

    func unhide(_ pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.unhide()
    }

    func unhideAllHiddenByUs() {
        hiddenByUs.forEach { NSRunningApplication(processIdentifier: $0)?.unhide() }
        hiddenByUs = []
    }
}
