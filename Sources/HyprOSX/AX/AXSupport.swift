import AppKit
import ApplicationServices
import HyprCore

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

extension Rect {
    init(_ r: CGRect) { self.init(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.width), height: Double(r.height)) }
}

extension CGRect {
    init(_ r: Rect) { self.init(x: r.x, y: r.y, width: r.width, height: r.height) }
}

extension CGPoint {
    init(_ p: Point) { self.init(x: p.x, y: p.y) }
}

enum AX {
    static func windowID(_ e: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(e, &id) == .success && id != 0 ? id : nil
    }

    static func value(_ e: AXUIElement, _ attribute: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, attribute as CFString, &v) == .success ? v : nil
    }

    static func string(_ e: AXUIElement, _ a: String) -> String? { value(e, a) as? String }

    static func bool(_ e: AXUIElement, _ a: String) -> Bool? { (value(e, a) as? NSNumber)?.boolValue }

    static func element(_ e: AXUIElement, _ a: String) -> AXUIElement? {
        guard let v = value(e, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elementList(_ e: AXUIElement, _ a: String) -> [AXUIElement]? {
        guard let array = value(e, a) as? [AnyObject] else { return nil }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    static func elements(_ e: AXUIElement, _ a: String) -> [AXUIElement] { elementList(e, a) ?? [] }

    static func frame(_ e: AXUIElement) -> Rect? {
        guard let p = value(e, kAXPositionAttribute), let s = value(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return Rect(CGRect(origin: point, size: size))
    }

    @discardableResult
    static func setPosition(_ e: AXUIElement, _ p: CGPoint) -> AXError {
        var point = p
        guard let v = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v)
    }

    @discardableResult
    static func setSize(_ e: AXUIElement, _ s: CGSize) -> AXError {
        var size = s
        guard let v = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v)
    }

    @discardableResult
    static func setBool(_ e: AXUIElement, _ a: String, _ b: Bool) -> AXError {
        AXUIElementSetAttributeValue(e, a as CFString, b as CFTypeRef)
    }

    @discardableResult
    static func perform(_ e: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(e, action as CFString)
    }

    static func windowExists(_ id: WindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]] else { return false }
        return list.contains { ($0[kCGWindowNumber as String] as? Int).map { WindowID($0) } == id }
    }

    static func windowLevel(_ id: WindowID) -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]] else { return nil }
        return list.first?[kCGWindowLayer as String] as? Int
    }
}

struct AXWindowAttributes: WindowAttributeReader {
    let window: AXUIElement
    let app: AXUIElement
    let windowID: WindowID

    func attribute(_ b: WindowButton) -> String {
        switch b {
        case .close: return kAXCloseButtonAttribute
        case .fullscreen: return kAXFullScreenButtonAttribute
        case .zoom: return kAXZoomButtonAttribute
        case .minimize: return kAXMinimizeButtonAttribute
        }
    }

    func subrole() -> String? { AX.string(window, kAXSubroleAttribute) }
    func title() -> String? { AX.string(window, kAXTitleAttribute) }
    func identifier() -> String? { AX.string(window, kAXIdentifierAttribute) }
    func hasButton(_ b: WindowButton) -> Bool { AX.element(window, attribute(b)) != nil }
    func isButtonEnabled(_ b: WindowButton) -> Bool? { AX.element(window, attribute(b)).flatMap { AX.bool($0, kAXEnabledAttribute) } }
    func isFocused() -> Bool? { AX.bool(window, kAXFocusedAttribute) }
    func isMain() -> Bool? { AX.bool(window, kAXMainAttribute) }
    func isAppFocusedWindow() -> Bool { AX.element(app, kAXFocusedWindowAttribute).flatMap(AX.windowID) == windowID }
}
