import Foundation

extension World {
    static let minimumStrip = 20.0
    static let overlapTolerance = 2.0

    @discardableResult
    func clearPlacement(_ id: WindowID) -> Bool {
        placementOrder.removeAll { $0 == id }
        guard windows[id]?.placedFrame != nil else { return false }
        windows[id]?.dropPlacement()
        return true
    }

    func releasePlacement(_ id: WindowID?) {
        guard let id, clearPlacement(id), let wsID = windows[id]?.workspace else { return }
        refresh([wsID])
    }

    func activePlacements(_ ws: Workspace, area: Rect) -> [WindowID: Rect] {
        var out: [WindowID: Rect] = [:]
        for id in ws.tiledIDs {
            if let rect = windows[id]?.placedFrame, World.clip(rect, to: area) != nil { out[id] = rect }
        }
        return out
    }

    func reconcilePlacements(_ ws: Workspace) {
        let area = workArea(for: ws)
        var active = activePlacements(ws, area: area)
        for id in ws.tiledIDs where windows[id]?.placedFrame != nil && active[id] == nil { clearPlacement(id) }
        while !active.isEmpty, hasNoRoom(ws, placements: active, area: area) {
            guard let newest = placementOrder.last(where: { active[$0] != nil }) ?? active.keys.min() else { break }
            clearPlacement(newest)
            active[newest] = nil
        }
    }

    func hasNoRoom(_ ws: Workspace, placements: [WindowID: Rect], area: Rect) -> Bool {
        guard ws.tiledIDs.contains(where: { placements[$0] == nil }) else { return false }
        let clipped = placements.values.compactMap { World.clip($0, to: area) }
        return World.freeStrips(placed: clipped, in: area, gaps: gapsIn(for: ws)).isEmpty
    }

    func placeWindow(_ id: WindowID, _ width: Measure, _ height: Measure, _ x: Measure, _ y: Measure) -> String? {
        guard let w = windows[id], w.suspended == nil, let ws = workspaces[w.workspace] else { return "no active window" }
        let area = workArea(for: ws)
        let rect = Rect(x: World.bounded(area.x + measure(x, base: area.width)), y: World.bounded(area.y + measure(y, base: area.height)),
                        width: min(max(World.minimumWindowSize, measure(width, base: area.width)), World.extent),
                        height: min(max(World.minimumWindowSize, measure(height, base: area.height)), World.extent)).rounded()
        if w.isFloating {
            windows[id]?.floatingFrame = rect
            refresh([ws.id])
            emit(.saveState)
            return nil
        }
        guard w.fullscreenMode == nil else { return "placeactive does not work on a fullscreen window" }
        guard World.clip(rect, to: area) != nil else {
            releasePlacement(id)
            return "placeactive rectangle is outside the work area"
        }
        for other in ws.tiledIDs where other != id {
            guard let older = windows[other]?.placedFrame, World.overlaps(older, rect) else { continue }
            clearPlacement(other)
        }
        windows[id]?.placedFrame = rect
        placementOrder.removeAll { $0 == id || windows[$0]?.placedFrame == nil }
        placementOrder.append(id)
        refresh([ws.id])
        return windows[id]?.placedFrame == nil ? "placeactive leaves no room for the other windows" : nil
    }

    func clearPlacementsAhead(of id: WindowID, _ direction: Direction, in ws: Workspace) -> Bool {
        guard windows[id]?.placedFrame == nil else { return false }
        let boxes = effectiveBoxes(ws)
        guard let box = boxes[id] else { return false }
        var cleared = false
        for other in ws.tiledIDs where other != id {
            guard windows[other]?.placedFrame != nil, let target = boxes[other] else { continue }
            let ahead: Bool, span: Double
            switch direction {
            case .left: ahead = target.maxX <= box.minX + World.overlapTolerance; span = min(target.maxY, box.maxY) - max(target.minY, box.minY)
            case .right: ahead = target.minX >= box.maxX - World.overlapTolerance; span = min(target.maxY, box.maxY) - max(target.minY, box.minY)
            case .up: ahead = target.maxY <= box.minY + World.overlapTolerance; span = min(target.maxX, box.maxX) - max(target.minX, box.minX)
            case .down: ahead = target.minY >= box.maxY - World.overlapTolerance; span = min(target.maxX, box.maxX) - max(target.minX, box.minX)
            }
            if ahead && span > 1 { cleared = clearPlacement(other) || cleared }
        }
        return cleared
    }

