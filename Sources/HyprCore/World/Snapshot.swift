import Foundation

public struct StateSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var windows: [ManagedWindow]
    public var workspaces: [Workspace]
    public var activeWorkspace: [String: Int]
    public var focusedWindow: WindowID?
}

extension DwindleLayout {
    static let maxDepth = 256

    mutating func sanitize() {
        let old = nodes
        var seen = Set<Int>(), used = Set<WindowID>()
        var fresh: [Int: Node] = [:]
        func walk(_ id: Int, _ depth: Int) -> Int? {
            guard depth <= DwindleLayout.maxDepth, seen.insert(id).inserted, let n = old[id] else { return nil }
            var node = Node(splitTop: n.splitTop, ratio: clampRatio(n.ratio), forced: n.forced)
            if n.children.isEmpty {
                guard let window = n.window, used.insert(window).inserted else { return nil }
                node.window = window
                fresh[fresh.count + 1] = node
                return fresh.count
            }
            guard n.children.count == 2 else { return nil }
            let kids = n.children.compactMap { walk($0, depth + 1) }
            guard kids.count == 2 else { return kids.first }
            node.children = kids
            let me = fresh.count + 1
            fresh[me] = node
            for kid in kids { fresh[kid]?.parent = me }
            return me
        }
        let top = root.flatMap { walk($0, 0) }
        nodes = fresh
        root = top
        nextID = fresh.count + 1
    }
}

extension MasterLayout {
    mutating func sanitize() {
        var seen = Set<WindowID>()
        nodes = nodes.filter { seen.insert($0.window).inserted }
        for i in nodes.indices {
            nodes[i].percMaster = MasterLayout.masterShare(nodes[i].percMaster)
            nodes[i].percSize = MasterLayout.clamped(nodes[i].percSize, 0.05, 1.95, fallback: 1)
        }
        if !nodes.isEmpty && !nodes.contains(where: \.isMaster) { nodes[0].isMaster = true }
    }
}

extension MonocleLayout {
    mutating func sanitize() {
        var seen = Set<WindowID>()
        order = order.filter { seen.insert($0).inserted }
    }
}

extension LayoutState {
    mutating func sanitize() {
        switch self {
        case .dwindle(var l): l.sanitize(); self = .dwindle(l)
        case .master(var l): l.sanitize(); self = .master(l)
        case .monocle(var l): l.sanitize(); self = .monocle(l)
        }
    }
}

extension World {
    public func snapshot() -> StateSnapshot {
        let active = Dictionary(activeWorkspace.compactMap { key, value in monitor(key).map { ($0.name, value) } }, uniquingKeysWith: { a, _ in a })
        let saved = windows.values.sorted { $0.id < $1.id }.map { window -> ManagedWindow in
            var w = window
            w.title = ""
            w.initialTitle = ""
            return w
        }
        return StateSnapshot(windows: saved, workspaces: workspaces.values.sorted { $0.id < $1.id },
                             activeWorkspace: active, focusedWindow: focusedWindow)
    }

    public func restore(_ snap: StateSnapshot, alive: [WindowSnapshot]) -> [Effect] {
        let live = Dictionary(alive.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let before = Set(workspaces.keys)
        var saved: [Workspace] = []
        var savedIDs = Set<Int>()
        for var ws in snap.workspaces {
            let validID = ws.isSpecial ? (-99 ... -1).contains(ws.id) : (1 ... Int(Int32.max)).contains(ws.id)
            guard validID, savedIDs.insert(ws.id).inserted else { continue }
            ws.layout.sanitize()
            saved.append(ws)
        }

        func inRange(_ values: Double...) -> Bool { values.allSatisfy { $0.isFinite && abs($0) <= World.extent } }
        var kept: [WindowID: ManagedWindow] = [:]
        for var w in snap.windows {
            guard kept[w.id] == nil, let l = live[w.id], l.bundleID == w.bundleID, savedIDs.contains(w.workspace) else { continue }
            w.title = l.title
            if w.initialTitle.isEmpty { w.initialTitle = l.title }
            w.lastFrame = l.frame
            w.appliedFrame = nil
            w.refitTarget = nil
            w.isParked = false
            w.suspended = nil
            let f = w.floatingFrame
            if !inRange(f.x, f.y, f.width, f.height) || f.width <= 0 || f.height <= 0 { w.floatingFrame = l.frame }
            if !inRange(w.pseudoSize.width, w.pseudoSize.height) || w.pseudoSize.width <= 0 || w.pseudoSize.height <= 0 { w.pseudoSize = l.frame.size }
            if let mode = w.fullscreenMode, !(0 ... 1).contains(mode) { w.fullscreenMode = nil }
            kept[w.id] = w
        }

        var placed = Set<WindowID>()
        func claim(_ id: WindowID, floating: Bool, in wsID: Int) -> Bool {
            guard let w = kept[id], w.workspace == wsID, w.isFloating == floating else { return false }
            return placed.insert(id).inserted
        }
        let primary = monitors.first?.id ?? 0
        for var ws in saved {
            ws.monitor = monitors.first { $0.name == ws.homeMonitorName }?.id ?? primary
            for id in ws.tiledIDs where !claim(id, floating: false, in: ws.id) { ws.layout.update { $0.remove(id) } }
            ws.floating = ws.floating.filter { claim($0, floating: true, in: ws.id) }
            if let last = ws.lastFocused, kept[last]?.workspace != ws.id { ws.lastFocused = nil }
            workspaces[ws.id] = ws
            if !ws.isSpecial && ws.id >= 1_000_000 { nextNamedID = max(nextNamedID, ws.id + 1) }
        }
        for (id, w) in kept { windows[id] = w }
        for id in kept.keys.sorted() where !placed.contains(id) {
            if let wsID = windows[id]?.workspace { attach(id, to: wsID) }
        }
        for (name, wsID) in snap.activeWorkspace {
            guard let m = monitors.first(where: { $0.name == name }), let ws = workspaces[wsID], !ws.isSpecial, ws.monitor == m.id else { continue }
            activeWorkspace[m.id] = wsID
            lastActiveByMonitorName[name] = wsID
        }
        if let f = snap.focusedWindow, kept[f] != nil { focusWindow(f, warp: false, emitEffect: false) }
        for s in alive where windows[s.id] == nil { addWindow(s) }
        for id in before.subtracting(savedIDs) { destroyIfUnused(id) }
        setMonitors(monitors)
        effects = effects.map { effect in
            guard case .setFrames(let changes) = effect else { return effect }
            return .setFrames(changes.map { FrameChange(id: $0.id, frame: $0.frame, reason: .layout) })
        }
        return takeEffects()
    }
}
