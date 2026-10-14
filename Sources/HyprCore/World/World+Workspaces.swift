import Foundation

extension World {
    static let idLimit = Int(Int32.max)

    static func clampOffset(_ n: Int) -> Int { min(max(n, -idLimit), idLimit) }

    func isUsableID(_ id: Int) -> Bool { workspaces[id] != nil || (1 ... World.idLimit).contains(id) }

    static func wrapped(_ i: Int, by n: Int, count: Int) -> Int {
        ((i + n % count) % count + count) % count
    }

    func resolveMonitor(_ sel: MonitorSelector) -> Int? {
        switch sel {
        case .current: return monitor(focusedMonitor)?.id
        case .id(let n): return monitor(n)?.id
        case .name(let n): return resolveMonitor(n)
        case .relative(let n):
            let sorted = monitors.sorted { ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id) }
            guard let i = sorted.firstIndex(where: { $0.id == focusedMonitor }) else { return nil }
            return sorted[World.wrapped(i, by: n, count: sorted.count)].id
        case .direction(let d): return monitorInDirection(from: focusedMonitor, d)
        }
    }

    func monitorInDirection(from id: Int, _ d: Direction) -> Int? {
        guard let f = monitor(id)?.frame else { return nil }
        let candidates = monitors.filter { o in
            guard o.id != id else { return false }
            let g = o.frame
            switch d {
            case .left: return g.maxX <= f.minX + 1 && g.maxY > f.minY && g.minY < f.maxY
            case .right: return g.minX >= f.maxX - 1 && g.maxY > f.minY && g.minY < f.maxY
            case .up: return g.maxY <= f.minY + 1 && g.maxX > f.minX && g.minX < f.maxX
            case .down: return g.minY >= f.maxY - 1 && g.maxX > f.minX && g.minX < f.maxX
            }
        }
        func distance(_ g: Rect) -> Double {
            let a = g.center, b = f.center
            return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
        }
        return candidates.min { distance($0.frame) < distance($1.frame) }?.id
    }

    var currentWorkspaceID: Int? { activeWorkspace[focusedMonitor] }

    func resolveWorkspace(_ sel: WorkspaceSelector) -> Int? {
        let current = currentWorkspaceID ?? 1
        let regular = workspaces.values.filter { !$0.isSpecial }.map(\.id).sorted()
        let onMonitor = regular.filter { workspaces[$0]?.monitor == focusedMonitor }
        func step(_ list: [Int], _ n: Int) -> Int? {
            guard !list.isEmpty else { return nil }
            guard let i = list.firstIndex(of: current) else { return list.first }
            return list[World.wrapped(i, by: n, count: list.count)]
        }
        func shifted(_ n: Int) -> Int { max(1, min(current + World.clampOffset(n), World.idLimit)) }
        switch sel {
        case .id(let n): return n >= 1 ? min(n, World.idLimit) : nil
        case .relative(let n): return shifted(n)
        case .name(let s): return resolveRuleWorkspace("name:" + s)
        case .special(let n): return resolveRuleWorkspace(n.map { "special:" + $0 } ?? "special")
        case .previous: return previousWorkspace
        case .previousPerMonitor: return previousPerMonitor[focusedMonitor]
        case .existing(let n): return step(regular, n)
        case .existingAbsolute(let n): return n >= 1 && n <= regular.count ? regular[n - 1] : nil
        case .onMonitor(let n, let includeEmpty): return includeEmpty ? shifted(n) : step(onMonitor, n)
        case .onMonitorAbsolute(let n, _): return n >= 1 && n <= onMonitor.count ? onMonitor[n - 1] : nil
        case .empty(_, let next):
            let used = Set(workspaces.values.filter { !$0.isSpecial && !$0.windowIDs.isEmpty }.map(\.id))
            var candidate = next ? current + 1 : 1
            while used.contains(candidate) { candidate += 1 }
            return candidate
        }
    }

    func switchWorkspace(_ requested: Int, focusing: WindowID? = nil, emitFocus: Bool = true) {
        var target = requested
        if target == currentWorkspaceID {
            guard config.bindsOptions.workspaceBackAndForth, let previous = previousWorkspace else { return }
            target = previous
        }
        activateWorkspace(target, focusing: focusing, emitFocus: emitFocus)
    }

    func activateWorkspace(_ target: Int, focusing: WindowID?, emitFocus: Bool) {
        guard isUsableID(target) else { return }
        let current = currentWorkspaceID
        ensureWorkspace(target, createdEmpty: workspaces[target] == nil)
        guard let ws = workspaces[target] else { return }
        if ws.isSpecial {
            toggleSpecial(target, show: true, focusing: focusing, emitFocus: emitFocus)
            return
        }
        let mon = ws.monitor
        let old = activeWorkspace[mon]
        if old == target {
            if let current, current != target { previousWorkspace = current }
            focusedMonitor = mon
            focusWindow(focusing ?? ws.lastFocused ?? ws.windowIDs.first, warp: true, emitEffect: emitFocus)
            focusedMonitor = mon
            return
        }
        previousWorkspace = current
        if let old { previousPerMonitor[mon] = old }
        activeWorkspace[mon] = target
        if let name = monitor(mon)?.name { lastActiveByMonitorName[name] = target }
        focusedMonitor = mon
        if let old {
            for id in workspaces[old]?.floating ?? [] where windows[id]?.isPinned == true {
                detach(id)
                attach(id, to: target)
            }
        }
        if config.bindsOptions.hideSpecialOnWorkspaceChange, let special = activeSpecial[mon] {
            activeSpecial[mon] = nil
            refresh([special])
            destroyIfUnused(special)
        }
        refresh([target], reason: .workspaceIn(leftward: target > (old ?? target)))
        if let old {
            refresh([old])
            destroyIfUnused(old)
        }
        let next = workspaces[target]
        focusWindow(focusing ?? next?.lastFocused ?? next?.windowIDs.first, warp: config.cursor.warpOnChangeWorkspace > 0, emitEffect: emitFocus)
        focusedMonitor = mon
        emit(.saveState)
    }

    func toggleSpecial(_ id: Int, show: Bool? = nil, on monitorID: Int? = nil, focusing: WindowID? = nil, emitFocus: Bool = true) {
        guard workspaces[id]?.isSpecial == true else { return }
        let mon = monitorID ?? focusedMonitor
        guard let info = monitor(mon) else { return }
        let shown = activeSpecial[mon] == id
        if show ?? !shown {
            guard !shown else { return }
            if let other = activeSpecial.first(where: { $0.value == id })?.key { activeSpecial[other] = nil }
            if let previous = activeSpecial[mon] {
                activeSpecial[mon] = nil
                refresh([previous])
                destroyIfUnused(previous)
            }
            let from = workspaces[id].flatMap { monitor($0.monitor) }
            workspaces[id]?.monitor = mon
            workspaces[id]?.homeMonitorName = info.name
            shiftFloating(windowIDs(inWorkspace: id), from: from?.frame, to: info.frame)
            activeSpecial[mon] = id
            refresh([id], reason: .workspaceIn(leftward: true))
            for w in workspaces[id]?.windowIDs ?? [] { emit(.raise(w)) }
            if let c = focusing ?? workspaces[id]?.lastFocused ?? workspaces[id]?.windowIDs.first {
                focusWindow(c, warp: false, emitEffect: emitFocus)
            }
        } else {
            guard shown else { return }
            activeSpecial[mon] = nil
            refresh([id])
            if mon == focusedMonitor || focusedWindow == nil {
                let regular = activeWorkspace[mon].flatMap { workspaces[$0] }
                focusWindow(regular?.lastFocused ?? regular?.windowIDs.first, warp: false, emitEffect: emitFocus)
            }
            destroyIfUnused(id)
        }
        emit(.statusChanged)
    }

    func closeSpecialIfEmpty(_ wsID: Int) {
        guard config.misc.closeSpecialOnEmpty, let ws = workspaces[wsID], ws.isSpecial, ws.windowIDs.isEmpty,
              let mon = activeSpecial.first(where: { $0.value == wsID })?.key else { return }
        toggleSpecial(wsID, show: false, on: mon)
    }

    func moveWindow(_ id: WindowID, toWorkspace target: Int, silent: Bool, focalPoint: Point? = nil) {
        guard let w = windows[id], w.suspended == nil, w.workspace != target, isUsableID(target) else { return }
        let source = w.workspace
        let center = (w.appliedFrame ?? w.lastFrame).center
        let wasFocused = focusedWindow == id
        ensureWorkspace(target)
        shiftFloating([id], from: workspaces[source].flatMap { monitor($0.monitor) }?.frame,
                      to: workspaces[target].flatMap { monitor($0.monitor) }?.frame)
        windows[id]?.fullscreenMode = nil
        detach(id)
        attach(id, to: target, focalPoint: focalPoint)
        if silent {
            refresh([source, target])
            if wasFocused {
                focusWindow(isVisible(source) ? focusCandidate(onWorkspace: source, near: center) : nil, warp: false, emitEffect: true)
            }
        } else if workspaces[target]?.isSpecial == true {
            let alreadyShown = activeSpecial[focusedMonitor] == target
            toggleSpecial(target, show: true, focusing: id)
            refresh([source, target])
            if alreadyShown {
                emit(.raise(id))
                focusWindow(id, warp: false, emitEffect: true)
            }
        } else {
            activateWorkspace(target, focusing: id, emitFocus: true)
            refresh([source, target])
        }
        destroyIfUnused(source)
        closeSpecialIfEmpty(source)
        emit(.saveState)
    }

    func focusMonitor(_ id: Int) {
        guard let m = monitor(id) else { return }
        focusedMonitor = id
        let candidate = [activeSpecial[id], activeWorkspace[id]].lazy.compactMap { $0 }.compactMap { wsID in
            self.workspaces[wsID].flatMap { $0.lastFocused ?? $0.windowIDs.first }
        }.first
        focusWindow(candidate, warp: false, emitEffect: true)
        focusedMonitor = id
        if !m.frame.contains(cursor) {
            cursor = m.frame.center
            emit(.warpCursor(m.frame.center))
        }
    }

    func settleFocus() {
        guard let id = focusedWindow, let w = windows[id] else { return }
        if isVisible(w.workspace) {
            if let m = workspaces[w.workspace]?.monitor, m != focusedMonitor {
                focusedMonitor = m
                emit(.statusChanged)
            }
            return
        }
        let ws = (activeSpecial[focusedMonitor] ?? activeWorkspace[focusedMonitor]).flatMap { workspaces[$0] }
        focusWindow(ws?.lastFocused ?? ws?.windowIDs.first, warp: false, emitEffect: true)
    }

    func moveWorkspace(_ wsID: Int, toMonitor target: Int) {
        guard var ws = workspaces[wsID], !ws.isSpecial, ws.monitor != target, let tm = monitor(target) else { return }
        let from = ws.monitor
        let wasActive = activeWorkspace[from] == wsID
        ws.monitor = target
        ws.homeMonitorName = tm.name
        workspaces[wsID] = ws
        shiftFloating(windowIDs(inWorkspace: wsID), from: monitor(from)?.frame, to: tm.frame)
        var affected: Set<Int> = [wsID]
        let displaced = activeWorkspace[target]
        if let displaced { affected.insert(displaced) }
        activeWorkspace[target] = wsID
        lastActiveByMonitorName[tm.name] = wsID
        if wasActive {
            let others = workspaces.values.filter { $0.monitor == from && !$0.isSpecial && $0.id != wsID }.map(\.id)
            let replacement = others.min() ?? ensureWorkspace(lowestUnusedID(), monitor: from)
            activeWorkspace[from] = replacement
            if let name = monitor(from)?.name { lastActiveByMonitorName[name] = replacement }
            affected.insert(replacement)
        }
        refresh(affected)
        if let displaced { destroyIfUnused(displaced) }
        settleFocus()
        emit(.statusChanged)
        emit(.saveState)
    }

    func swapActiveWorkspaces(_ a: Int, _ b: Int) {
        guard a != b, let wa = activeWorkspace[a], let wb = activeWorkspace[b], let ma = monitor(a), let mb = monitor(b) else { return }
        workspaces[wa]?.monitor = b
        workspaces[wa]?.homeMonitorName = mb.name
        workspaces[wb]?.monitor = a
        workspaces[wb]?.homeMonitorName = ma.name
        shiftFloating(windowIDs(inWorkspace: wa), from: ma.frame, to: mb.frame)
        shiftFloating(windowIDs(inWorkspace: wb), from: mb.frame, to: ma.frame)
        activeWorkspace[a] = wb
        activeWorkspace[b] = wa
        lastActiveByMonitorName[ma.name] = wb
        lastActiveByMonitorName[mb.name] = wa
        refresh([wa, wb])
        settleFocus()
        emit(.statusChanged)
        emit(.saveState)
    }

    func focusWorkspaceOnCurrentMonitor(_ wsID: Int) {
        guard isUsableID(wsID) else { return }
        ensureWorkspace(wsID, monitor: focusedMonitor, createdEmpty: workspaces[wsID] == nil)
        guard let ws = workspaces[wsID] else { return }
        if ws.monitor == focusedMonitor || ws.isSpecial {
            switchWorkspace(wsID)
            return
        }
        let here = focusedMonitor
        if activeWorkspace[ws.monitor] == wsID {
            swapActiveWorkspaces(here, ws.monitor)
        } else {
            moveWorkspace(wsID, toMonitor: here)
        }
        focusWindow(workspaces[wsID]?.lastFocused ?? workspaces[wsID]?.windowIDs.first, warp: false, emitEffect: true)
        focusedMonitor = here
    }

    func relocate(_ id: WindowID, to wsID: Int, focalPoint: Point? = nil) {
        let wasLast = windows[id].flatMap { workspaces[$0.workspace]?.lastFocused } == id
        detach(id)
        attach(id, to: wsID, focalPoint: focalPoint)
        if wasLast { workspaces[wsID]?.lastFocused = id }
    }

    func setFloating(_ id: WindowID, _ floating: Bool) {
        guard var w = windows[id], w.isFloating != floating, w.suspended == nil else { return }
        let wsID = w.workspace
        let wasLast = workspaces[wsID]?.lastFocused == id
        detach(id)
        w.dropPlacement()
        if floating, !w.everFloated, let ws = workspaces[wsID] {
            let area = workArea(for: ws)
            w.floatingFrame = Rect(x: area.x + area.width * 0.2, y: area.y + area.height * 0.2, width: area.width * 0.6, height: area.height * 0.6).rounded()
        }
        w.everFloated = w.everFloated || floating
        w.isFloating = floating
        if !floating { w.isPinned = false }
        windows[id] = w
        attach(id, to: wsID)
        if wasLast { workspaces[wsID]?.lastFocused = id }
        refresh([wsID])
        emit(.saveState)
    }

    func windowAt(_ p: Point) -> WindowID? {
        guard let m = monitorID(containing: p) else { return nil }
        for wsID in [activeSpecial[m], activeWorkspace[m]].compactMap({ $0 }) {
            guard let ws = workspaces[wsID] else { continue }
            let boxes = targetFrames(ws)
            func hits(_ id: WindowID) -> Bool { boxes[id]?.contains(p) == true }
            if let hit = ws.windowIDs.first(where: { windows[$0]?.fullscreenMode != nil && hits($0) }) { return hit }
            if let hit = ws.floating.reversed().first(where: hits) { return hit }
            if let focused = focusedWindow, ws.tiledIDs.contains(focused), hits(focused) { return focused }
            if let hit = ws.tiledIDs.first(where: hits) { return hit }
        }
        return nil
    }
}
