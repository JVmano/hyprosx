import Foundation

public final class World {
    public private(set) var config: Config
    public internal(set) var monitors: [MonitorInfo] = []
    public internal(set) var workspaces: [Int: Workspace] = [:]
    public internal(set) var windows: [WindowID: ManagedWindow] = [:]
    public internal(set) var activeWorkspace: [Int: Int] = [:]
    public internal(set) var activeSpecial: [Int: Int] = [:]
    public internal(set) var focusedMonitor = 0
    public internal(set) var focusedWindow: WindowID?
    public internal(set) var focusHistory: [WindowID] = []
    public internal(set) var submap = ""
    public var cursor = Point(x: 1e9, y: 1e9)
    public var isStartingUp = false
    var lastKnownMonitors: [MonitorInfo] = []
    var ignored: Set<WindowID> = []
    var previousWorkspace: Int?
    var previousPerMonitor: [Int: Int] = [:]
    var lastActiveByMonitorName: [String: Int] = [:]
    var nextNamedID = 1_000_000
    var spawnRules: [Int: String] = [:]
    var pidRules: [Int32: String] = [:]
    var nextSpawnToken = 1
    var dragging: WindowID?
    var dragIsResize = false
    var placementOrder: [WindowID] = []
    var effects: [Effect] = []

    static let extent = 100_000.0

    static func bounded(_ v: Double) -> Double { v.isFinite ? min(max(v, -extent), extent) : 0 }

    static func bounded(_ e: Edges) -> Edges {
        Edges(top: bounded(e.top), right: bounded(e.right), bottom: bounded(e.bottom), left: bounded(e.left))
    }

