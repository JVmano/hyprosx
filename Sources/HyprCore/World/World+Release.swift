import Foundation

extension World {
    public func releaseParked() -> [Effect] {
        guard let area = monitor(focusedMonitor)?.visibleFrame ?? monitors.first?.visibleFrame else { return [] }
        var changes: [FrameChange] = []
        for id in windows.keys.sorted() {
            guard var w = windows[id], w.isParked else { continue }
            let size = (w.appliedFrame ?? w.lastFrame).size
            let width = min(size.width, area.width)
            let height = min(size.height, area.height)
            let frame = Rect(x: area.x + (area.width - width) / 2, y: area.y + (area.height - height) / 2, width: width, height: height)
            w.isParked = false
            w.appliedFrame = frame
            windows[id] = w
            changes.append(FrameChange(id: id, frame: frame, reason: .restore))
        }
        return changes.isEmpty ? [] : [.setFrames(changes)]
    }
}
