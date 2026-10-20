import AppKit
import ApplicationServices
import HyprCore
import os

final class AppController: NSObject, NSApplicationDelegate {
    static let version = "0.1.0"
    private static let startupTimeout: TimeInterval = 2
    private static let quitFlushSeconds: TimeInterval = 1

    private let log = Logger(subsystem: "dev.hyprosx", category: "app")
    private let configStore = ConfigStore()
    private let stateStore = StateStore()
    private let dropPreview = DropPreview()
    private let borders = BorderWindows()
    private let dims = DimWindows()
    private var status: StatusItem!
    private var world: World?
    private var tracker: AppTracker!
    private var executor: EffectExecutor!
    private var motion: MotionEngine!
    private var hotkeys: HotkeyManager!
    private var mouseUp: MouseUpMonitor!
    private var mouseMonitor: Any?
    private var configErrors: [Diagnostic] = []
    private var hotkeyInstallError: Diagnostic?
    private var runtimeErrors: [String] = []
    private var trustTimer: Timer?
    private var isSetUp = false
    private var socketStarted = false
    private var paused = false
    private var ranExecOnce = false
    private var collecting = false
    private var startupGeneration = 0
    private var startupWindows: [WindowSnapshot] = []
    private var startupEvents: [PlatformEvent] = []
    private var startupFocus: PlatformEvent?
    private var dragPending = false
    private var delayedPending = false
    private var handlingSocket = false
    private var signalSources: [DispatchSourceSignal] = []
    private var observers: [NSObjectProtocol] = []
    private let launched = Date()

