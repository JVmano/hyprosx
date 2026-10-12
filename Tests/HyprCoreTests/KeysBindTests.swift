import Testing
@testable import HyprCore

private let here = SourceLocation(file: "/cfg/hyprland.conf", line: 7)

@Suite struct KeysBindTests {
    @Test(arguments: [
        ("SUPER", Modifiers.command), ("ALT SHIFT", [.option, .shift]), ("SUPER_SHIFT", [.command, .shift]),
        ("SUPERSHIFT", [.command, .shift]), ("CTRL + ALT", [.control, .option]), ("super and shift", [.command, .shift]),
        ("CMD", Modifiers.command), ("OPTION", Modifiers.option), ("", []), ("FN", Modifiers.function),
    ] as [(String, Modifiers)])
    func modifiers(_ raw: String, _ expected: Modifiers) { #expect(Modifiers.parse(raw) == expected) }

    @Test func unsupportedModifiersAreNil() {
        #expect(Modifiers.parse("MOD2") == nil)
        #expect(Modifiers.parse("HYPER") == nil)
    }

    @Test(arguments: [("h", 0x04), ("H", 0x04), ("Return", 0x24), ("enter", 0x24), ("bracketleft", 0x21),
                      ("semicolon", 0x29), ("1", 0x12), ("0", 0x1D), ("Left", 0x7B), ("F12", 0x6F), ("space", 0x31)])
    func keysyms(_ name: String, _ code: Int) { #expect(Keysym.keyCode(for: name) == UInt16(code)) }

    @Test func plainBind() {
        let r = BindParser.parse(keyword: "bind", value: "ALT, H, movefocus, l", submap: "", location: here)
        #expect(r.diagnostics.isEmpty)
        #expect(r.bind == Bind(modifiers: .option, trigger: .key(0x04), flags: [], dispatcher: "movefocus", arguments: "l",
                               description: nil, submap: "", location: here))
    }

    @Test func argumentsKeepTheirCommas() {
        let r = BindParser.parse(keyword: "bind", value: "ALT, Return, exec, notify-send \"a, b\"", submap: "", location: here)
        #expect(r.bind?.arguments == "notify-send \"a, b\"")
    }

    @Test func emptyModifiersAndEmptyArguments() {
        let r = BindParser.parse(keyword: "bind", value: ", Escape, submap, reset", submap: "resize", location: here)
        #expect(r.bind?.modifiers == [])
        #expect(r.bind?.submap == "resize")
        let k = BindParser.parse(keyword: "bind", value: "SUPER, C, killactive,", submap: "", location: here)
        #expect(k.bind?.arguments == "")
    }

    @Test func flagsAndDescription() {
        let r = BindParser.parse(keyword: "bindrd", value: "ALT, Q, Close it, killactive,", submap: "", location: here)
        #expect(r.bind?.flags == [.release, .description])
        #expect(r.bind?.description == "Close it")
        #expect(r.bind?.dispatcher == "killactive")
    }

    @Test func repeatBind() {
        #expect(BindParser.parse(keyword: "binde", value: ", H, resizeactive, -50 0", submap: "resize", location: here).bind?.flags == .repeating)
    }

    @Test func mouseBindHasNoArguments() {
        let r = BindParser.parse(keyword: "bindm", value: "CTRL ALT, mouse:272, movewindow", submap: "", location: here)
        #expect(r.bind?.trigger == .mouse(272))
        #expect(r.bind?.dispatcher == "movewindow")
        #expect(r.bind?.flags == .mouse)
    }

    @Test func scrollAndCodeTriggers() {
        #expect(BindParser.parseTrigger("mouse_down") == .scroll(.down))
        #expect(BindParser.parseTrigger("code:36") == .key(36))
        #expect(BindParser.parseTrigger("nope") == nil)
    }

    @Test func unsupportedFlagWarnsButLoads() {
        let r = BindParser.parse(keyword: "bindn", value: "ALT, X, exec, true", submap: "", location: here)
        #expect(r.bind != nil)
        #expect(r.diagnostics.first?.isWarning == true)
        #expect(r.diagnostics.first?.message == "bind flag 'n' is not supported on macOS; loaded as a plain bind")
    }

    @Test func catchallIsDroppedWithWarning() {
        let r = BindParser.parse(keyword: "bind", value: ", catchall, submap, reset", submap: "resize", location: here)
        #expect(r.bind == nil)
        #expect(r.diagnostics.map(\.message) == ["catchall binds are not supported on macOS"])
    }

    @Test func errors() {
        #expect(BindParser.parse(keyword: "bindz", value: "ALT, X, exec, a", submap: "", location: here).diagnostics.first?.message == "invalid bind flag 'z'")
        #expect(BindParser.parse(keyword: "bind", value: "ALT, nokey, exec, a", submap: "", location: here).diagnostics.first?.message == "invalid key 'nokey'")
        #expect(BindParser.parse(keyword: "bind", value: "MOD3, X, exec, a", submap: "", location: here).diagnostics.first?.message == "invalid modifiers 'MOD3'")
        #expect(BindParser.parse(keyword: "bind", value: "FN, X, exec, a", submap: "", location: here).diagnostics.first?.message == "FN works only with mouse and scroll binds")
        #expect(BindParser.parse(keyword: "bind", value: "ALT, X", submap: "", location: here).diagnostics.first?.message == "missing dispatcher")
    }

    @Test func unbind() {
        let u = BindParser.parseUnbind("SUPER, O")
        #expect(u?.0 == .command)
        #expect(u?.1 == .key(0x1F))
    }
}
