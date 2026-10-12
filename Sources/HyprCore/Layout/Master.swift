import Foundation

public struct MasterLayout: TiledLayout, Equatable, Codable, Sendable {
    struct Node: Equatable, Codable, Sendable {
        var window: WindowID
        var isMaster: Bool
        var percMaster: Double
        var percSize: Double
    }

    var nodes: [Node] = []
    var orientationOverride: String?
    var previousFocus: WindowID?
    var allowSmallSplit = false

    static let orientations = ["left", "top", "right", "bottom", "center"]

    public init() {}

    public var windowIDs: [WindowID] { nodes.map(\.window) }

    func index(of id: WindowID?) -> Int? { id.flatMap { w in nodes.firstIndex { $0.window == w } } }

    func orientation(_ ctx: LayoutContext) -> String {
        let name = orientationOverride ?? ctx.master.orientation
        return MasterLayout.orientations.contains(name) ? name : "left"
    }

    static func clamped(_ v: Double, _ lo: Double, _ hi: Double, fallback: Double) -> Double {
        v.isNaN ? fallback : min(max(v, lo), hi)
    }

    static func masterShare(_ v: Double) -> Double { clamped(v, 0.05, 0.95, fallback: 0.55) }

    func effectiveOrientation(_ ctx: LayoutContext) -> (name: String, centered: Bool) {
        let stored = orientation(ctx)
        guard stored == "center" else { return (stored, false) }
        let slaveCount = nodes.filter { !$0.isMaster }.count
        return slaveCount >= ctx.master.slaveCountForCenterMaster ? (stored, true) : (ctx.master.centerMasterFallback, false)
    }

    static func centerColumns(_ slaves: [Node], startRight: Bool) -> (left: [Node], right: [Node]) {
        var onRight = startRight
        var left: [Node] = [], right: [Node] = []
        for n in slaves { if onRight { right.append(n) } else { left.append(n) }; onRight.toggle() }
        return (left, right)
    }

    static func distribute(_ group: [Node], total: Double, smart: Bool) -> [Double] {
        guard !group.isEmpty else { return [] }
        if smart {
            let avg = total / Double(group.count)
            let acc = group.reduce(0) { $0 + avg * $1.percSize }
            return group.map { acc > 0 ? avg * $0.percSize * total / acc : avg }
        }
        var left = total
        var sizes: [Double] = []
        for (i, n) in group.enumerated() {
            let remaining = group.count - i
            var s = remaining > 1 ? left / Double(remaining) * n.percSize : left
            if remaining > 1 && s > left * 0.9 { s = left * 0.9 }
            sizes.append(s)
            left -= s
        }
        return sizes
    }