    static func borderWidth(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), extent) : 0 }

    public init(config: Config) { self.config = config }

    public func handle(_ event: PlatformEvent) -> [Effect] {
        apply(event)
        return takeEffects()
    }

    func apply(_ event: PlatformEvent) {
        switch event {
        case .monitorsChanged(let infos): setMonitors(infos)
        case .windowAppeared(let s): addWindow(s)
        case .windowDisappeared(let id): removeWindow(id)
        case .windowSuspended(let id, let reason): suspend(id, reason)
        case .windowResumed(let id): resume(id)
        case .appHidden(let pid, let byUser): appHidden(pid, byUser: byUser)
        case .appUnhidden(let pid):
            for id in windowIDs(ofApp: pid) where windows[id]?.suspended == .appHidden { resume(id) }
        case .appTerminated(let pid):
            for id in windowIDs(ofApp: pid) { removeWindow(id) }
        case .windowTitleChanged(let id, let title, let early): retitle(id, title, early: early)
        case .windowFrameChanged(let id, let frame, let userDriven): frameChanged(id, frame, userDriven: userDriven)
        case .dragEnded(let point): endDrag(at: point)
        case .focusChanged(let id): nativeFocusChanged(id)
        case .cursorMoved(let point): cursorMoved(point)
        }
    }

    public func reload(_ newConfig: Config) -> [Effect] {
        config = newConfig
        refresh(Set(workspaces.keys))
        emit(.statusChanged)
        return takeEffects()
    }

    public func registerSpawn(token: Int, pid: Int32) {
        if let rules = spawnRules.removeValue(forKey: token) { pidRules[pid] = rules }
    }

    public var activeBinds: [Bind] { config.binds.filter { $0.submap == submap || $0.flags.contains(.universal) } }

    func emit(_ e: Effect) { effects.append(e) }

    func takeEffects() -> [Effect] {
        var frames: [FrameChange] = []
        var parks: [ParkRequest] = []
        var others: [Effect] = []
        var status = false, save = false
        for e in effects {
            switch e {
            case .setFrames(let list):
                for c in list {
                    frames.removeAll { $0.id == c.id }
                    parks.removeAll { $0.id == c.id }
                    frames.append(c)
                }
            case .park(let list):
                for p in list {
                    frames.removeAll { $0.id == p.id }
                    parks.removeAll { $0.id == p.id }
                    parks.append(p)
                }
            case .statusChanged: status = true
            case .saveState: save = true
            default: others.append(e)
            }
        }
        effects = []
        var out: [Effect] = []
        if !frames.isEmpty { out.append(.setFrames(frames)) }
        if !parks.isEmpty { out.append(.park(parks)) }
        out += others
        if status { out.append(.statusChanged) }
        if save { out.append(.saveState) }
        return out
    }

    func monitor(_ id: Int) -> MonitorInfo? { monitors.first { $0.id == id } }

    func monitorID(containing p: Point) -> Int? { monitors.first { $0.frame.contains(p) }?.id }

    func resolveMonitor(_ s: String) -> Int? {
        if let n = Int(s) { return monitor(n)?.id }
        if s.hasPrefix("desc:") {
            let d = String(s.dropFirst(5))
            return monitors.first { $0.name.localizedCaseInsensitiveContains(d) }?.id
        }
        return monitors.first { $0.name == s }?.id ?? monitors.first { $0.name.localizedCaseInsensitiveContains(s) }?.id
    }

    func isVisible(_ wsID: Int) -> Bool {
        activeWorkspace.values.contains(wsID) || activeSpecial.values.contains(wsID)
    }

    func facts(of ws: Workspace) -> WorkspaceFacts {
        let tiled = ws.tiledIDs.count
        let fullscreen = ws.windowIDs.compactMap { windows[$0]?.fullscreenMode }.first ?? -1
        return WorkspaceFacts(id: ws.id, name: ws.name, isSpecial: ws.isSpecial, monitorName: monitor(ws.monitor)?.name ?? "",
                              tiledCount: tiled, floatingCount: ws.floating.count, fullscreenMode: fullscreen)
    }

    func rules(for ws: Workspace) -> [WorkspaceRule] {
        let f = facts(of: ws)
        return config.workspaceRules.filter { $0.matches(f, monitorMatches: { self.resolveMonitor($0) == ws.monitor }) }
    }

    func gapsIn(for ws: Workspace) -> Edges { World.bounded(rules(for: ws).compactMap(\.gapsIn).last ?? config.general.gapsIn) }

    func borderSize(for ws: Workspace) -> Double {
        let r = rules(for: ws)
        if r.compactMap(\.border).last == false { return 0 }
        return World.borderWidth(Double(r.compactMap(\.borderSize).last ?? config.general.borderSize))
    }

    func fullscreenArea(for ws: Workspace) -> Rect {
        guard let m = monitor(ws.monitor) else { return .zero }
        return m.visibleFrame.inset(by: World.bounded(config.reservedAreas[m.name] ?? config.reservedAreas[""] ?? .zero))
    }

    func workArea(for ws: Workspace) -> Rect {
        let gapsOut = World.bounded(rules(for: ws).compactMap(\.gapsOut).last ?? config.general.gapsOut)
        var area = fullscreenArea(for: ws).inset(by: gapsOut)
        if ws.isSpecial {
            let raw = ws.layout.kind == .master ? config.master.specialScaleFactor : config.dwindle.specialScaleFactor
            let f = raw.isFinite ? min(max(raw, 0), 1) : 1
            area = Rect(x: area.x + area.width * (1 - f) / 2, y: area.y + area.height * (1 - f) / 2,
                        width: area.width * f, height: area.height * f)
        }
        return area
    }

    func layoutContext(_ ws: Workspace, focalPoint: Point? = nil) -> LayoutContext {
        let focused = focusedWindow.flatMap { windows[$0]?.workspace == ws.id ? $0 : nil } ?? ws.lastFocused
        return LayoutContext(workArea: workArea(for: ws), focused: focused, cursor: cursor, focalPoint: focalPoint,
                             isFirstMap: true, dragging: dragging != nil, dwindle: config.dwindle, master: config.master)
    }

    func idealBoxes(_ ws: Workspace) -> [WindowID: Rect] {
        var out = effectiveBoxes(ws)
        for id in ws.floating { if let w = windows[id] { out[id] = w.floatingFrame } }
        return out
    }

    func targetFrames(_ ws: Workspace) -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        let ctx = layoutContext(ws)
        let gaps = gapsIn(for: ws)
        let border = borderSize(for: ws)
        let placements = activePlacements(ws, area: ctx.workArea)
        for (id, box) in effectiveBoxes(ws) {
            guard let w = windows[id], w.suspended == nil else { continue }
            out[id] = placements[id] ?? tileFrame(w, box: box, ctx: ctx, gaps: gaps, border: border)
        }
        let visible = monitor(ws.monitor)?.visibleFrame
        for id in ws.floating { if let w = windows[id], w.suspended == nil { out[id] = World.reachable(w.floatingFrame, in: visible) } }
        for id in ws.windowIDs {
            guard let w = windows[id], w.suspended == nil, let mode = w.fullscreenMode else { continue }
            out[id] = mode == 0 ? fullscreenArea(for: ws) : ctx.workArea.inset(by: Edges(all: border))
        }
        return out
    }

    func tileFrame(_ w: ManagedWindow, box: Rect, ctx: LayoutContext, gaps: Edges, border: Double) -> Rect {
        let b = borderWidth(of: w, rules: dynamicOutcome(for: w), fallback: border)
        return WindowGeometry.frame(tile: box, workArea: ctx.workArea, gapsIn: gaps, borderSize: b, pseudoSize: w.isPseudo ? w.pseudoSize : nil)
    }

    static func reachable(_ f: Rect, in visible: Rect?) -> Rect {
        guard let v = visible, !v.contains(f.center) else { return f }
        let w = min(f.width, v.width), h = min(f.height, v.height)
        return Rect(x: min(max(f.x, v.minX), v.maxX - w), y: min(max(f.y, v.minY), v.maxY - h), width: w, height: h)
    }

    func shiftFloating(_ ids: [WindowID], from old: Rect?, to new: Rect?) {
        guard let old, let new else { return }
        let dx = new.x - old.x, dy = new.y - old.y
        guard dx != 0 || dy != 0 else { return }
        for id in ids {
            windows[id]?.floatingFrame.x += dx
            windows[id]?.floatingFrame.y += dy
        }
    }

    func windowIDs(inWorkspace wsID: Int) -> [WindowID] {
        windows.values.filter { $0.workspace == wsID }.map(\.id).sorted()
    }

    func refresh(_ ids: Set<Int>, reason: FrameReason = .layout, opened: WindowID? = nil, skip: WindowID? = nil, slide: SlideOut? = nil) {
        var changes: [FrameChange] = []
        var parkList: [ParkRequest] = []
        for wsID in ids.sorted() {
            guard let ws = workspaces[wsID], let mon = monitor(ws.monitor) else { continue }
            if isVisible(wsID) {
                reconcilePlacements(ws)
                for (id, frame) in targetFrames(ws).sorted(by: { $0.key < $1.key }) where id != skip {
                    guard var w = windows[id] else { continue }
                    let stale = w.appliedFrame.map { !$0.isClose(to: frame) } ?? true
                    if w.isParked || stale {
                        changes.append(FrameChange(id: id, frame: frame, reason: id == opened ? .open : reason))
                        w.appliedFrame = frame
                        w.refitTarget = nil
                        w.isParked = false
                        windows[id] = w
                    }
                }
            } else {
                for id in ws.windowIDs {
                    guard var w = windows[id], !w.isParked, w.suspended == nil else { continue }
                    let size = (w.appliedFrame ?? w.lastFrame).size
                    parkList.append(ParkRequest(id: id, origin: Parking.origin(windowSize: size, monitor: mon, among: monitors, bundleID: w.bundleID), slide: slide))
                    w.isParked = true
                    windows[id] = w
                }
            }
        }
        if !changes.isEmpty { emit(.setFrames(changes)) }
        if !parkList.isEmpty { emit(.park(parkList)) }
    }

    func lowestUnusedID() -> Int {
        var id = 1
        while workspaces[id] != nil { id += 1 }
        return id
    }

    @discardableResult
    func ensureWorkspace(_ id: Int, name: String? = nil, special: Bool = false, monitor: Int? = nil, createdEmpty: Bool = false) -> Int {
        if workspaces[id] != nil { return id }
        var ws = Workspace(id: id, name: name ?? (special ? "special" : String(id)), monitor: monitor ?? focusedMonitor,
                           homeMonitorName: "", isSpecial: special, layout: LayoutState(.dwindle))
        let matched = rules(for: ws)
        if monitor == nil, let m = matched.compactMap(\.monitor).last.flatMap(resolveMonitor) { ws.monitor = m }
        ws.homeMonitorName = self.monitor(ws.monitor)?.name ?? ""
        ws.layout = LayoutState(LayoutKind(rawValue: matched.compactMap(\.layout).last ?? config.general.layout) ?? .dwindle)
        if case .master(var m) = ws.layout, let o = matched.compactMap(\.orientation).last {
            m.orientationOverride = o
            ws.layout = .master(m)
        }
        ws.persistent = matched.compactMap(\.persistent).last ?? false
        if name == nil, !special, let dn = matched.compactMap(\.defaultName).last { ws.name = dn }
        workspaces[id] = ws
        if createdEmpty, let cmd = matched.compactMap(\.onCreatedEmpty).last { emit(.spawn(cmd, token: nil)) }
        return id
    }

    func destroyIfUnused(_ id: Int) {
        guard let ws = workspaces[id], ws.windowIDs.isEmpty, !ws.persistent, !isVisible(id) else { return }
        if windows.values.contains(where: { $0.workspace == id }) { return }
        workspaces[id] = nil
    }

    func detach(_ id: WindowID) {
        guard let w = windows[id], var ws = workspaces[w.workspace] else { return }
        clearPlacement(id)
        ws.layout.update { $0.remove(id) }
        ws.floating.removeAll { $0 == id }
        if ws.lastFocused == id { ws.lastFocused = nil }
        workspaces[ws.id] = ws
    }

    func attach(_ id: WindowID, to wsID: Int, focalPoint: Point? = nil) {
        guard var w = windows[id], var ws = workspaces[wsID] else { return }
        w.workspace = wsID
        windows[id] = w
        if w.isFloating {
            ws.floating.append(id)
        } else {
            let ctx = layoutContext(ws, focalPoint: focalPoint)
            ws.layout.update { $0.insert(id, ctx) }
        }
        workspaces[wsID] = ws
    }

    func facts(for w: ManagedWindow) -> WindowFacts {
        let mon = workspaces[w.workspace].flatMap { monitor($0.monitor) } ?? monitors.first
        let origin = mon?.frame.origin ?? .zero
        let frame = w.appliedFrame ?? w.lastFrame
        return WindowFacts(bundleID: w.bundleID, appName: w.appName, title: w.title, initialTitle: w.initialTitle,
                           isFloating: w.isFloating, isFullscreen: w.fullscreenMode != nil, isPinned: w.isPinned,
                           isFocused: focusedWindow == w.id, isModal: w.isModal, workspaceID: w.workspace,
                           workspaceName: workspaces[w.workspace]?.name,
                           monitorSize: mon?.frame.size ?? Size(width: 0, height: 0),
                           windowFrame: Rect(x: frame.x - origin.x, y: frame.y - origin.y, width: frame.width, height: frame.height),
                           cursor: cursor - origin)
    }

    func staticOutcome(for w: ManagedWindow) -> StaticRuleOutcome {
        RuleEngine.staticOutcome(windowRules(forPID: w.pid), facts(for: w))
    }

    func resolveRuleWorkspace(_ selector: String) -> Int? {
        let s = selector.trimmingCharacters(in: .whitespaces)
        if let n = boundedInt(s) { return n >= 1 ? ensureWorkspace(n) : nil }
        if s.hasPrefix("name:") {
            let name = String(s.dropFirst(5))
            guard !name.isEmpty else { return nil }
            if let ws = workspaces.values.first(where: { !$0.isSpecial && $0.name == name }) { return ws.id }
            while workspaces[nextNamedID] != nil { nextNamedID += 1 }
            let id = nextNamedID
            nextNamedID += 1
            return ensureWorkspace(id, name: name)
        }
        if s == "special" || s.hasPrefix("special:") {
            let name = s == "special" ? "special" : String(s.dropFirst(8))
            guard !name.isEmpty else { return nil }
            if let ws = workspaces.values.first(where: { $0.isSpecial && $0.name == name }) { return ws.id }
            guard let id = name == "special" ? -99 : (-98 ... -1).first(where: { workspaces[$0] == nil }) else { return nil }
            return ensureWorkspace(id, name: name, special: true)
        }
        return nil
    }

    func setMonitors(_ infos: [MonitorInfo]) {
        let sorted = infos.sorted { $0.id < $1.id }
        let layoutChanged = sorted != monitors
        let previous = monitors
        monitors = sorted
        if !sorted.isEmpty { lastKnownMonitors = sorted }
        guard let primary = monitors.first?.id else { return }
        let ids = Set(monitors.map(\.id))
        for (id, var ws) in workspaces {
            let was = ws.monitor
            if let home = monitors.first(where: { $0.name == ws.homeMonitorName }) { ws.monitor = home.id }
            else if !ids.contains(ws.monitor) { ws.monitor = primary }
            workspaces[id] = ws
            shiftFloating(windowIDs(inWorkspace: id), from: previous.first { $0.id == was }?.frame, to: monitor(ws.monitor)?.frame)
        }
        activeWorkspace = activeWorkspace.filter { ids.contains($0.key) && workspaces[$0.value]?.monitor == $0.key }
        activeSpecial = activeSpecial.filter { ids.contains($0.key) && workspaces[$0.value]?.monitor == $0.key }
        for m in monitors where activeWorkspace[m.id] == nil {
            let remembered = lastActiveByMonitorName[m.name].flatMap { workspaces[$0]?.monitor == m.id ? $0 : nil }
            let ruleDefault = config.workspaceRules.first { r in
                r.isDefault == true && r.monitor.flatMap(resolveMonitor) == m.id
            }.flatMap { r -> Int? in
                if case .id(let n) = r.selector, !activeWorkspace.values.contains(n) { return n }
                return nil
            }
            let hidden = workspaces.values.filter { $0.monitor == m.id && !$0.isSpecial && !activeWorkspace.values.contains($0.id) }.map(\.id).min()
            let chosen = remembered ?? ruleDefault ?? hidden ?? lowestUnusedID()
            ensureWorkspace(chosen, monitor: m.id)
            let prior = workspaces[chosen]?.monitor
            workspaces[chosen]?.monitor = m.id
            if let prior, prior != m.id { shiftFloating(windowIDs(inWorkspace: chosen), from: monitor(prior)?.frame, to: m.frame) }
            activeWorkspace[m.id] = chosen
            lastActiveByMonitorName[m.name] = chosen
        }
        if !ids.contains(focusedMonitor) { focusedMonitor = primary }
        settleFocus()
        if layoutChanged {
            for (id, w) in windows where w.isParked && !isVisible(w.workspace) { windows[id]?.isParked = false }
        }
        refresh(Set(workspaces.keys))
        emit(.statusChanged)
    }

    func addWindow(_ s: WindowSnapshot) {
        guard windows[s.id] == nil, !ignored.contains(s.id), let first = monitors.first else { return }
        let homeMonitor = isStartingUp ? (monitorID(containing: s.frame.center) ?? focusedMonitor) : focusedMonitor
        var target = activeWorkspace[homeMonitor] ?? ensureWorkspace(lowestUnusedID(), monitor: homeMonitor)
        var w = ManagedWindow(id: s.id, pid: s.pid, bundleID: s.bundleID, appName: s.appName, title: s.title, initialTitle: s.title,
                              isModal: s.kind == .dialog, workspace: target, isFloating: s.kind == .dialog, floatingFrame: s.frame,
                              lastFrame: s.frame)
        let outcome = staticOutcome(for: w)
        if outcome.ignore { ignored.insert(s.id); return }
        var silent = false
        if let t = outcome.workspace, let id = resolveRuleWorkspace(t.selector) {
            target = id
            silent = t.silent
        }
        if let m = outcome.monitor.flatMap(resolveMonitor), let active = activeWorkspace[m] { target = active }
        w.workspace = target
        w.isFloating = outcome.floating ?? (s.kind == .dialog)
        let mon = workspaces[target].flatMap { monitor($0.monitor) } ?? first
        var frame = s.frame
        let v = mon.visibleFrame
        frame.x = min(max(frame.x, v.minX), max(v.minX, v.maxX - frame.width))
        frame.y = min(max(frame.y, v.minY), max(v.minY, v.maxY - frame.height))
        let f = facts(for: w)
        if let size = outcome.size.flatMap({ RuleEngine.resolveSize($0, f) }) {
            frame.width = min(max(size.width, 1), World.extent)
            frame.height = min(max(size.height, 1), World.extent)
        }
        if let move = outcome.move.flatMap({ RuleEngine.resolveMove($0, f) }) {
            frame.x = mon.frame.x + World.bounded(move.x)
            frame.y = mon.frame.y + World.bounded(move.y)
        }
        if outcome.center, let ws = workspaces[target] {
            let area = workArea(for: ws)
            frame.x = area.x + (area.width - frame.width) / 2
            frame.y = area.y + (area.height - frame.height) / 2
        }
        w.floatingFrame = frame
        w.everFloated = w.isFloating
        if w.isFloating { w.appliedFrame = s.frame }
        if outcome.pseudo { w.isPseudo = true; w.pseudoSize = s.frame.size }
        w.isPinned = outcome.pin && w.isFloating
        if let mode = outcome.fullscreenMode {
            for other in workspaces[target]?.windowIDs ?? [] { windows[other]?.fullscreenMode = nil }
            w.fullscreenMode = mode
        }
        windows[s.id] = w
        pidRules[s.pid] = nil
        attach(s.id, to: target)
        if !isVisible(target) && !silent && outcome.workspace != nil {
            if workspaces[target]?.isSpecial == true { toggleSpecial(target, show: true, emitFocus: false) } else { switchWorkspace(target, emitFocus: false) }
        }
        refresh([target], opened: s.id)
        if isVisible(target) && !outcome.noInitialFocus {
            focusWindow(s.id, warp: false, emitEffect: true)
        } else if let previous = focusedWindow {
            emit(.focus(previous))
        }
        emit(.statusChanged)
        emit(.saveState)
    }

    func focusCandidate(onWorkspace wsID: Int, near point: Point) -> WindowID? {
        guard let ws = workspaces[wsID] else { return nil }
        let ids = ws.windowIDs.filter { windows[$0]?.suspended == nil }
        switch config.input.focusOnClose {
        case 1:
            let boxes = targetFrames(ws)
            if let hit = ids.reversed().first(where: { boxes[$0]?.contains(cursor) == true }) { return hit }
        case 2:
            if let recent = focusHistory.reversed().first(where: { ids.contains($0) }) { return recent }
        default:
            break
        }
        if let next = ws.layout.current.nextFocusCandidate(near: point, layoutContext(ws)), ids.contains(next) { return next }
        return ids.last
    }

    func removeWindow(_ id: WindowID) {
        ignored.remove(id)
        guard let w = windows[id] else { return }
        let center = (w.appliedFrame ?? w.lastFrame).center
        detach(id)
        windows[id] = nil
        focusHistory.removeAll { $0 == id }
        if dragging == id {
            dragging = nil
            dragIsResize = false
        }
        if focusedWindow == id {
            focusedWindow = nil
            if isVisible(w.workspace), let next = focusCandidate(onWorkspace: w.workspace, near: center) {
                focusWindow(next, warp: false, emitEffect: true)
            }
        }
        refresh([w.workspace])
        destroyIfUnused(w.workspace)
        closeSpecialIfEmpty(w.workspace)
        emit(.statusChanged)
        emit(.saveState)
    }

    func focusWindow(_ id: WindowID?, warp: Bool, emitEffect: Bool = true) {
        guard let id, let w = windows[id] else {
            focusedWindow = nil
            emit(.statusChanged)
            return
        }
        focusedWindow = id
        focusHistory.removeAll { $0 == id }
        focusHistory.append(id)
        workspaces[w.workspace]?.lastFocused = id
        if let m = workspaces[w.workspace]?.monitor { focusedMonitor = m }
        if emitEffect { emit(.focus(id)) }
        if warp && !config.cursor.noWarps, let f = windows[id]?.appliedFrame, !f.contains(cursor) {
            cursor = f.center
            emit(.warpCursor(f.center))
        }
        emit(.statusChanged)
    }
}
