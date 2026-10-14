import Foundation

extension World {
    static let minimumStrip = 20.0
    static let overlapTolerance = 2.0

    @discardableResult
    func clearPlacement(_ id: WindowID) -> Bool {
        guard windows[id]?.placedFrame != nil else { return false }
        windows[id]?.dropPlacement()
        return true
    }

    func releasePlacement(_ id: WindowID?) {
        guard let id, clearPlacement(id), let wsID = windows[id]?.workspace else { return }
        refresh([wsID])
    }

    func reconcilePlacements(_ ws: Workspace) {
        let area = fullscreenArea(for: ws)
        for id in ws.tiledIDs {
            guard let stamp = windows[id]?.placedArea, !stamp.isClose(to: area) else { continue }
            clearPlacement(id)
        }
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
        for other in ws.tiledIDs where other != id {
            guard let older = windows[other]?.placedFrame, World.overlaps(older, rect) else { continue }
            clearPlacement(other)
        }
        windows[id]?.placedFrame = rect
        windows[id]?.placedArea = fullscreenArea(for: ws)
        refresh([ws.id])
        return nil
    }

    static func overlaps(_ a: Rect, _ b: Rect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) > overlapTolerance && min(a.maxY, b.maxY) - max(a.minY, b.minY) > overlapTolerance
    }

    func effectiveBoxes(_ ws: Workspace) -> [WindowID: Rect] {
        let ctx = layoutContext(ws)
        let placed = ws.tiledIDs.filter { windows[$0]?.placedFrame != nil }
        guard !placed.isEmpty else { return ws.layout.current.tileBoxes(ctx) }
        let gaps = gapsIn(for: ws)
        var out: [WindowID: Rect] = [:]
        var rects: [Rect] = []
        for id in placed {
            guard let rect = windows[id]?.placedFrame else { continue }
            rects.append(rect)
            out[id] = World.inflated(rect, in: ctx.workArea, gaps: gaps)
        }
        let strips = World.freeStrips(placed: rects, in: ctx.workArea, gaps: gaps)
        var rest = ws.layout
        for id in placed { rest.update { $0.remove(id) } }
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
        let boxes = rects.map { inflated($0, in: area, gaps: gaps) }
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
        return strips.isEmpty ? [area] : strips
    }
}
