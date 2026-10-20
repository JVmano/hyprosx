import Foundation

extension World {
    func windowIDs(ofApp pid: Int32) -> [WindowID] {
        windows.values.filter { $0.pid == pid }.map(\.id).sorted()
    }

    func suspend(_ id: WindowID, _ reason: SuspendReason) {
        guard var w = windows[id], w.suspended == nil else { return }
        let center = (w.appliedFrame ?? w.lastFrame).center
        detach(id)
        w.dropPlacement()
        w.suspended = reason
        w.isParked = false
        w.appliedFrame = nil
        windows[id] = w
        if dragging == id {
            dragging = nil
            dragIsResize = false
        }
        if focusedWindow == id {
            focusedWindow = nil
            if isVisible(w.workspace) {
                focusWindow(focusCandidate(onWorkspace: w.workspace, near: center), warp: false, emitEffect: true)
            }
        }
        refresh([w.workspace])
        emit(.statusChanged)
        emit(.saveState)
    }

    func resume(_ id: WindowID) {
        guard var w = windows[id], let reason = w.suspended else { return }
        let previous = w.workspace
        w.suspended = nil
        if reason == .minimized, let current = currentWorkspaceID { w.workspace = current }
        windows[id] = w
        ensureWorkspace(w.workspace)
        attach(id, to: w.workspace)
        refresh([w.workspace])
        if reason == .minimized { focusWindow(id, warp: false, emitEffect: false) }
        if previous != w.workspace { destroyIfUnused(previous) }
        emit(.statusChanged)
        emit(.saveState)
    }

    func appHidden(_ pid: Int32, byUser: Bool) {
        if byUser && config.macos.unhideHiddenApps {
            emit(.unhideApp(pid))
            return
        }
        for id in windowIDs(ofApp: pid) { suspend(id, .appHidden) }
    }

    func retitle(_ id: WindowID, _ title: String, early: Bool) {
        guard var w = windows[id] else { return }
        w.title = title
        let rerun = early && w.initialTitle.isEmpty && !title.isEmpty
        if rerun { w.initialTitle = title }
        windows[id] = w
        emit(.statusChanged)
        guard rerun else { return }
        let outcome = staticOutcome(for: w)
        if outcome.ignore {
            removeWindow(id)
            ignored.insert(id)
            return
        }
        if let floating = outcome.floating, floating != w.isFloating { setFloating(id, floating) }
        if let t = outcome.workspace, let target = resolveRuleWorkspace(t.selector), target != w.workspace {
            moveWindow(id, toWorkspace: target, silent: t.silent)
        }
    }

    func frameChanged(_ id: WindowID, _ frame: Rect, userDriven: Bool) {
        guard var w = windows[id], w.suspended == nil, !w.isParked else { return }
        let fullscreen = w.fullscreenMode != nil
        if w.isFloating && !fullscreen {
            let nearApplied = w.appliedFrame.map { $0.isClose(to: frame) } == true
            let unchanged = nearApplied || w.floatingFrame.isClose(to: frame)
            w.lastFrame = frame
            if !nearApplied { w.appliedFrame = frame }
            if !unchanged { w.floatingFrame = frame }
            windows[id] = w
            guard !unchanged else { return }
            if let m = monitorID(containing: frame.center), m != workspaces[w.workspace]?.monitor,
               let target = activeSpecial[m] ?? activeWorkspace[m] {
                relocate(id, to: target)
                if focusedWindow == id { focusedMonitor = m }
                emit(.statusChanged)
            }
            emit(.saveState)
            return
        }
        w.lastFrame = frame
        windows[id] = w
        guard isVisible(w.workspace), let applied = w.appliedFrame, !applied.isClose(to: frame, tolerance: 2) else { return }
        guard userDriven, !fullscreen else {
            if w.refitTarget.map({ !$0.isClose(to: applied) }) ?? true {
                windows[id]?.refitTarget = applied
                emit(.setFrames([FrameChange(id: id, frame: applied, reason: .layout)]))
            }
            return
        }
        clearPlacement(id)
        let leftMoved = abs(frame.minX - applied.minX) > 2, rightMoved = abs(frame.maxX - applied.maxX) > 2
        let topMoved = abs(frame.minY - applied.minY) > 2, bottomMoved = abs(frame.maxY - applied.maxY) > 2
        let resized = abs(frame.width - applied.width) > 2 || abs(frame.height - applied.height) > 2
        let continuingResize = dragging == id && dragIsResize
        dragging = id
        guard resized, var ws = workspaces[w.workspace] else {
            dragIsResize = continuingResize
            return
        }
        dragIsResize = true
        let corner: Corner = topMoved ? (leftMoved ? .topLeft : .topRight) : (leftMoved ? .bottomLeft : .bottomRight)
        let delta = Point(x: leftMoved ? frame.minX - applied.minX : (rightMoved ? frame.maxX - applied.maxX : 0),
                          y: topMoved ? frame.minY - applied.minY : (bottomMoved ? frame.maxY - applied.maxY : 0))
        let ctx = layoutContext(ws)
        ws.layout.update { $0.resize(id, by: delta, corner: corner, ctx) }
        workspaces[ws.id] = ws
        windows[id]?.appliedFrame = frame
        refresh([ws.id], skip: id)
    }

    @discardableResult
    func endDrag(at point: Point) -> Bool {
        cursor = point
        guard let id = dragging else { return false }
        dragging = nil
        let wasResize = dragIsResize
        dragIsResize = false
        guard var w = windows[id], !w.isFloating, let ws = workspaces[w.workspace] else { return false }
        w.appliedFrame = w.lastFrame
        windows[id] = w
        let boxes = idealBoxes(ws)
        let targetMonitor = monitorID(containing: point) ?? ws.monitor
        let targetWS = activeSpecial[targetMonitor] ?? activeWorkspace[targetMonitor] ?? ws.id
        if wasResize || (targetWS == ws.id && boxes[id]?.contains(point) ?? true) {
            refresh([ws.id])
            return false
        }
        if targetWS == ws.id, ws.layout.kind != .dwindle {
            let other = boxes.keys.sorted().first { $0 != id && boxes[$0]?.contains(point) == true && windows[$0]?.isFloating == false }
            if let other { workspaces[ws.id]?.layout.update { $0.swap(id, other) } }
            refresh([ws.id])
            return other != nil
        }
        relocate(id, to: targetWS, focalPoint: point)
        if focusedWindow == id, let m = workspaces[targetWS]?.monitor { focusedMonitor = m }
        refresh([ws.id, targetWS])
        destroyIfUnused(ws.id)
        emit(.saveState)
        return true
    }

    func nativeFocusChanged(_ id: WindowID?) {
        if let id, windows[id] == nil, !ignored.contains(id) { return }
        guard let id, let w = windows[id], w.suspended == nil else {
            if focusedWindow != nil {
                focusedWindow = nil
                emit(.statusChanged)
            }
            return
        }
        if !isVisible(w.workspace) {
            guard config.misc.focusOnActivate else { return }
            if workspaces[w.workspace]?.isSpecial == true {
                toggleSpecial(w.workspace, show: true, focusing: id, emitFocus: false)
            } else {
                switchWorkspace(w.workspace, focusing: id, emitFocus: false)
            }
        }
        focusWindow(id, warp: false, emitEffect: false)
    }

    func cursorMoved(_ p: Point) {
        cursor = p
        guard config.input.followMouse == 1, dragging == nil, let id = windowAt(p), id != focusedWindow else { return }
        focusWindow(id, warp: false, emitEffect: true)
    }
}
