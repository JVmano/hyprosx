import Foundation

public enum WindowButton: Sendable { case close, fullscreen, zoom, minimize }
public enum WindowClassification: Equatable, Sendable { case notAWindow, dialog, normal }

public protocol WindowAttributeReader {
    func subrole() -> String?
    func title() -> String?
    func identifier() -> String?
    func hasButton(_ b: WindowButton) -> Bool
    func isButtonEnabled(_ b: WindowButton) -> Bool?
    func isFocused() -> Bool?
    func isMain() -> Bool?
    func isAppFocusedWindow() -> Bool
}

public enum WindowClassifier {
    static let standard = "AXStandardWindow"
    static let firefoxFamily: Set<String> = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "app.zen-browser.zen"]
    static let levelSensitive: Set<String> = firefoxFamily.union([
        "com.tinyspeck.slackmacgap", "com.google.Chrome", "com.brave.Browser", "com.timpler.screenstudio", "pl.maketheweb.cleanshotx",
        "com.googlecode.iterm2", "com.microsoft.Outlook", "com.openai.codex", "com.electron.wispr-flow",
    ])
    static let fullscreenButtonOptional: Set<String> = [
        "org.gimp.gimp-2.10", "com.google.Chrome", "com.apple.ActivityMonitor", "org.alacritty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "org.qutebrowser.qutebrowser", "com.googlecode.iterm2", "org.gnu.Emacs",
        "com.microsoft.VSCode", "com.vscodium", "com.valvesoftware.steam.helper",
    ]

    public static func classify(_ w: WindowAttributeReader, bundleID: String?, isAccessoryApp: Bool, windowLevel: Int?) -> WindowClassification {
        let id = bundleID ?? ""
        guard isWindow(w, id, isAccessoryApp, windowLevel) else { return .notAWindow }
        return isDialog(w, id, windowLevel) ? .dialog : .normal
    }

    static func isWindow(_ w: WindowAttributeReader, _ id: String, _ accessory: Bool, _ level: Int?) -> Bool {
        if let level, level != 0, levelSensitive.contains(id) { return false }
        if id == "com.mitchellh.ghostty" && w.identifier() == "com.mitchellh.ghostty.quickTerminal" { return false }
        if id == "com.apple.dt.Xcode" && w.identifier() == "open_quickly" { return false }
        if id == "com.googlecode.iterm2" && !w.hasButton(.fullscreen) { return false }
        if accessory && !w.hasButton(.close) && id != "com.valvesoftware.steam.helper" { return false }
        if id == "org.gnu.Emacs" && w.subrole() == "AXFloatingWindow" { return false }
        if !firefoxFamily.contains(id) { return isWindowOld(w, id) }
        return w.hasButton(.close) || w.hasButton(.fullscreen) || w.hasButton(.zoom) || w.hasButton(.minimize)
            || w.isFocused() == true || w.isMain() == true || w.isAppFocusedWindow() || w.subrole() == standard
    }

    static func isWindowOld(_ w: WindowAttributeReader, _ id: String) -> Bool {
        let subrole = w.subrole()
        let title = w.title() ?? ""
        if !w.hasButton(.close) && !w.hasButton(.fullscreen) && !w.hasButton(.zoom) && !w.hasButton(.minimize)
            && w.isFocused() == false && w.isMain() == false && !w.isAppFocusedWindow()
            && subrole != standard && (title.isEmpty || title == "Window") {
            return false
        }
        return subrole == standard || subrole == "AXDialog" || subrole == "AXFloatingWindow" || (id == "com.apple.finder" && subrole == "Quick Look")
    }

    static func isDialog(_ w: WindowAttributeReader, _ id: String, _ level: Int?) -> Bool {
        if id == "com.1password.1password", let level, level != 0 { return true }
        if id == "com.apple.iphonesimulator" { return true }
        if w.subrole() != standard && id != "org.qutebrowser.qutebrowser" { return true }
        if firefoxFamily.contains(id) && w.isButtonEnabled(.minimize) != true { return true }
        if id == "com.apple.PhotoBooth" { return true }
        if id == "com.mitchellh.ghostty" { return w.isButtonEnabled(.fullscreen) != true && w.isButtonEnabled(.close) == true }
        if w.isButtonEnabled(.fullscreen) != true && !fullscreenButtonOptional.contains(id) { return true }
        return false
    }
}
