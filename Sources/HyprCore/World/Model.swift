import Foundation

public struct MonitorInfo: Equatable, Codable, Sendable {
    public var id: Int
    public var name: String
    public var frame: Rect
    public var visibleFrame: Rect
    public init(id: Int, name: String, frame: Rect, visibleFrame: Rect) {
        self.id = id; self.name = name; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

public enum WindowKind: String, Codable, Sendable { case normal, dialog }

public struct WindowSnapshot: Equatable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var frame: Rect
    public var kind: WindowKind
    public init(id: WindowID, pid: Int32, bundleID: String, appName: String, title: String, frame: Rect, kind: WindowKind) {
        self.id = id; self.pid = pid; self.bundleID = bundleID; self.appName = appName; self.title = title; self.frame = frame; self.kind = kind
    }
}

public enum SuspendReason: String, Codable, Sendable { case minimized, nativeFullscreen, appHidden }

public struct ManagedWindow: Equatable, Codable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var initialTitle: String
    public var isModal: Bool
    public var workspace: Int
    public var isFloating: Bool
    public var floatingFrame: Rect
    public var fullscreenMode: Int?
    public var isPseudo = false
    public var pseudoSize = Size(width: 1280, height: 720)
    public var isPinned = false
    public var everFloated = false
    public var suspended: SuspendReason?
    public var appliedFrame: Rect?
    public var lastFrame: Rect
    public var isParked = false
    public var refitTarget: Rect?
    public var placedFrame: Rect?
    public var placedSlot: Rect?
    public var props: [String: String] = [:]
    public var address: String { String(format: "0x%x", id) }

    mutating func dropPlacement() {
        placedFrame = nil
        placedSlot = nil
    }
}

public enum LayoutKind: String, Codable, Sendable, CaseIterable { case dwindle, master, monocle }

public enum LayoutState: Equatable, Codable, Sendable {
    case dwindle(DwindleLayout)
    case master(MasterLayout)
    case monocle(MonocleLayout)

    public init(_ kind: LayoutKind) {
        switch kind {
        case .dwindle: self = .dwindle(DwindleLayout())
        case .master: self = .master(MasterLayout())
        case .monocle: self = .monocle(MonocleLayout())
        }
    }

    public var kind: LayoutKind {
        switch self {
        case .dwindle: return .dwindle
        case .master: return .master
        case .monocle: return .monocle
        }
    }

    public var current: any TiledLayout {
        switch self {
        case .dwindle(let l): return l
        case .master(let l): return l
        case .monocle(let l): return l
        }
    }

    @discardableResult
    public mutating func update<R>(_ body: (inout any TiledLayout) -> R) -> R {
        var layout = current
        let result = body(&layout)
        if let d = layout as? DwindleLayout { self = .dwindle(d) }
        else if let m = layout as? MasterLayout { self = .master(m) }
        else if let m = layout as? MonocleLayout { self = .monocle(m) }
        return result
    }
}

public struct Workspace: Equatable, Codable, Sendable {
    public var id: Int
    public var name: String
    public var monitor: Int
    public var homeMonitorName: String
    public var isSpecial: Bool
    public var layout: LayoutState
    public var floating: [WindowID] = []
    public var lastFocused: WindowID?
    public var persistent = false
    public var tiledIDs: [WindowID] { layout.current.windowIDs }
    public var windowIDs: [WindowID] { tiledIDs + floating }
}
