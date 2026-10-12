import Foundation

public typealias WindowID = UInt32

public enum Corner: Equatable, Sendable { case none, topLeft, topRight, bottomLeft, bottomRight }

public struct LayoutContext: Sendable {
    public var workArea: Rect
    public var focused: WindowID?
    public var cursor: Point
    public var focalPoint: Point?
    public var isFirstMap: Bool
    public var dragging: Bool
    public var dwindle: DwindleOptions
    public var master: MasterOptions
    public init(workArea: Rect, focused: WindowID? = nil, cursor: Point = Point(x: 1e9, y: 1e9), focalPoint: Point? = nil,
                isFirstMap: Bool = true, dragging: Bool = false, dwindle: DwindleOptions = DwindleOptions(), master: MasterOptions = MasterOptions()) {
        self.workArea = workArea; self.focused = focused; self.cursor = cursor; self.focalPoint = focalPoint
        self.isFirstMap = isFirstMap; self.dragging = dragging; self.dwindle = dwindle; self.master = master
    }
}

public enum LayoutMessageResult: Equatable, Sendable { case ok, focus(WindowID), error(String) }

public protocol TiledLayout: Sendable {
    var windowIDs: [WindowID] { get }
    mutating func insert(_ id: WindowID, _ ctx: LayoutContext)
    mutating func remove(_ id: WindowID)
    func tileBoxes(_ ctx: LayoutContext) -> [WindowID: Rect]
    mutating func resize(_ id: WindowID, by delta: Point, corner: Corner, _ ctx: LayoutContext)
    mutating func swap(_ a: WindowID, _ b: WindowID)
    mutating func moveWindow(_ id: WindowID, _ direction: Direction, _ ctx: LayoutContext) -> Bool
    mutating func message(_ text: String, _ ctx: LayoutContext) -> LayoutMessageResult
    func nextFocusCandidate(near point: Point, _ ctx: LayoutContext) -> WindowID?
}

func clampRatio(_ v: Double) -> Double { v.isNaN ? 1 : min(max(v, 0.1), 1.9) }
