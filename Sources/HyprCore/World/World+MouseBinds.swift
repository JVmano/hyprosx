import Foundation

struct MouseDrag: Equatable, Sendable {
    var id: WindowID
    var action: MouseBindAction
    var start: Point
    var last: Point
    var corner: Corner
    var startFrame: Rect
}

extension World {
    func mouseBindStarted(_ action: MouseBindAction, at p: Point) {
        cursor = p
        mouseDrag = nil
        guard let id = windowAt(p), let w = windows[id], w.suspended == nil, w.fullscreenMode == nil else { return }
        let frame = w.appliedFrame ?? w.lastFrame
        let left = p.x < frame.center.x, top = p.y < frame.center.y
        let corner: Corner = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        mouseDrag = MouseDrag(id: id, action: action, start: p, last: p, corner: corner, startFrame: frame)
        clearPlacement(id)
        if action == .move && !w.isFloating {
            dragging = id
            dragIsResize = false
        }
        focusWindow(id, warp: false, emitEffect: true)
    }

    func mouseBindMoved(to p: Point) {
        cursor = p
        guard var drag = mouseDrag, let w = windows[drag.id], var ws = workspaces[w.workspace] else { return }
        let total = p - drag.start
        let step = p - drag.last
        drag.last = p
        mouseDrag = drag
        switch (drag.action, w.isFloating) {
        case (.move, true):
            let frame = Rect(origin: drag.startFrame.origin + total, size: drag.startFrame.size)
            windows[drag.id]?.floatingFrame = frame
            var touched: Set<Int> = [ws.id]
            if let m = monitorID(containing: frame.center), m != ws.monitor, let target = activeSpecial[m] ?? activeWorkspace[m] {
                relocate(drag.id, to: target)
                if focusedWindow == drag.id { focusedMonitor = m }
                touched.insert(target)
                emit(.statusChanged)
            }
            refresh(touched, reason: .manualResize)
        case (.move, false):
            let frame = Rect(origin: drag.startFrame.origin + total, size: drag.startFrame.size)
            windows[drag.id]?.lastFrame = frame
            emit(.setFrames([FrameChange(id: drag.id, frame: frame, reason: .manualResize)]))
        case (.resize, true):
            windows[drag.id]?.floatingFrame = World.resizedFloating(drag.startFrame, by: total, corner: drag.corner)
            refresh([ws.id], reason: .manualResize)
        case (.resize, false):
            let ctx = layoutContext(ws)
            ws.layout.update { $0.resize(drag.id, by: step, corner: drag.corner, ctx) }
            workspaces[ws.id] = ws
            refresh([ws.id], reason: .manualResize)
        }
    }

    func mouseBindEnded(at p: Point) {
        cursor = p
        guard let drag = mouseDrag else { return }
        mouseDrag = nil
        if drag.action == .move, dragging == drag.id {
            endDrag(at: p)
            return
        }
        if let w = windows[drag.id] { refresh([w.workspace]) }
        emit(.saveState)
    }

    static func resizedFloating(_ f: Rect, by d: Point, corner: Corner) -> Rect {
        let movesLeft = corner == .topLeft || corner == .bottomLeft
        let movesTop = corner == .topLeft || corner == .topRight
        let width = max(50, f.width + (movesLeft ? -d.x : d.x))
        let height = max(50, f.height + (movesTop ? -d.y : d.y))
        return Rect(x: movesLeft ? f.maxX - width : f.minX, y: movesTop ? f.maxY - height : f.minY, width: width, height: height)
    }
}