    private var allErrors: [String] { (configErrors + hotkeyDiagnostics()).map(\.description) + runtimeErrors }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        installSignalHandlers()
        status = StatusItem()
        status.state = { [weak self] in self?.statusState() ?? StatusState() }
        status.onWorkspace = { [weak self] id in self?.dispatch(.workspace(.id(id))) }
        status.onReload = { [weak self] in self?.reloadConfig() }
        status.onOpenConfigFolder = { [weak self] in
            if let dir = self?.configStore.directory { NSWorkspace.shared.open(URL(fileURLWithPath: dir)) }
        }
        status.onTogglePause = { [weak self] in self?.togglePause() }
        status.onGrantAccessibility = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            setUp()
            return
        }
        status.update()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trustTimer = nil
            self?.setUp()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.deactivate()
        dropPreview.hide()
        guard isSetUp, let world else { return }
        if !paused {
            motion.stopAll()
            execute(world.releaseParked())
            tracker.unhideAllHiddenByUs()
            saveStateNow()
        }
        runExec(world.config.execShutdown)
        let threads = Array(tracker.threads.values)
        DispatchQueue.concurrentPerform(iterations: threads.count) { threads[$0].flush(timeout: Self.quitFlushSeconds) }
        if socketStarted { unlink(SocketPaths.socket()) }
        borders.removeAll()
        dims.removeAll()
    }

    private func installSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    private func setUp() {
        isSetUp = true
        tracker = AppTracker { [weak self] event in self?.trackerEvent(event) }
        tracker.onDelayedRegistration = { [weak self] in
            self?.delayedPending = true
            self?.mouseUp.arm()
        }
        tracker.onDragStarted = { [weak self] in
            self?.dragPending = true
            self?.mouseUp.arm()
        }
        tracker.onInitialScanDone = { [weak self] in self?.finishStartup() }
        motion = MotionEngine(thread: { [weak self] id in
            self?.world?.windows[id].flatMap { self?.tracker.threads[$0.pid] }
        }, world: { [weak self] in self?.world })
        motion.onSettled = { [weak self] id in self?.readBack(id) }
        motion.onFrame = { [weak self] id, frame in
            self?.borders.move(id, frame)
            self?.dims.move(id, frame)
        }
        executor = EffectExecutor(tracker: tracker, windowPID: { [weak self] id in self?.world?.windows[id]?.pid }, environment: { [weak self] in
            Spawner.environment(base: ProcessInfo.processInfo.environment, extra: self?.world?.config.environment ?? [])
        }, motion: motion)
        executor.onRaised = { [weak self] id in
            self?.dims.reorder(id)
            self?.borders.reorder(id)
        }
        executor.onSpawned = { [weak self] token, pid in self?.world?.registerSpawn(token: token, pid: pid) }
        executor.onSpawnFailed = { [weak self] message in
            guard let self, !self.runtimeErrors.contains(message) else { return }
            self.runtimeErrors.append(message)
            self.status.update()
        }
        executor.onAppEffect = { [weak self] effect in self?.appEffect(effect) }
        hotkeys = HotkeyManager { [weak self] binds in self?.runBinds(binds) }
        if !hotkeys.install() {
            hotkeyInstallError = Diagnostic(SourceLocation(file: configStore.path, line: 1),
                                            "hotkeys are unavailable: the Carbon event handler could not be installed")
        }
        mouseUp = MouseUpMonitor { [weak self] in self?.mouseReleased() }
        do {
            try SocketServer(path: SocketPaths.socket(), queue: .main) { [weak self] raw in self?.ipc(raw) ?? "" }.start()
            socketStarted = true
        } catch {
            runtimeErrors.append("hyprctl socket: \(error)")
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        })
        beginManaging()
    }

    private func beginManaging() {
        paused = false
        let (config, diagnostics) = configStore.load(writingDefaults: true)
        let world = World(config: config)
        self.world = world
        applyConfig(diagnostics)
        world.isStartingUp = true
        world.cursor = Screens.cursor()
        let monitors = Screens.current()
        tracker.screenSizes = monitors.map(\.frame.size)
        execute(world.handle(.monitorsChanged(monitors)))
        collecting = true
        startupWindows = []
        startupEvents = []
        startupFocus = nil
        startupGeneration += 1
        let generation = startupGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupTimeout) { [weak self] in
            if self?.startupGeneration == generation { self?.finishStartup() }
        }
        tracker.start()
        status.update()
    }

    private func finishStartup() {
        guard collecting, let world else { return }
        collecting = false
        world.cursor = Screens.cursor()
        if let saved = stateStore.load() {
            execute(world.restore(saved, alive: startupWindows))
        } else {
            for snapshot in startupWindows { execute(world.handle(.windowAppeared(snapshot))) }
        }
        for event in startupEvents { execute(world.handle(event)) }
        startupWindows = []
        startupEvents = []
        world.isStartingUp = false
        execute(world.handle(startupFocus ?? .focusChanged(nil)))
        startupFocus = nil
        if !ranExecOnce {
            ranExecOnce = true
            runExec(world.config.execOnce)
        }
        runExec(world.config.exec)
        scheduleSave()
        status.update()
    }

    private func applyConfig(_ diagnostics: [Diagnostic]) {
        guard let world else { return }
        refreshHotkeys()
        var all = diagnostics
        for bind in world.config.binds where !bind.flags.contains(.mouse) {
            if case .failure(let error) = CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments) {
                all.append(Diagnostic(bind.location, error.message))
            }
        }
        if !Spawner.isAvailable {
            all.append(Diagnostic(SourceLocation(file: configStore.path, line: 1), "commands are disabled: responsibility_spawnattrs_setdisclaim is missing"))
        }
        configErrors = all
        runtimeErrors.removeAll { $0.hasPrefix("AeroSpace") }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "bobko.aerospace").isEmpty {
            runtimeErrors.append("AeroSpace is running; quit it, or both apps will move windows")
        }
        followMouse(world.config.input.followMouse == 1)
        watchConfig()
    }

    private func watchConfig() {
        guard let world else { return }
        configStore.watch(sourced: world.config.sourcedFiles, enabled: !world.config.misc.disableAutoreload) { [weak self] in
            self?.reloadConfig(manual: false)
        }
    }

    private func refreshHotkeys() {
        guard let world, !paused else { return }
        hotkeys.activate(world.activeBinds, allBinds: world.config.binds)
        status.update()
    }

    private func hotkeyDiagnostics() -> [Diagnostic] {
        let failures = (hotkeys?.failures ?? []).map { failure -> Diagnostic in
            guard let world, world.submap != "", let bind = world.activeBinds.first(where: { $0.location == failure.location }),
                  bind.dispatcher == "submap" else { return failure }
            return Diagnostic(failure.location, "the key that leaves submap \(world.submap) could not be registered; pause and resume HyprOSX to leave it")
        }
        return (hotkeyInstallError.map { [$0] } ?? []) + failures
    }

    private func followMouse(_ enabled: Bool) {
        if enabled, mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.cursorMoved()
            }
        } else if !enabled, let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func cursorMoved() {
        guard let world, !paused, !collecting else { return }
        let point = Screens.cursor()
        world.cursor = point
        execute(world.handle(.cursorMoved(point)))
    }

    private func reloadConfig(fromSocket: Bool = false, manual: Bool = true) {
        guard let world, !paused else { return }
        guard configStore.mainFileExists else {
            let missing = Diagnostic(SourceLocation(file: configStore.path, line: 0), "config file \(configStore.path) is inaccessible")
            if manual, !configErrors.contains(missing) {
                configErrors.append(missing)
                status.update()
            }
            return
        }
        let runsExec = !fromSocket || world.config.macos.ipcExec
        world.cursor = Screens.cursor()
        let (config, diagnostics) = configStore.load()
        execute(world.reload(config))
        applyConfig(diagnostics)
        if runsExec { runExec(world.config.exec) }
        status.update()
    }

    private func togglePause() {
        guard isSetUp else { return }
        if paused {
            beginManaging()
            return
        }
        guard let world else { return }
        dropPreview.hide()
        motion.stopAll()
        execute(world.releaseParked())
        tracker.unhideAllHiddenByUs()
        saveStateNow()
        hotkeys.deactivate()
        mouseUp.disarm()
        followMouse(false)
        configStore.watch(sourced: [], enabled: false) {}
        tracker.stop()
        collecting = false
        dragPending = false
        delayedPending = false
        paused = true
        borders.removeAll()
        dims.removeAll()
        status.update()
    }

    private func trackerEvent(_ event: PlatformEvent) {
        guard collecting else { return handle(event) }
        switch event {
        case .windowAppeared(let snapshot):
            startupWindows.removeAll { $0.id == snapshot.id }
            startupWindows.append(snapshot)
        case .windowDisappeared(let id):
            startupWindows.removeAll { $0.id == id }
        case .appTerminated(let pid):
            startupWindows.removeAll { $0.pid == pid }
        case .windowSuspended, .windowResumed, .appHidden:
            startupEvents.append(event)
        case .focusChanged:
            startupFocus = event
        default:
            break
        }
    }

    private func handle(_ event: PlatformEvent) {
        guard let world, !paused else { return }
        var event = event
        switch event {
        case .windowDisappeared(let id): motion.cancel(id)
        case .appTerminated(let pid): for w in world.windows.values where w.pid == pid { motion.cancel(w.id) }
        case .windowFrameChanged(let id, let frame, userDriven: true) where motion.isMoving(id):
            event = .windowFrameChanged(id, frame, userDriven: false)
        default: break
        }
        world.cursor = Screens.cursor()
        execute(world.handle(event))
        switch event {
        case .windowFrameChanged(_, _, userDriven: true): updateDropPreview()
        case .dragEnded: dropPreview.hide()
        default: break
        }
    }

    private func readBack(_ id: WindowID) {
        guard let pid = world?.windows[id]?.pid else { return }
        tracker.threads[pid]?.readFrame(id) { [weak self] frame in
            guard let frame else { return }
            self?.handle(.windowFrameChanged(id, frame, userDriven: false))
            self?.borders.move(id, frame)
            self?.dims.move(id, frame)
        }
    }

    private func updateDropPreview() {
        guard let world, let frame = world.dropPreview(cursor: Screens.cursor()) else { return dropPreview.hide() }
        dropPreview.show(frame, border: world.config.general.activeBorder)
    }

    private func dispatch(_ command: Command) {
        guard let world, !paused else { return }
        world.cursor = Screens.cursor()
        execute(world.run(command).effects)
    }

    private func runBinds(_ binds: [Bind]) {
        guard let world, !paused, !binds.isEmpty else { return }
        tracker.pruneAll()
        world.cursor = Screens.cursor()
        var effects: [Effect] = []
        for bind in binds {
            switch CommandParser.parse(dispatcher: bind.dispatcher, arguments: bind.arguments) {
            case .success(let command): effects += world.run(command).effects
            case .failure(let error): log.error("\(bind.location.file, privacy: .public):\(bind.location.line): \(error.message, privacy: .public)")
            }
        }
        execute(effects)
    }

    private func runExec(_ commands: [ExecCommand]) {
        guard let world, !commands.isEmpty else { return }
        world.cursor = Screens.cursor()
        var effects: [Effect] = []
        for c in commands {
            if case .success(let command) = CommandParser.parse(dispatcher: c.raw ? "execr" : "exec", arguments: c.command) {
                effects += world.run(command).effects
            }
        }
        execute(effects)
    }

    private func execute(_ effects: [Effect]) {
        guard !effects.isEmpty else { return }
        executor.execute(effects)
        decorate()
    }

    private func decorate() {
        guard let world, !paused else { return }
        let c = world.config
        let angleLeaf = c.animations.leaf("borderangle")
        let angle = Motion.decorationTiming("borderangle", config: c).map { (timing: $0, loop: angleLeaf.style == "loop") }
        let set = world.decorations()
        let animating = motion.animating
        let ringed = dims.apply(set, animating: animating,
                                timing: Motion.timing("fadeDim", config: c, environment: MotionEngine.environment),
                                noAnim: { [weak world] id in world?.motion(for: id).noAnim ?? false },
                                monitorFrame: { [weak world] id in world?.monitorFrame(of: id) })
        borders.apply(set, animating: animating,
                      radius: c.macos.borderRadius >= 0 ? Double(c.macos.borderRadius) : BorderWindows.defaultRadius(),
                      colorTiming: Motion.decorationTiming("border", config: c), angle: angle)
        if let ringed { borders.reorder(ringed) }
    }

    private func saveStateNow() {
        if let world, !collecting { stateStore.saveNow(world.snapshot()) }
    }

    private func scheduleSave() {
        stateStore.schedule { [weak self] in
            guard let self, !self.collecting else { return nil }
            return self.world?.snapshot()
        }
    }

    private func appEffect(_ effect: Effect) {
        switch effect {
        case .submapChanged:
            DispatchQueue.main.async { [weak self] in
                self?.refreshHotkeys()
            }
        case .statusChanged:
            status.update()
        case .saveState:
            scheduleSave()
        case .reloadConfig:
            reloadConfig(fromSocket: handlingSocket)
        case .exitApp:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
        default:
            break
        }
    }

    private func ipc(_ raw: String) -> String {
        guard let world else { return "HyprOSX is waiting for Accessibility permission" }
        if paused { return "HyprOSX is paused" }
        tracker.pruneAll()
        world.cursor = Screens.cursor()
        let autoreload = world.config.misc.disableAutoreload
        let reply = IPCResponder.handle(raw, world: world, version: Self.version, configErrors: allErrors, perfReport: { perfReport() })
        handlingSocket = true
        defer { handlingSocket = false }
        execute(reply.effects)
        if reply.configChanged {
            refreshHotkeys()
            followMouse(world.config.input.followMouse == 1)
            if world.config.misc.disableAutoreload != autoreload { watchConfig() }
        }
        return reply.text
    }

    private func screensChanged() {
        guard isSetUp else { return }
        let monitors = Screens.current()
        tracker.screenSizes = monitors.map(\.frame.size)
        handle(.monitorsChanged(monitors))
    }

    private func mouseReleased() {
        dropPreview.hide()
        if delayedPending {
            delayedPending = false
            tracker.threads.values.forEach { $0.flushDelayed() }
        }
        if dragPending {
            dragPending = false
            handle(.dragEnded(cursor: Screens.cursor()))
        }
    }

    private func statusState() -> StatusState {
        guard let world else { return StatusState(trusted: isSetUp || AXIsProcessTrusted(), errors: allErrors) }
        let current = world.activeWorkspace[world.focusedMonitor]
        let workspaces = world.workspaces.values.filter { !$0.isSpecial }.sorted { $0.id < $1.id }
            .map { StatusWorkspace(id: $0.id, name: $0.name, active: $0.id == current) }
        let name = current.flatMap { world.workspaces[$0]?.name } ?? "-"
        return StatusState(title: paused ? "\(name) ⏸" : name, trusted: true, paused: paused, workspaces: workspaces, errors: allErrors)
    }

    private func perfReport() -> String {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        let rss = result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
        let threads = (tracker?.threads.values).map { Array($0) } ?? []
        var lines = [
            String(format: "cpu time: %.2f s", cpu),
            String(format: "resident memory: %.1f MB", rss),
            String(format: "uptime: %.0f s", Date().timeIntervalSince(launched)),
            "tracked apps: \(threads.count)",
            "ax writes: \(threads.reduce(0) { $0 + $1.callCount }), errors: \(threads.reduce(0) { $0 + $1.errorCount })",
        ]
        for thread in threads.sorted(by: { $0.averageLatencyMs > $1.averageLatencyMs }).prefix(5) {
            lines.append(String(format: "  %@: %.2f ms average", thread.appName, thread.averageLatencyMs))
        }
        return lines.joined(separator: "\n")
    }
}