    static func clip(_ rect: Rect, to area: Rect) -> Rect? {
        let x0 = max(rect.minX, area.minX), x1 = min(rect.maxX, area.maxX)
        let y0 = max(rect.minY, area.minY), y1 = min(rect.maxY, area.maxY)
        guard x1 - x0 > overlapTolerance, y1 - y0 > overlapTolerance else { return nil }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    static func overlaps(_ a: Rect, _ b: Rect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) > overlapTolerance && min(a.maxY, b.maxY) - max(a.minY, b.minY) > overlapTolerance
    }

    func effectiveBoxes(_ ws: Workspace) -> [WindowID: Rect] {
        let ctx = layoutContext(ws)
        let area = ctx.workArea
        let placements = activePlacements(ws, area: area)
        guard !placements.isEmpty else { return ws.layout.current.tileBoxes(ctx) }
        let gaps = gapsIn(for: ws)
        var out: [WindowID: Rect] = [:]
        for id in ws.tiledIDs {
            guard let rect = placements[id], let inside = World.clip(rect, to: area) else { continue }
            out[id] = World.clip(World.inflated(inside, in: area, gaps: gaps), to: area) ?? inside
        }
        let strips = placementStrips(ws, placements: placements.filter { out[$0.key] != nil }, area: area)
        var rest = ws.layout
        for id in placements.keys { rest.update { $0.remove(id) } }
        if strips.count == 1 {
            var stripCtx = ctx
            stripCtx.workArea = strips[0]
            out.merge(rest.current.tileBoxes(stripCtx)) { a, _ in a }
            return out
        }
        var buckets = Array(repeating: [WindowID](), count: strips.count)
        for (i, id) in rest.current.windowIDs.enumerated() { buckets[i % strips.count].append(id) }
        for (strip, ids) in zip(strips, buckets) where !ids.isEmpty {
            let height = strip.height / Double(ids.count)
            for (row, id) in ids.enumerated() {
                out[id] = Rect(x: strip.x, y: strip.y + height * Double(row), width: strip.width, height: height)
            }
        }
        return out
    }

    static func inflated(_ rect: Rect, in area: Rect, gaps: Edges) -> Rect {
        let left = WindowGeometry.sticks(rect.minX, area.minX) ? 0 : gaps.left
        let right = WindowGeometry.sticks(rect.maxX, area.maxX) ? 0 : gaps.right
        let top = WindowGeometry.sticks(rect.minY, area.minY) ? 0 : gaps.top
        let bottom = WindowGeometry.sticks(rect.maxY, area.maxY) ? 0 : gaps.bottom
        return Rect(x: rect.x - left, y: rect.y - top, width: rect.width + left + right, height: rect.height + top + bottom)
    }

    static func freeStrips(placed rects: [Rect], in area: Rect, gaps: Edges) -> [Rect] {
        let boxes = rects.map { clip(inflated($0, in: area, gaps: gaps), to: area) ?? $0 }
        var strips: [Rect] = []
        if rects.allSatisfy({ $0.minY < area.minY + overlapTolerance && $0.maxY > area.maxY - overlapTolerance }) {
            var edge = area.minX
            for box in boxes.sorted(by: { $0.minX < $1.minX }) {
                if box.minX - edge >= minimumStrip { strips.append(Rect(x: edge, y: area.y, width: box.minX - edge, height: area.height)) }
                edge = max(edge, box.maxX)
            }
            if area.maxX - edge >= minimumStrip { strips.append(Rect(x: edge, y: area.y, width: area.maxX - edge, height: area.height)) }
        } else {
            let left = boxes.map(\.minX).min() ?? area.minX, right = boxes.map(\.maxX).max() ?? area.maxX
            let top = boxes.map(\.minY).min() ?? area.minY, bottom = boxes.map(\.maxY).max() ?? area.maxY
            let candidates = [
                Rect(x: area.x, y: area.y, width: left - area.minX, height: area.height),
                Rect(x: right, y: area.y, width: area.maxX - right, height: area.height),
                Rect(x: area.x, y: area.y, width: area.width, height: top - area.minY),
                Rect(x: area.x, y: bottom, width: area.width, height: area.maxY - bottom),
            ]
            let roomy = candidates.filter { $0.width >= minimumStrip && $0.height >= minimumStrip }
            if let best = roomy.max(by: { $0.width * $0.height < $1.width * $1.height }) { strips = [best] }
        }
        return strips
    }
}