    public func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect] {
        guard !nodes.isEmpty else { return [:] }
        let wa = ctx.workArea
        let W = wa.width, H = wa.height
        let masters = nodes.filter(\.isMaster)
        let slaves = nodes.filter { !$0.isMaster }
        let smart = ctx.master.smartResizing
        let stored = orientation(ctx)
        let (orient, centerMaster) = effectiveOrientation(ctx)
        var out: [WindowID: Rect] = [:]
        if nodes.count == 1 && !centerMaster {
            let n = nodes[0]
            guard ctx.master.alwaysKeepPosition else { out[n.window] = wa; return out }
            let w = W * MasterLayout.masterShare(n.percMaster)
            let x = stored == "right" ? W - w : (stored == "center" ? (W - w) / 2 : 0)
            out[n.window] = Rect(x: wa.x + x, y: wa.y, width: w, height: H)
            return out
        }
        let perc = MasterLayout.masterShare(masters.first?.percMaster ?? ctx.master.mfact)
        var masterW = W, masterH = H
        if orient == "top" || orient == "bottom" {
            masterH = slaves.isEmpty ? H : H * perc
            let y = orient == "bottom" ? H - masterH : 0
            var x = 0.0
            for (n, w) in zip(masters, MasterLayout.distribute(masters, total: W, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: w, height: masterH)
                x += w
            }
        } else {
            masterW = (!slaves.isEmpty || centerMaster) ? W * perc : W
            let x = orient == "right" ? W - masterW : (centerMaster ? (W - masterW) / 2 : 0)
            var y = 0.0
            for (n, h) in zip(masters, MasterLayout.distribute(masters, total: H, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: masterW, height: h)
                y += h
            }
        }
        guard !slaves.isEmpty else { return out }
        switch orient {
        case "top", "bottom":
            let h = H - masterH
            let y = orient == "top" ? masterH : 0
            var x = 0.0
            for (n, w) in zip(slaves, MasterLayout.distribute(slaves, total: W, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: w, height: h)
                x += w
            }
        case _ where centerMaster:
            let colW = (W - masterW) / 2
            let columns = MasterLayout.centerColumns(slaves, startRight: ctx.master.centerMasterFallback == "right")
            for (column, x) in [(columns.left, 0.0), (columns.right, colW + masterW)] {
                var y = 0.0
                for (n, h) in zip(column, MasterLayout.distribute(column, total: H, smart: smart)) {
                    out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: colW, height: h)
                    y += h
                }
            }
        default:
            let w = W - masterW
            let x = orient == "left" ? masterW : 0
            var y = 0.0
            for (n, h) in zip(slaves, MasterLayout.distribute(slaves, total: H, smart: smart)) {
                out[n.window] = Rect(x: wa.x + x, y: wa.y + y, width: w, height: h)
                y += h
            }
        }
        return out
    }

    public mutating func insert(_ id: WindowID, _ ctx: LayoutContext) {
        guard index(of: id) == nil else { return }
        let o = ctx.master
        allowSmallSplit = o.allowSmallSplit
        let focusedIndex = index(of: ctx.focused)
        let opening = focusedIndex.map { nodes[$0] } ?? nodes.first(where: \.isMaster)
        let newIsMaster = !ctx.dragging && o.newStatus == "master"
        let count = nodes.count + 1
        let becomesMaster = newIsMaster || count == 1
            || (count > 2 && !ctx.isFirstMap && opening?.isMaster == true)
            || (o.newStatus == "inherit" && opening?.isMaster == true && !ctx.dragging)
        var at = o.newOnTop ? 0 : nodes.count
        if o.newOnActive != "none" && !newIsMaster, let fi = focusedIndex {
            let masterCount = nodes.filter(\.isMaster).count
            if !(nodes[fi].isMaster && (masterCount == 1 || o.newStatus == "slave")) {
                at = o.newOnActive == "before" ? fi : fi + 1
            }
        }
        let share = MasterLayout.masterShare(o.mfact)
        var node = Node(window: id, isMaster: false, percMaster: nodes.first(where: \.isMaster)?.percMaster ?? share, percSize: 1)
        if becomesMaster {
            let demote = o.newOnActive == "before" ? nodes.lastIndex(where: \.isMaster) : nodes.firstIndex(where: \.isMaster)
            if let d = demote {
                node.percMaster = nodes[d].percMaster
                nodes[d].isMaster = false
            } else {
                node.percMaster = share
            }
            node.isMaster = true
        }
        nodes.insert(node, at: at)
    }

    public mutating func remove(_ id: WindowID) {
        guard let i = index(of: id) else { return }
        let node = nodes[i]
        let mastersBefore = nodes.filter(\.isMaster).count
        if node.isMaster && (mastersBefore <= 1 || allowSmallSplit), let s = nodes.firstIndex(where: { !$0.isMaster }) {
            nodes[s].isMaster = true
            nodes[s].percMaster = node.percMaster
        }
        nodes.remove(at: i)
        if previousFocus == id { previousFocus = nil }
        if !nodes.isEmpty && nodes.allSatisfy(\.isMaster) && mastersBefore > 1 && nodes.count > 1 { nodes[nodes.count - 1].isMaster = false }
        if nodes.count == 1 { nodes[0].isMaster = true }
    }

    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let i = index(of: a), let j = index(of: b) else { return }
        nodes[i].window = b
        nodes[j].window = a
    }

    public mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext) {
        guard let i = index(of: id) else { return }
        let wa = ctx.workArea
        guard wa.width > 0, wa.height > 0 else { return }
        let (orient, centered) = effectiveOrientation(ctx)
        let vertical = orient == "top" || orient == "bottom"
        let masterDelta: Double
        switch orient {
        case "right": masterDelta = -delta.x / wa.width
        case "top": masterDelta = delta.y / wa.height
        case "bottom": masterDelta = -delta.y / wa.height
        default: masterDelta = (centered ? 2 : 1) * delta.x / wa.width
        }
        if masterDelta != 0 {
            for k in nodes.indices where nodes[k].isMaster {
                nodes[k].percMaster = MasterLayout.clamped(nodes[k].percMaster + masterDelta, 0.05, 0.95, fallback: nodes[k].percMaster)
            }
        }
        let stackDelta = vertical ? delta.x : delta.y
        guard stackDelta != 0 else { return }
        let group = nodes.filter { $0.isMaster == nodes[i].isMaster }
        var column = group.count
        if centered && !nodes[i].isMaster {
            let columns = MasterLayout.centerColumns(group, startRight: ctx.master.centerMasterFallback == "right")
            column = columns.left.contains { $0.window == id } ? columns.left.count : columns.right.count
        }
        let extent = vertical ? wa.width : wa.height
        let unit = extent / Double(max(column, 1))
        nodes[i].percSize = MasterLayout.clamped(nodes[i].percSize + stackDelta / unit, 0.05, 1.95, fallback: nodes[i].percSize)
    }

    public mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool {
        let boxes = tileBoxes(ctx)
        guard let box = boxes[id] else { return false }
        let focal = WindowGeometry.focalPoint(of: box, direction)
        guard let target = nodes.first(where: { $0.window != id && boxes[$0.window]?.contains(focal) == true })?.window else { return false }
        swap(id, target)
        return true
    }

    func nextTarget(_ id: WindowID, next: Bool, loop: Bool) -> WindowID? {
        guard let start = index(of: id) else { return nil }
        let node = nodes[start]
        let list = next ? Array(nodes[start...]) : Array(nodes[...start].reversed())
        var candidate = list.first { $0.window != id && $0.isMaster == node.isMaster }
        if candidate == nil {
            let all = next ? nodes : nodes.reversed()
            candidate = all.first { $0.window != id && $0.isMaster != node.isMaster }
        }
        guard let c = candidate else { return nil }
        if !loop {
            if c.isMaster && next { return nil }
            if !c.isMaster && node.isMaster && !next { return nil }
        }
        return c.window
    }

    public mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult {
        allowSmallSplit = ctx.master.allowSmallSplit
        let words = text.split(separator: " ").map(String.init)
        guard let command = words.first else { return .error("empty layout message") }
        let args = Array(words.dropFirst())
        if command.hasPrefix("orientation") {
            let current = orientation(ctx)
            let pos = MasterLayout.orientations.firstIndex(of: current) ?? 0
            switch command {
            case "orientationnext": orientationOverride = MasterLayout.orientations[(pos + 1) % 5]
            case "orientationprev": orientationOverride = MasterLayout.orientations[(pos + 4) % 5]
            case "orientationcycle":
                let list = args.isEmpty ? MasterLayout.orientations : args
                guard list.allSatisfy({ MasterLayout.orientations.contains($0) }) else { return .error("unknown orientation") }
                orientationOverride = list[list.firstIndex(of: current).map { ($0 + 1) % list.count } ?? 0]
            default:
                let name = String(command.dropFirst("orientation".count))
                guard MasterLayout.orientations.contains(name) else { return .error("unknown master layout message '\(command)'") }
                orientationOverride = name
            }
            return .ok
        }
        if command == "mfact" {
            let exact = args.first == "exact"
            guard let v = (exact ? args.dropFirst().first : args.first).flatMap(Double.init), v.isFinite,
                  let m = nodes.firstIndex(where: \.isMaster) else { return .error("invalid mfact") }
            let share = MasterLayout.clamped(exact ? v : nodes[m].percMaster + v, 0.05, 0.95, fallback: nodes[m].percMaster)
            for k in nodes.indices where nodes[k].isMaster { nodes[k].percMaster = share }
            return .ok
        }
        guard let focused = ctx.focused, let fi = index(of: focused) else { return .error("no focused tiled window") }
        switch command {
        case "swapwithmaster":
            if !nodes[fi].isMaster {
                guard let m = nodes.first(where: \.isMaster)?.window else { return .error("no master") }
                swap(focused, m)
                return args.contains("child") ? .focus(m) : .ok
            }
            if args.contains("ignoremaster") { return .ok }
            guard let s = nodes.first(where: { !$0.isMaster })?.window else { return .ok }
            swap(focused, s)
            return args.contains("master") ? .focus(s) : .ok
        case "focusmaster":
            let mode = args.first ?? "auto"
            if !nodes[fi].isMaster {
                if mode == "previous" { previousFocus = focused }
                return nodes.first(where: \.isMaster).map { .focus($0.window) } ?? .ok
            }
            if mode == "master" { return .ok }
            if mode == "previous", let p = previousFocus, p != focused, index(of: p) != nil { return .focus(p) }
            return nodes.first(where: { !$0.isMaster }).map { .focus($0.window) } ?? .ok
        case "cyclenext", "cycleprev":
            return nextTarget(focused, next: command == "cyclenext", loop: !args.contains("noloop")).map { .focus($0) } ?? .ok
        case "swapnext", "swapprev":
            guard let t = nextTarget(focused, next: command == "swapnext", loop: !args.contains("noloop")) else { return .ok }
            swap(focused, t)
            return .ok
        case "addmaster":
            let masters = nodes.filter(\.isMaster).count
            guard masters + 2 <= nodes.count || allowSmallSplit else { return .error("nothing to do") }
            if !nodes[fi].isMaster { nodes[fi].isMaster = true }
            else if let s = nodes.firstIndex(where: { !$0.isMaster }) { nodes[s].isMaster = true }
            return .ok
        case "removemaster":
            let masters = nodes.filter(\.isMaster).count
            guard nodes.count >= 2 && masters >= 2 else { return .error("nothing to do") }
            if nodes[fi].isMaster { nodes[fi].isMaster = false }
            else if let m = nodes.lastIndex(where: \.isMaster) { nodes[m].isMaster = false }
            return .ok
        case "rollnext", "rollprev":
            guard let s = (command == "rollnext" ? nodes.firstIndex(where: { !$0.isMaster }) : nodes.lastIndex(where: { !$0.isMaster })),
                  let m = (nodes[fi].isMaster ? fi : nodes.firstIndex(where: \.isMaster)) else { return .ok }
            let newMaster = nodes[s].window
            nodes[s].isMaster = true
            nodes[s].percMaster = nodes[m].percMaster
            nodes[m].isMaster = false
            if command == "rollnext" {
                let old = nodes.remove(at: m)
                nodes.append(old)
            } else {
                let promoted = nodes.remove(at: s)
                nodes.insert(promoted, at: 0)
            }
            return .focus(newMaster)
        default:
            return .error("unknown master layout message '\(command)'")
        }
    }

    public func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID? {
        if ctx.master.focusMasterOnClose, let m = nodes.first(where: \.isMaster) { return m.window }
        let boxes = tileBoxes(ctx)
        let nearest = nodes.compactMap { n in boxes[n.window].map { (n.window, $0.distanceSquared(to: point)) } }.min { $0.1 < $1.1 }
        return nearest?.0 ?? nodes.first?.window
    }
}
