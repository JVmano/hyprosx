import Foundation

public enum FrameReason: Equatable, Sendable { case layout, open, workspaceIn(leftward: Bool), specialIn, manualResize, restore }

public enum SlideOut: Equatable, Sendable { case workspace(leftward: Bool), special }

public struct FrameChange: Equatable, Sendable {
    public var id: WindowID
    public var frame: Rect
    public var reason: FrameReason
    public init(id: WindowID, frame: Rect, reason: FrameReason) { self.id = id; self.frame = frame; self.reason = reason }
}

public struct ParkRequest: Equatable, Sendable {
    public var id: WindowID
    public var origin: Point
    public var slide: SlideOut?
    public init(id: WindowID, origin: Point, slide: SlideOut? = nil) { self.id = id; self.origin = origin; self.slide = slide }
}

public enum Effect: Equatable, Sendable {
    case setFrames([FrameChange])
    case park([ParkRequest])
    case focus(WindowID)
    case raise(WindowID)
    case close(WindowID)
    case signal(pid: Int32, signal: Int32)
    case hideApp(Int32)
    case unhideApp(Int32)
    case spawn(String, token: Int?)
    case warpCursor(Point)
    case submapChanged(String)
    case statusChanged
    case saveState
    case reloadConfig
    case exitApp
}

public struct CommandResult: Equatable, Sendable {
    public var reply: String
    public var isError: Bool
    public var effects: [Effect]
}

public enum PlatformEvent: Equatable, Sendable {
    case monitorsChanged([MonitorInfo])
    case windowAppeared(WindowSnapshot)
    case windowDisappeared(WindowID)
    case windowSuspended(WindowID, SuspendReason)
    case windowResumed(WindowID)
    case appHidden(pid: Int32, byUser: Bool)
    case appUnhidden(pid: Int32)
    case appTerminated(pid: Int32)
    case windowTitleChanged(WindowID, String, early: Bool)
    case windowFrameChanged(WindowID, Rect, userDriven: Bool)
    case dragEnded(cursor: Point)
    case focusChanged(WindowID?)
    case cursorMoved(Point)
    case mouseBindStarted(MouseBindAction, Point)
    case mouseBindMoved(Point)
    case mouseBindEnded(Point)
}
