import Testing
@testable import HyprCore

struct FakeWindow: WindowAttributeReader {
    var sub: String? = "AXStandardWindow"
    var name: String? = "Doc"
    var ident: String?
    var buttons: [WindowButton: Bool?] = [.close: true, .fullscreen: true, .zoom: true, .minimize: true]
    var focused: Bool? = false
    var main: Bool? = false
    var appFocused = false
    func subrole() -> String? { sub }
    func title() -> String? { name }
    func identifier() -> String? { ident }
    func hasButton(_ b: WindowButton) -> Bool { buttons[b] != nil }
    func isButtonEnabled(_ b: WindowButton) -> Bool? { buttons[b] ?? nil }
    func isFocused() -> Bool? { focused }
    func isMain() -> Bool? { main }
    func isAppFocusedWindow() -> Bool { appFocused }
}

@Suite struct WindowClassifierTests {
    func classify(_ w: FakeWindow, _ bundle: String? = "com.example.app", accessory: Bool = false, level: Int? = 0) -> WindowClassification {
        WindowClassifier.classify(w, bundleID: bundle, isAccessoryApp: accessory, windowLevel: level)
    }

    @Test func standardWindowIsNormal() { #expect(classify(FakeWindow()) == .normal) }

    @Test func dialogSubroleIsDialog() { #expect(classify(FakeWindow(sub: "AXDialog")) == .dialog) }

    @Test func buttonlessUnknownPopupIsNotAWindow() {
        #expect(classify(FakeWindow(sub: "AXUnknown", name: "", buttons: [:])) == .notAWindow)
    }

    @Test func ghosttyQuickTerminalAndSettings() {
        #expect(classify(FakeWindow(ident: "com.mitchellh.ghostty.quickTerminal"), "com.mitchellh.ghostty") == .notAWindow)
        let settings = FakeWindow(buttons: [.close: true, .fullscreen: false, .zoom: true, .minimize: true])
        #expect(classify(settings, "com.mitchellh.ghostty") == .dialog)
        #expect(classify(FakeWindow(), "com.mitchellh.ghostty") == .normal)
    }

    @Test func disabledFullscreenButtonFloatsExceptKnownApps() {
        let noFullscreen = FakeWindow(buttons: [.close: true, .fullscreen: false, .zoom: true, .minimize: true])
        #expect(classify(noFullscreen, "com.apple.calculator") == .dialog)
        #expect(classify(noFullscreen, "net.kovidgoyal.kitty") == .normal)
    }

    @Test func firefoxFamilyPictureInPictureFloats() {
        let pip = FakeWindow(buttons: [.close: true, .fullscreen: true, .zoom: true])
        #expect(classify(pip, "app.zen-browser.zen") == .dialog)
        #expect(classify(FakeWindow(), "app.zen-browser.zen") == .normal)
    }

    @Test func levelSensitiveAppsAndAccessoryApps() {
        #expect(classify(FakeWindow(), "com.tinyspeck.slackmacgap", level: 3) == .notAWindow)
        #expect(classify(FakeWindow(), "com.tinyspeck.slackmacgap", level: nil) == .normal)
        #expect(classify(FakeWindow(buttons: [.fullscreen: true]), accessory: true) == .notAWindow)
    }
}
