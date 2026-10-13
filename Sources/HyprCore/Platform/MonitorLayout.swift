import Foundation

public struct ScreenDescription: Equatable, Sendable {
    public var name: String
    public var frame: Rect
    public var visibleFrame: Rect
    public init(name: String, frame: Rect, visibleFrame: Rect) { self.name = name; self.frame = frame; self.visibleFrame = visibleFrame }
}

public enum MonitorLayout {
    public static func infos(_ screens: [ScreenDescription]) -> [MonitorInfo] {
        guard let primary = screens.first else { return [] }
        func flip(_ r: Rect) -> Rect { Rect(x: r.x, y: primary.frame.height - (r.y + r.height), width: r.width, height: r.height) }
        let flipped = screens.map { ($0.name, flip($0.frame), flip($0.visibleFrame)) }
        let rest = flipped.dropFirst().sorted { ($0.1.x, $0.1.y, $0.0) < ($1.1.x, $1.1.y, $1.0) }
        var seen: [String: Int] = [:]
        return ([flipped[0]] + rest).enumerated().map { index, screen in
            seen[screen.0, default: 0] += 1
            let count = seen[screen.0]!
            return MonitorInfo(id: index, name: count == 1 ? screen.0 : "\(screen.0) (\(count))", frame: screen.1, visibleFrame: screen.2)
        }
    }
}
