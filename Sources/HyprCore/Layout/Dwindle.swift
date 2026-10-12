import Foundation

private func safeRatio(_ v: Double) -> Double { v.isNaN ? 1 : clampRatio(v) }

public struct DwindleLayout: TiledLayout, Equatable, Codable, Sendable {
    struct Node: Equatable, Codable, Sendable {
        var parent: Int?
        var children: [Int] = []
        var window: WindowID?
        var splitTop = false
        var ratio = 1.0
        var forced = false
    }

    var nodes: [Int: Node] = [:]
    var root: Int?
    var nextID = 1
    var overrideDirection: Direction?

    public init() {}

    public var windowIDs: [WindowID] { leaves(from: root).compactMap { nodes[$0]?.window } }

    func leaves(from id: Int?) -> [Int] {
        guard let id, let n = nodes[id] else { return [] }
        return n.children.isEmpty ? [id] : n.children.flatMap { leaves(from: $0) }
    }

    func leaf(of window: WindowID) -> Int? { nodes.first { $0.value.window == window }?.key }

    mutating func make(_ node: Node) -> Int {
        let id = nextID
        nextID += 1
        nodes[id] = node
        return id
    }

    mutating func replace(_ old: Int, with new: Int, in parent: Int?) {
        if let parent, var p = nodes[parent] {
            p.children = p.children.map { $0 == old ? new : $0 }
            nodes[parent] = p
        } else {
            root = new
        }
    }

    func effectiveSplitTop(_ n: Node, _ box: Rect, _ o: DwindleOptions) -> Bool {
        if n.forced || o.preserveSplit || o.smartSplit || o.preciseMouseMove { return n.splitTop }
        return box.height * o.splitWidthMultiplier > box.width
    }

    func nodeBoxes(_ ctx: LayoutContext) -> [Int: Rect] {
        var out: [Int: Rect] = [:]
        func walk(_ id: Int, _ box: Rect) {
            out[id] = box
            guard let n = nodes[id], n.children.count == 2 else { return }
            if !effectiveSplitTop(n, box, ctx.dwindle) {
                let first = box.width / 2 * n.ratio
                walk(n.children[0], Rect(x: box.x, y: box.y, width: max(0, first), height: box.height))
                walk(n.children[1], Rect(x: box.x + first, y: box.y, width: max(0, box.width - first), height: box.height))
            } else {
                let first = box.height / 2 * n.ratio
                walk(n.children[0], Rect(x: box.x, y: box.y, width: box.width, height: max(0, first)))
                walk(n.children[1], Rect(x: box.x, y: box.y + first, width: box.width, height: max(0, box.height - first)))
            }
        }
        if let root { walk(root, ctx.workArea) }
        return out
    }

