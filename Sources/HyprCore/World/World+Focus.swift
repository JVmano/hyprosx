import Foundation

extension World {
    var visibleWorkspaceIDs: [Int] {
        monitors.flatMap { m in [activeSpecial[m.id], activeWorkspace[m.id]].compactMap { $0 } }
    }

    func allIdealBoxes() -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        for wsID in visibleWorkspaceIDs {
            if let ws = workspaces[wsID] { out.merge(idealBoxes(ws)) { a, _ in a } }
        }
        return out
    }

    static func isAdjacent(_ aMin: Double, _ aMax: Double, _ bMin: Double, _ bMax: Double) -> Bool {
        let delta = aMin - bMax
        if abs(delta) < 2 { return true }
        if delta >= 0 { return false }
        if (aMin <= bMin && aMax >= bMax) || (bMin <= aMin && bMax >= aMax) { return false }
        return -delta <= min(aMax - aMin, bMax - bMin) * 0.5
    }

    func windowInDirection(from origin: Rect, originFloating: Bool, ignoring: WindowID?, _ dir: Direction) -> WindowID? {
        let originWorkspace = ignoring.flatMap { windows[$0]?.workspace }
        let originMonitor = originWorkspace.flatMap { workspaces[$0]?.monitor }
        let boxes = allIdealBoxes().filter { id, _ in
            guard id != ignoring, let w = windows[id], w.suspended == nil else { return false }
            guard let originWorkspace, w.workspace != originWorkspace else { return true }
            return workspaces[w.workspace]?.monitor != originMonitor
        }.sorted { $0.key < $1.key }
        var rank: [WindowID: Double] = [:]
        for (i, id) in focusHistory.enumerated() { rank[id] = Double(i) }
        for preference in [originFloating, !originFloating] {
            var leader: WindowID?
            var leaderValue = -1.0
            var bestAngle = 2 * Double.pi
            for (id, box) in boxes where windows[id]?.isFloating == preference {
                if originFloating {
                    let o = origin.center, c = box.center
                    let vx = c.x - o.x, vy = c.y - o.y
                    let dist = (vx * vx + vy * vy).squareRoot()
                    guard dist > 0 else { continue }
                    let (dx, dy): (Double, Double)
                    switch dir {
                    case .right: (dx, dy) = (1, 0)
                    case .left: (dx, dy) = (-1, 0)
                    case .up: (dx, dy) = (0, -1)
                    case .down: (dx, dy) = (0, 1)
                    }
                    let angle = acos(max(-1, min(1, (vx * dx + vy * dy) / dist)))
                    if angle > Double.pi / 2 { continue }
                    let threshold = 0.3 * Double.pi
                    if (bestAngle < threshold && dist < leaderValue && angle < threshold) || (angle < bestAngle && bestAngle > threshold) || leaderValue == -1 {
                        leader = id
                        leaderValue = dist
                        bestAngle = angle
                    }
                    continue
                }
                let adjacent: Bool
                let overlap: Double
                switch dir {
                case .left:
                    adjacent = World.isAdjacent(origin.minX, origin.maxX, box.minX, box.maxX)
                    overlap = min(origin.maxY, box.maxY) - max(origin.minY, box.minY)
                case .right:
                    adjacent = World.isAdjacent(box.minX, box.maxX, origin.minX, origin.maxX)
                    overlap = min(origin.maxY, box.maxY) - max(origin.minY, box.minY)
                case .up:
                    adjacent = World.isAdjacent(origin.minY, origin.maxY, box.minY, box.maxY)
                    overlap = min(origin.maxX, box.maxX) - max(origin.minX, box.minX)
                case .down:
                    adjacent = World.isAdjacent(box.minY, box.maxY, origin.minY, origin.maxY)
                    overlap = min(origin.maxX, box.maxX) - max(origin.minX, box.minX)
                }
                guard adjacent, overlap > 1 else { continue }
                let value = config.bindsOptions.focusPreferredMethod == 1 ? overlap : (rank[id] ?? -0.5)
                if value > leaderValue {
                    leader = id
                    leaderValue = value
                }
            }
            if let leader { return leader }
        }
        return nil
    }

    func focusAndRaise(_ id: WindowID) {
        focusWindow(id, warp: true, emitEffect: true)
        emit(.raise(id))
    }

    func focusAnywhere(_ id: WindowID) {
        guard let w = windows[id], w.suspended == nil else { return }
        if isVisible(w.workspace) {
            focusWindow(id, warp: true, emitEffect: true)
        } else {
            if workspaces[w.workspace]?.isSpecial == true {
                toggleSpecial(w.workspace, show: true, focusing: id)
            } else {
                switchWorkspace(w.workspace, focusing: id)
            }
            guard let moved = windows[id], isVisible(moved.workspace) else { return }
            focusWindow(id, warp: true, emitEffect: false)
        }
        emit(.raise(id))
    }

    func moveFocus(_ d: Direction) {
        guard let f = focusedWindow, let w = windows[f], let ws = workspaces[w.workspace], let box = idealBoxes(ws)[f] else {
            if config.bindsOptions.windowDirectionMonitorFallback, let m = monitorInDirection(from: focusedMonitor, d) { focusMonitor(m) }
            return
        }
        if !w.isFloating, case .monocle(let m) = ws.layout {
            if let n = m.neighbor(of: f, forward: d == .right || d == .down) { focusAndRaise(n) }
            return
        }
        if config.bindsOptions.movefocusCyclesFullscreen, w.fullscreenMode != nil {
            var o = CycleOptions()
            o.previous = d == .left || d == .up
            cycle(o)
            return
        }
        if let target = windowInDirection(from: box, originFloating: w.isFloating, ignoring: f, d) {
            focusAndRaise(target)
            return
        }
        if config.bindsOptions.windowDirectionMonitorFallback, let m = monitorInDirection(from: ws.monitor, d) {
            focusMonitor(m)
            return
        }
        if config.general.noFocusFallback { return }
        let area = workArea(for: ws)
        if (d == .left || d == .right) && WindowGeometry.sticks(box.minX, area.minX) && WindowGeometry.sticks(box.maxX, area.maxX) { return }
        if (d == .up || d == .down) && WindowGeometry.sticks(box.minY, area.minY) && WindowGeometry.sticks(box.maxY, area.maxY) { return }
        let strip: Rect
        switch d {
        case .left: strip = Rect(x: area.maxX, y: area.minY, width: 1, height: area.height)
        case .right: strip = Rect(x: area.minX - 1, y: area.minY, width: 1, height: area.height)
        case .up: strip = Rect(x: area.minX, y: area.maxY, width: area.width, height: 1)
        case .down: strip = Rect(x: area.minX, y: area.minY - 1, width: area.width, height: 1)
        }
        if let target = windowInDirection(from: strip, originFloating: w.isFloating, ignoring: f, d) { focusAndRaise(target) }
    }

    func cycle(_ o: CycleOptions) {
        let home = focusedWindow.flatMap { windows[$0]?.workspace } ?? currentWorkspaceID
        let wsIDs = o.visible ? visibleWorkspaceIDs : [home].compactMap { $0 }
        var list = wsIDs.flatMap { workspaces[$0]?.windowIDs ?? [] }
        if o.tiledOnly { list = list.filter { windows[$0]?.isFloating == false } }
        if o.floatingOnly { list = list.filter { windows[$0]?.isFloating == true } }
        if o.history {
            let members = Set(list)
            let known = Set(focusHistory)
            list = focusHistory.reversed().filter(members.contains) + list.filter { !known.contains($0) }
        }
        guard !list.isEmpty else { return }
        let next: WindowID
        if let f = focusedWindow, let i = list.firstIndex(of: f) {
            next = list[(i + (o.previous ? list.count - 1 : 1)) % list.count]
        } else {
            next = (o.previous ? list.last : list.first) ?? list[0]
        }
        focusAndRaise(next)
    }

    func matchingWindows(_ sel: WindowSelector) -> [WindowID] {
        let ordered = windows.keys.sorted().filter { windows[$0]?.suspended == nil }
        func classes(_ w: ManagedWindow) -> [String] { w.bundleID.isEmpty ? [w.appName] : [w.bundleID, w.appName] }
        let current = focusedWindow.flatMap { windows[$0]?.workspace } ?? currentWorkspaceID
        switch sel {
        case .active: return focusedWindow.map { [$0] } ?? []
        case .classRegex(let r), .initialClass(let r):
            guard let rx = RuleRegex(r) else { return [] }
            return ordered.filter { windows[$0].map { rx.matchesAny(classes($0)) } ?? false }
        case .title(let r):
            guard let rx = RuleRegex(r) else { return [] }
            return ordered.filter { windows[$0].map { rx.matches($0.title) } ?? false }
        case .initialTitle(let r):
            guard let rx = RuleRegex(r) else { return [] }
            return ordered.filter { windows[$0].map { rx.matches($0.initialTitle) } ?? false }
        case .pid(let p): return ordered.filter { windows[$0]?.pid == p }
        case .address(let a): return ordered.filter { $0 == a }
        case .floating: return (current.flatMap { workspaces[$0]?.floating } ?? []).prefix(1).map { $0 }
        case .tiled: return (current.flatMap { workspaces[$0]?.tiledIDs } ?? []).prefix(1).map { $0 }
        case .tag: return []
        }
    }
}
