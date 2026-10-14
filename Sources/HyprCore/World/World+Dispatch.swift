import Foundation

extension World {
    static let pendingSpawnLimit = 256
    static let minimumWindowSize = 20.0
    static let setPropNames: Set<String> = ["border_size", "border_color", "no_anim"]

    public func run(_ command: Command) -> CommandResult {
        let error = execute(command)
        return CommandResult(reply: error ?? "ok", isError: error != nil, effects: takeEffects())
    }

    func measure(_ m: Measure, base: Double) -> Double {
        switch m {
        case .pixels(let v): return World.bounded(v)
        case .percent(let v): return World.bounded(v) / 100 * World.bounded(base)
        }
    }

    var layoutTargetWorkspaceID: Int? { focusedWindow.flatMap { windows[$0]?.workspace } ?? currentWorkspaceID }

    func sendSignal(_ w: ManagedWindow, _ sig: Int32) -> String? {
        guard (1 ... 31).contains(sig) else { return "invalid signal \(sig)" }
        guard w.pid > 1 else { return "window has no valid process" }
        emit(.signal(pid: w.pid, signal: sig))
        return nil
    }

    func execute(_ command: Command) -> String? {
        switch command {
        case .exec(let cmd, let rules, _):
            guard !cmd.isEmpty else { return "empty command" }
            var token: Int?
            if let rules, !rules.isEmpty {
                let t = nextSpawnToken
                nextSpawnToken += 1
                spawnRules[t] = rules
                if spawnRules.count > World.pendingSpawnLimit, let oldest = spawnRules.keys.min() { spawnRules[oldest] = nil }
                token = t
            }
            emit(.spawn(cmd, token: token))
            return nil
        case .killActive(let force):
            guard let id = focusedWindow, let w = windows[id] else { return "no active window" }
            if force { return sendSignal(w, 9) }
            emit(.close(id))
            return nil
        case .closeWindow(let sel, let force):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            if force { return sendSignal(w, 9) }
            emit(.close(id))
            return nil
        case .signal(let sig, let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            return sendSignal(w, sig)
        case .workspace(let sel):
            guard let id = resolveWorkspace(sel) else { return "invalid workspace" }
            if workspaces[id]?.isSpecial == true { toggleSpecial(id, show: true) } else { switchWorkspace(id) }
            return nil
        case .moveToWorkspace(let sel, let wsel, let silent):
            guard let target = resolveWorkspace(sel) else { return "invalid workspace" }
            guard let id = matchingWindows(wsel).first else { return "no matching window" }
            moveWindow(id, toWorkspace: target, silent: silent)
            return nil
        case .floating(let action, let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            releasePlacement(id)
            setFloating(id, action == .toggle ? !w.isFloating : action == .set)
            return nil
        case .fullscreen(let mode, let action):
            guard mode == 0 || mode == 1 else { return "invalid fullscreen mode" }
            guard let id = focusedWindow, let w = windows[id] else { return "no active window" }
            releasePlacement(id)
            let turnOn = action == .toggle ? w.fullscreenMode != mode : action == .set
            for other in workspaces[w.workspace]?.windowIDs ?? [] { windows[other]?.fullscreenMode = nil }
            windows[id]?.fullscreenMode = turnOn ? mode : nil
            if turnOn { emit(.raise(id)) }
            refresh([w.workspace])
            emit(.saveState)
            return nil
        case .pin(let sel):
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            guard w.isFloating else { return "pin works only on floating windows" }
            windows[id]?.isPinned.toggle()
            emit(.saveState)
            return nil
        case .pseudo(let sel):
            guard let id = matchingWindows(sel).first, windows[id] != nil else { return "no matching window" }
            releasePlacement(id)
            guard let w = windows[id] else { return "no matching window" }
            if !w.isPseudo { windows[id]?.pseudoSize = (w.appliedFrame ?? w.lastFrame).size }
            windows[id]?.isPseudo.toggle()
            refresh([w.workspace])
            emit(.saveState)
            return nil
        case .moveFocus(let d):
            moveFocus(d)
            return nil
        case .moveWindow(let target, let silent):
            return moveActiveWindow(target, silent: silent)
        case .swapWindow(let target):
            return swapWindow(target)
        case .centerWindow:
            guard let id = focusedWindow, let w = windows[id], w.isFloating, let ws = workspaces[w.workspace] else { return "no floating active window" }
            let area = workArea(for: ws)
            var f = w.floatingFrame
            f.x = area.x + (area.width - f.width) / 2
            f.y = area.y + (area.height - f.height) / 2
            windows[id]?.floatingFrame = f.rounded()
            refresh([w.workspace])
            emit(.saveState)
            return nil
        case .resizeActive(let p):
            guard let id = focusedWindow else { return "no active window" }
            return resize(id, p)
        case .moveActive(let p):
            guard let id = focusedWindow else { return "no active window" }
            return move(id, p, name: "moveactive")
        case .placeActive(let width, let height, let x, let y):
            guard let id = focusedWindow else { return "no active window" }
            return placeWindow(id, width, height, x, y)
        case .resizeWindow(let p, let sel):
            guard let id = matchingWindows(sel).first else { return "no matching window" }
            return resize(id, p)
        case .moveWindowTo(let p, let sel):
            guard let id = matchingWindows(sel).first else { return "no matching window" }
            return move(id, p, name: "movewindowpixel")
        case .cycleNext(let o):
            cycle(o)
            return nil
        case .swapNext(let previous):
            guard let id = focusedWindow, let w = windows[id], !w.isFloating, var ws = workspaces[w.workspace] else { return "no tiled active window" }
            let tiled = ws.tiledIDs
            guard let i = tiled.firstIndex(of: id), tiled.count > 1 else { return nil }
            let other = tiled[(i + (previous ? tiled.count - 1 : 1)) % tiled.count]
            ws.layout.update { $0.swap(id, other) }
            workspaces[ws.id] = ws
            refresh([ws.id])
            emit(.saveState)
            return nil
        case .focusWindow(let sel):
            guard let id = matchingWindows(sel).first else { return "no matching window" }
            focusAnywhere(id)
            return nil
        case .focusMonitor(let sel):
            guard let m = resolveMonitor(sel) else { return "invalid monitor" }
            focusMonitor(m)
            return nil
        case .focusCurrentOrLast, .focusUrgentOrLast:
            guard let last = focusHistory.last(where: { $0 != focusedWindow && windows[$0]?.suspended == nil }) else { return nil }
            focusAnywhere(last)
            return nil
        case .moveCurrentWorkspaceToMonitor(let sel):
            guard let m = resolveMonitor(sel), let current = currentWorkspaceID else { return "invalid monitor" }
            moveWorkspace(current, toMonitor: m)
            focusedMonitor = m
            return nil
        case .moveWorkspaceToMonitor(let wsel, let msel):
            guard let id = resolveWorkspace(wsel), let m = resolveMonitor(msel) else { return "invalid workspace or monitor" }
            ensureWorkspace(id)
            moveWorkspace(id, toMonitor: m)
            destroyIfUnused(id)
            return nil
        case .focusWorkspaceOnCurrentMonitor(let sel):
            guard let id = resolveWorkspace(sel) else { return "invalid workspace" }
            focusWorkspaceOnCurrentMonitor(id)
            return nil
        case .swapActiveWorkspaces(let a, let b):
            guard let ma = resolveMonitor(a), let mb = resolveMonitor(b) else { return "invalid monitor" }
            swapActiveWorkspaces(ma, mb)
            return nil
        case .toggleSpecialWorkspace(let name):
            guard let id = resolveWorkspace(.special(name)) else { return "invalid workspace" }
            toggleSpecial(id)
            return nil
        case .renameWorkspace(let id, let name):
            guard let ws = workspaces[id] else { return "no such workspace" }
            guard !ws.isSpecial else { return "cannot rename a special workspace" }
            workspaces[id]?.name = name.isEmpty ? String(id) : name
            emit(.statusChanged)
            emit(.saveState)
            return nil
        case .layoutMessage(let text):
            return layoutMessage(text)
        case .submap(let name):
            submap = name == "reset" ? "" : name
            emit(.submapChanged(submap))
            emit(.statusChanged)
            return nil
        case .alterZOrder(let top):
            guard let id = focusedWindow else { return "no active window" }
            if top { emit(.raise(id)) }
            return nil
        case .moveCursorToCorner(let corner):
            guard (0 ... 3).contains(corner) else { return "invalid corner" }
            guard let id = focusedWindow, let w = windows[id] else { return "no active window" }
            let f = w.appliedFrame ?? w.lastFrame
            let points = [Point(x: f.minX, y: f.maxY - 1), Point(x: f.maxX - 1, y: f.maxY - 1), Point(x: f.maxX - 1, y: f.minY), Point(x: f.minX, y: f.minY)]
            cursor = points[corner]
            emit(.warpCursor(cursor))
            return nil
        case .moveCursor(let x, let y):
            cursor = Point(x: World.bounded(x), y: World.bounded(y))
            emit(.warpCursor(cursor))
            return nil
        case .workspaceLayout(let names):
            return setWorkspaceLayout(names)
        case .setProp(let sel, let prop, let value):
            guard World.setPropNames.contains(prop) else { return "setprop \(prop) is not supported on macOS" }
            guard let id = matchingWindows(sel).first, let w = windows[id] else { return "no matching window" }
            if value == "unset" {
                windows[id]?.props[prop] = nil
            } else {
                let valid: Bool
                switch prop {
                case "border_size": valid = finiteDouble(value) != nil
                case "border_color": valid = ConfigValue.gradient(value) != nil
                default: valid = ConfigValue.bool(value) != nil
                }
                guard valid else { return "invalid value for \(prop): \(value)" }
                windows[id]?.props[prop] = value
            }
            refresh([w.workspace])
            emit(.saveState)
            return nil
        case .exit:
            emit(.exitApp)
            return nil
        case .noop:
            return nil
        case .unsupported(let name):
            return "\(name) is not supported on macOS"
        }
    }

    func moveActiveWindow(_ target: MoveTarget, silent: Bool) -> String? {
        guard let id = focusedWindow, let w = windows[id], var ws = workspaces[w.workspace] else { return "no active window" }
        switch target {
        case .monitor(let sel):
            guard let m = resolveMonitor(sel), let dest = activeSpecial[m] ?? activeWorkspace[m] else { return "invalid monitor" }
            moveWindow(id, toWorkspace: dest, silent: silent)
            return nil
        case .direction(let d):
            if w.isFloating {
                let area = workArea(for: ws)
                var f = w.floatingFrame
                switch d {
                case .left: f.x = area.minX
                case .right: f.x = area.maxX - f.width
                case .up: f.y = area.minY
                case .down: f.y = area.maxY - f.height
                }
                windows[id]?.floatingFrame = f.rounded()
                refresh([ws.id])
                emit(.saveState)
                return nil
            }
            let ctx = layoutContext(ws)
            let moved = ws.layout.update { $0.moveWindow(id, d, ctx) }
            workspaces[ws.id] = ws
            if moved {
                releasePlacement(id)
                refresh([ws.id])
                emit(.saveState)
                return nil
            }
            guard config.bindsOptions.windowDirectionMonitorFallback, let m = monitorInDirection(from: ws.monitor, d),
                  let dest = activeSpecial[m] ?? activeWorkspace[m], let destWS = workspaces[dest] else { return nil }
            let area = workArea(for: destWS)
            let entry: Point
            switch d {
            case .left: entry = Point(x: area.maxX - 1, y: area.center.y)
            case .right: entry = Point(x: area.minX + 1, y: area.center.y)
            case .up: entry = Point(x: area.center.x, y: area.maxY - 1)
            case .down: entry = Point(x: area.center.x, y: area.minY + 1)
            }
            moveWindow(id, toWorkspace: dest, silent: silent, focalPoint: entry)
            return nil
        }
    }

    func swapWindow(_ target: SwapTarget) -> String? {
        guard let id = focusedWindow, let w = windows[id], !w.isFloating, var ws = workspaces[w.workspace] else { return "no tiled active window" }
        let other: WindowID?
        switch target {
        case .direction(let d): other = idealBoxes(ws)[id].flatMap { windowInDirection(from: $0, originFloating: false, ignoring: id, d) }
        case .window(let sel): other = matchingWindows(sel).first { $0 != id }
        }
        guard let other, windows[other]?.workspace == ws.id, windows[other]?.isFloating == false else { return "no window to swap with" }
        ws.layout.update { $0.swap(id, other) }
        workspaces[ws.id] = ws
        refresh([ws.id])
        emit(.saveState)
        return nil
    }

    func resize(_ id: WindowID, _ p: ResizeParam) -> String? {
        guard let w = windows[id], var ws = workspaces[w.workspace] else { return "no matching window" }
        let area = workArea(for: ws)
        let current = w.isFloating ? w.floatingFrame : (idealBoxes(ws)[id] ?? w.lastFrame)
        var size: Size
        switch p {
        case .relative(let dx, let dy):
            size = Size(width: current.width + measure(dx, base: current.width), height: current.height + measure(dy, base: current.height))
        case .exact(let width, let height):
            size = Size(width: measure(width, base: area.width), height: measure(height, base: area.height))
        }
        size = Size(width: min(max(World.minimumWindowSize, size.width), World.extent),
                    height: min(max(World.minimumWindowSize, size.height), World.extent))
        if w.isFloating {
            windows[id]?.floatingFrame = Rect(x: current.x, y: current.y, width: size.width, height: size.height).rounded()
        } else {
            let delta = Point(x: size.width - current.width, y: size.height - current.height)
            let ctx = layoutContext(ws)
            ws.layout.update { $0.resize(id, by: delta, corner: .none, ctx) }
            workspaces[ws.id] = ws
        }
        refresh([ws.id])
        emit(.saveState)
        return nil
    }

    func move(_ id: WindowID, _ p: ResizeParam, name: String) -> String? {
        guard let w = windows[id], w.isFloating, let ws = workspaces[w.workspace] else { return "\(name) works only on floating windows" }
        let area = workArea(for: ws)
        var f = w.floatingFrame
        switch p {
        case .relative(let dx, let dy):
            f.x += measure(dx, base: f.width)
            f.y += measure(dy, base: f.height)
        case .exact(let x, let y):
            f.x = area.x + measure(x, base: area.width)
            f.y = area.y + measure(y, base: area.height)
        }
        f.x = World.bounded(f.x)
        f.y = World.bounded(f.y)
        windows[id]?.floatingFrame = f.rounded()
        refresh([ws.id])
        emit(.saveState)
        return nil
    }

    func layoutMessage(_ text: String) -> String? {
        guard let wsID = layoutTargetWorkspaceID, var ws = workspaces[wsID] else { return "no workspace" }
        let ctx = layoutContext(ws)
        let result = ws.layout.update { $0.message(text, ctx) }
        workspaces[wsID] = ws
        switch result {
        case .ok:
            releasePlacement(focusedWindow)
            refresh([wsID])
            emit(.saveState)
            return nil
        case .focus(let id):
            releasePlacement(focusedWindow)
            refresh([wsID])
            focusAndRaise(id)
            return nil
        case .error(let message):
            return message
        }
    }

    func setWorkspaceLayout(_ names: [String]) -> String? {
        let kinds = names.compactMap(LayoutKind.init(rawValue:))
        guard kinds.count == names.count, (1 ... 2).contains(kinds.count), let first = kinds.first,
              let wsID = layoutTargetWorkspaceID, var ws = workspaces[wsID] else { return "invalid layout" }
        let target = kinds.count > 1 && ws.layout.kind == first ? kinds[1] : first
        guard target != ws.layout.kind else { return nil }
        let ids = ws.tiledIDs
        ws.layout = LayoutState(target)
        var previous: WindowID?
        for id in ids {
            var ctx = layoutContext(ws)
            ctx.focused = previous
            ws.layout.update { $0.insert(id, ctx) }
            previous = id
        }
        workspaces[wsID] = ws
        refresh([wsID])
        emit(.saveState)
        return nil
    }
}