    public func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        for (id, box) in nodeBoxes(ctx) { if let w = nodes[id]?.window { out[w] = box } }
        return out
    }

    func closestLeaf(to point: Point, _ boxes: [Int: Rect], skipping: Int? = nil) -> Int? {
        var best: (Int, Double)?
        for id in leaves(from: root) where id != skipping {
            guard let box = boxes[id] else { continue }
            let d = box.distanceSquared(to: point)
            if best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    public mutating func insert(_ id: WindowID, _ ctx: LayoutContext) {
        guard leaf(of: id) == nil else { return }
        let o = ctx.dwindle
        let boxes = nodeBoxes(ctx)
        let mouse = ctx.focalPoint ?? ctx.cursor
        var opening: Int?
        if let focal = ctx.focalPoint {
            opening = closestLeaf(to: focal, boxes)
        } else if o.useActiveForSplits {
            if let f = ctx.focused { opening = leaf(of: f) }
            if opening == nil { opening = closestLeaf(to: mouse, boxes) }
        } else {
            opening = leaves(from: root).first { boxes[$0]?.contains(mouse) == true } ?? closestLeaf(to: mouse, boxes)
        }
        if opening == nil { opening = leaves(from: root).first }
        let newLeaf = make(Node(window: id))
        guard let target = opening, let box = boxes[target] else { root = newLeaf; return }

        let grandparent = nodes[target]?.parent
        var parent = Node(parent: grandparent)
        parent.ratio = safeRatio(o.defaultSplitRatio)
        let sideBySide = box.width > box.height * o.splitWidthMultiplier
        parent.splitTop = !sideBySide
        var newFirst: Bool
        if let dir = overrideDirection {
            parent.splitTop = dir == .up || dir == .down
            parent.forced = true
            newFirst = dir == .up || dir == .left
            if !o.permanentDirectionOverride { overrideDirection = nil }
        } else if o.smartSplit || (o.preciseMouseMove && ctx.dragging) {
            let delta = mouse - box.center
            let slope = delta.y / delta.x
            if abs(slope) < box.height / box.width {
                parent.splitTop = false
                newFirst = delta.x <= 0
            } else {
                parent.splitTop = true
                newFirst = delta.y <= 0
            }
        } else if o.forceSplit == 0 || ctx.focalPoint != nil || ctx.dragging {
            newFirst = (sideBySide && mouse.x < box.x + box.width / 2) || (!sideBySide && mouse.y < box.y + box.height / 2)
        } else {
            newFirst = o.forceSplit == 1
        }
        if o.splitBias == 1 && newFirst { parent.ratio = 2 - parent.ratio }
        parent.children = newFirst ? [newLeaf, target] : [target, newLeaf]
        let parentID = make(parent)
        nodes[target]?.parent = parentID
        nodes[newLeaf]?.parent = parentID
        replace(target, with: parentID, in: grandparent)
    }

    public mutating func remove(_ id: WindowID) {
        guard let l = leaf(of: id) else { return }
        guard let p = nodes[l]?.parent, let parent = nodes[p] else {
            nodes[l] = nil
            root = nil
            return
        }
        guard let sibling = parent.children.first(where: { $0 != l }) else { return }
        nodes[sibling]?.parent = parent.parent
        replace(p, with: sibling, in: parent.parent)
        nodes[l] = nil
        nodes[p] = nil
    }

    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let la = leaf(of: a), let lb = leaf(of: b) else { return }
        nodes[la]?.window = b
        nodes[lb]?.window = a
    }

    public mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext) {
        guard let l = leaf(of: id) else { return }
        let boxes = nodeBoxes(ctx)
        guard let box = boxes[l] else { return }
        let wa = ctx.workArea
        let dl = WindowGeometry.sticks(box.minX, wa.minX), dr = WindowGeometry.sticks(box.maxX, wa.maxX)
        let dt = WindowGeometry.sticks(box.minY, wa.minY), db = WindowGeometry.sticks(box.maxY, wa.maxY)
        var allowed = Point(x: delta.x.isFinite ? delta.x : 0, y: delta.y.isFinite ? delta.y : 0)
        if dl && dr { allowed.x = 0 }
        if dt && db { allowed.y = 0 }
        if ctx.dwindle.smartResizing {
            smartResize(l, allowed, corner, dl: dl, dr: dr, dt: dt, db: db, boxes, ctx)
        } else {
            plainResize(l, allowed, boxes, ctx)
        }
    }

    mutating func smartResize(_ l: Int, _ allowed: Point, _ corner: Corner, dl: Bool, dr: Bool, dt: Bool, db: Bool, _ boxes: [Int: Rect], _ ctx: LayoutContext) {
        let none = corner == .none
        let left = corner == .topLeft || corner == .bottomLeft || dr
        let right = corner == .topRight || corner == .bottomRight || dl
        let top = corner == .topLeft || corner == .topRight || db
        let bottom = corner == .bottomLeft || corner == .bottomRight || dt
        var vOuter: Int?, vInner: Int?, hOuter: Int?, hInner: Int?
        var cur = l
        while let p = nodes[cur]?.parent, let pn = nodes[p], let pbox = boxes[p] {
            let splitTop = effectiveSplitTop(pn, pbox, ctx.dwindle)
            if vOuter == nil && splitTop && (none || (top && pn.children[1] == cur) || (bottom && pn.children[0] == cur)) { vOuter = cur }
            else if vOuter == nil && vInner == nil && splitTop { vInner = cur }
            else if hOuter == nil && !splitTop && (none || (left && pn.children[1] == cur) || (right && pn.children[0] == cur)) { hOuter = cur }
            else if hOuter == nil && hInner == nil && !splitTop { hInner = cur }
            if vOuter != nil && hOuter != nil { break }
            cur = p
        }
        func apply(outer: Int?, inner: Int?, amount: Double, extent: (Rect) -> Double) {
            let boxes = nodeBoxes(ctx)
            guard let outer, let op = nodes[outer]?.parent, let obox = boxes[op], extent(obox) > 0 else { return }
            let outerRatio = nodes[op]?.ratio ?? 1
            nodes[op]?.ratio = safeRatio(outerRatio + amount * 2 / extent(obox))
            guard let inner, let ip = nodes[inner]?.parent, let ibox = boxes[inner] else { return }
            let original = extent(ibox)
            guard let newParentBox = nodeBoxes(ctx)[ip], extent(newParentBox) > 0 else { return }
            let pe = extent(newParentBox)
            let innerFirst = nodes[ip]?.children.first == inner
            nodes[ip]?.ratio = innerFirst
                ? safeRatio((original - amount) / pe * 2)
                : safeRatio(2 - (original + amount) / pe * 2)
        }
        apply(outer: hOuter, inner: hInner, amount: allowed.x, extent: { $0.width })
        apply(outer: vOuter, inner: vInner, amount: allowed.y, extent: { $0.height })
    }

    mutating func plainResize(_ l: Int, _ allowed: Point, _ boxes: [Int: Rect], _ ctx: LayoutContext) {
        guard let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] else { return }
        let parentSideBySide = !effectiveSplitTop(pn, pbox, ctx.dwindle)
        var other: Int?
        var cur = p
        while let up = nodes[cur]?.parent, let un = nodes[up], let ubox = boxes[up] {
            if !effectiveSplitTop(un, ubox, ctx.dwindle) != parentSideBySide { other = up; break }
            cur = up
        }
        func bump(_ id: Int, _ amount: Double, _ extent: Double) {
            guard extent > 0, let current = nodes[id]?.ratio else { return }
            nodes[id]?.ratio = safeRatio(current + amount * 2 / extent)
        }
        guard let other, let obox = boxes[other] else {
            if parentSideBySide { bump(p, allowed.x, pbox.width) } else { bump(p, allowed.y, pbox.height) }
            return
        }
        let side = parentSideBySide ? p : other
        let stacked = parentSideBySide ? other : p
        bump(side, allowed.x, (parentSideBySide ? pbox : obox).width)
        bump(stacked, allowed.y, (parentSideBySide ? obox : pbox).height)
    }

    public mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool {
        guard let l = leaf(of: id) else { return false }
        let boxes = nodeBoxes(ctx)
        guard let box = boxes[l] else { return false }
        let focal = WindowGeometry.focalPoint(of: box, direction)
        guard ctx.workArea.contains(focal) else { return false }
        if let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] {
            let splitTop = effectiveSplitTop(pn, pbox, ctx.dwindle)
            let isFirst = pn.children[0] == l
            let siblingIsLeaf = nodes[pn.children[isFirst ? 1 : 0]]?.children.isEmpty == true
            let lands = (direction == .up && splitTop && !isFirst) || (direction == .down && splitTop && isFirst)
                || (direction == .left && !splitTop && !isFirst) || (direction == .right && !splitTop && isFirst)
            if lands && siblingIsLeaf { overrideDirection = direction }
        }
        remove(id)
        var c = ctx
        c.focalPoint = focal
        c.focused = nil
        insert(id, c)
        return true
    }

    public mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult {
        let words = text.split(separator: " ").map(String.init)
        guard let command = words.first else { return .error("empty layout message") }
        if command == "preselect" {
            overrideDirection = words.count > 1 ? Direction.parse(words[1]) : nil
            return .ok
        }
        guard let focused = ctx.focused, let l = leaf(of: focused) else { return .error("no focused tiled window") }
        let boxes = nodeBoxes(ctx)
        switch command {
        case "togglesplit":
            guard let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] else { return .error("window has no split") }
            let toggled = !effectiveSplitTop(pn, pbox, ctx.dwindle)
            nodes[p]?.splitTop = toggled
            return .ok
        case "swapsplit":
            guard let p = nodes[l]?.parent else { return .error("window has no split") }
            nodes[p]?.children.reverse()
            return .ok
        case "rotatesplit":
            guard let p = nodes[l]?.parent, let pn = nodes[p], let pbox = boxes[p] else { return .error("window has no split") }
            let angle = words.count > 1 ? (Int(words[1]) ?? 90) : 90
            let n = ((angle / 90 % 4) + 4) % 4
            let splitTop = effectiveSplitTop(pn, pbox, ctx.dwindle)
            var shouldSwap = false
            switch n {
            case 1: shouldSwap = splitTop; nodes[p]?.splitTop = !splitTop; nodes[p]?.forced = true
            case 2: shouldSwap = true
            case 3: shouldSwap = !splitTop; nodes[p]?.splitTop = !splitTop; nodes[p]?.forced = true
            default: break
            }
            if shouldSwap { nodes[p]?.children.reverse() }
            return .ok
        case "splitratio":
            guard let p = nodes[l]?.parent else { return .error("window has no split") }
            let exact = words.contains("exact")
            guard let value = words.dropFirst().first(where: { $0 != "exact" }).flatMap(Double.init), value.isFinite else { return .error("invalid splitratio") }
            let current = nodes[p]?.ratio ?? 1
            nodes[p]?.ratio = safeRatio(exact ? value : current + value)
            return .ok
        case "movetoroot":
            return moveToRoot(l, stable: !words.contains("unstable"))
        default:
            return .error("unknown dwindle layout message '\(command)'")
        }
    }

    mutating func moveToRoot(_ l: Int, stable: Bool) -> LayoutMessageResult {
        guard let root, let p = nodes[l]?.parent, p != root else { return .error("window is already at the root") }
        var ancestor = l
        while let up = nodes[ancestor]?.parent, up != root { ancestor = up }
        guard let rootNode = nodes[root], let other = rootNode.children.first(where: { $0 != ancestor }) else { return .error("no root split") }
        guard let lp = nodes[l]?.parent, let lpNode = nodes[lp] else { return .error("no parent") }
        nodes[lp]?.children = lpNode.children.map { $0 == l ? other : $0 }
        nodes[root]?.children = rootNode.children.map { $0 == other ? l : $0 }
        nodes[other]?.parent = lp
        nodes[l]?.parent = root
        if stable { nodes[root]?.children.reverse() }
        return .ok
    }

    public func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID? {
        closestLeaf(to: point, nodeBoxes(ctx)).flatMap { nodes[$0]?.window }
    }
}
