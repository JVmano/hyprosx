import Testing
@testable import HyprCore

private func cmd(_ d: String, _ a: String = "") -> Command? { try? CommandParser.parse(dispatcher: d, arguments: a).get() }

@Suite struct CommandTests {
    @Test(arguments: [
        ("3", WorkspaceSelector.id(3)), ("+1", .relative(1)), ("-2", .relative(-2)),
        ("m+1", .onMonitor(1, includeEmpty: false)), ("r-1", .onMonitor(-1, includeEmpty: true)),
        ("m~3", .onMonitorAbsolute(3, includeEmpty: false)), ("e+1", .existing(1)), ("e~2", .existingAbsolute(2)),
        ("name:web", .name("web")), ("previous", .previous), ("previous_per_monitor", .previousPerMonitor),
        ("empty", .empty(currentMonitorOnly: false, next: false)), ("emptynm", .empty(currentMonitorOnly: true, next: true)),
        ("special", .special(nil)), ("special:magic", .special("magic")),
    ])
    func workspaceSelectors(_ raw: String, _ expected: WorkspaceSelector) { #expect(WorkspaceSelector.parse(raw) == expected) }

    @Test func badWorkspaceSelector() { #expect(WorkspaceSelector.parse("x+") == nil) }

    @Test(arguments: [
        ("", WindowSelector.active), ("activewindow", .active), ("class:kitty", .classRegex("kitty")), ("kitty", .classRegex("kitty")),
        ("title:^(Mail)$", .title("^(Mail)$")), ("pid:42", .pid(42)), ("address:0x1a", .address(26)), ("floating", .floating),
        ("initialclass:x", .initialClass("x")), ("initialtitle:y", .initialTitle("y")), ("tag:t", .tag("t")),
    ])
    func windowSelectors(_ raw: String, _ expected: WindowSelector) { #expect(WindowSelector.parse(raw) == expected) }

    @Test(arguments: [("l", MonitorSelector.direction(.left)), ("right", .direction(.right)), ("current", .current),
                      ("+1", .relative(1)), ("0", .id(0)), ("desc:PHL", .name("desc:PHL")), ("Built-in Retina Display", .name("Built-in Retina Display"))])
    func monitorSelectors(_ raw: String, _ expected: MonitorSelector) { #expect(MonitorSelector.parse(raw) == expected) }

    @Test func resizeParams() {
        #expect(ResizeParam.parse("-50 0") == .relative(.pixels(-50), .pixels(0)))
        #expect(ResizeParam.parse("exact 33% 100%") == .exact(.percent(33), .percent(100)))
        #expect(ResizeParam.parse("10") == nil)
    }

    @Test func floatValues() {
        #expect(FloatValue.parse("exact 0.5") == .exact(0.5))
        #expect(FloatValue.parse("+0.1") == .relative(0.1))
        #expect(FloatValue.parse("-0.1") == .relative(-0.1))
    }

    @Test func execWithRules() {
        #expect(cmd("exec", "[workspace 2 silent; float] kitty --single") == .exec("kitty --single", rules: "workspace 2 silent; float", raw: false))
        #expect(cmd("execr", "open -na Ghostty") == .exec("open -na Ghostty", rules: nil, raw: true))
    }

    @Test func workspaceDispatchers() {
        #expect(cmd("workspace", "2") == .workspace(.id(2)))
        #expect(cmd("movetoworkspace", "special:magic") == .moveToWorkspace(.special("magic"), .active, silent: false))
        #expect(cmd("movetoworkspacesilent", "3,class:kitty") == .moveToWorkspace(.id(3), .classRegex("kitty"), silent: true))
        #expect(cmd("togglespecialworkspace") == .toggleSpecialWorkspace(nil))
        #expect(cmd("renameworkspace", "2 work") == .renameWorkspace(2, "work"))
    }

    @Test func windowDispatchers() {
        #expect(cmd("togglefloating") == .floating(.toggle, .active))
        #expect(cmd("settiled", "class:x") == .floating(.unset, .classRegex("x")))
        #expect(cmd("fullscreen") == .fullscreen(mode: 0, .toggle))
        #expect(cmd("fullscreen", "1 set") == .fullscreen(mode: 1, .set))
        #expect(cmd("fullscreenstate", "2 2") == .fullscreen(mode: 0, .toggle))
        #expect(cmd("movefocus", "l") == .moveFocus(.left))
        #expect(cmd("movewindow", "mon:+1 silent") == .moveWindow(.monitor(.relative(1)), silent: true))
        #expect(cmd("movewindow", "u") == .moveWindow(.direction(.up), silent: false))
        #expect(cmd("swapwindow", "r") == .swapWindow(.direction(.right)))
        #expect(cmd("resizeactive", "50 0") == .resizeActive(.relative(.pixels(50), .pixels(0))))
        #expect(cmd("resizewindowpixel", "100 100,class:kitty") == .resizeWindow(.relative(.pixels(100), .pixels(100)), .classRegex("kitty")))
        #expect(cmd("killactive") == .killActive(force: false))
        #expect(cmd("killwindow", "pid:9") == .closeWindow(.pid(9), force: true))
        #expect(cmd("signalwindow", "class:x,9") == .signal(9, .classRegex("x")))
    }

    @Test func cycleAndLayout() {
        var o = CycleOptions(); o.previous = true; o.tiledOnly = true
        #expect(cmd("cyclenext", "prev tiled") == .cycleNext(o))
        #expect(cmd("layoutmsg", "togglesplit") == .layoutMessage("togglesplit"))
        #expect(cmd("splitratio", "0.1") == .layoutMessage("splitratio 0.1"))
        #expect(cmd("workspacelayout", "dwindle monocle") == .workspaceLayout(["dwindle", "monocle"]))
        #expect(cmd("bringactivetotop") == .alterZOrder(top: true))
    }

    @Test func hostileInputIsRejectedNotTrapped() {
        #expect(WorkspaceSelector.parse("m--9223372036854775808") == nil)
        #expect(WorkspaceSelector.parse("e--9223372036854775808") == nil)
        #expect(WorkspaceSelector.parse("m+-1") == nil)
        #expect(ResizeParam.parse("nan 0") == nil)
        #expect(ResizeParam.parse("exact 1e400 10%") == nil)
        #expect(FloatValue.parse("inf") == nil)
        #expect(FloatValue.parse("exact nan") == nil)
        #expect(cmd("movecursor", "nan 1") == nil)
        #expect(cmd("movecursor", "10 20") == .moveCursor(10, 20))
    }

    @Test func parsedIntegersAreBounded() {
        for raw in ["9223372036854775807", "+9223372036854775807", "r+9223372036854775807", "e+9223372036854775807",
                    "m-9223372036854775807", "e~9223372036854775807", "2147483648", "+2147483648"] {
            #expect(WorkspaceSelector.parse(raw) == nil)
        }
        #expect(WorkspaceSelector.parse("2147483647") == .id(2147483647))
        #expect(WorkspaceSelector.parse("-2147483647") == .relative(-2147483647))
        #expect(WorkspaceSelector.parse("r+2147483647") == .onMonitor(2147483647, includeEmpty: true))
        #expect(MonitorSelector.parse("+9223372036854775807") == nil)
        #expect(MonitorSelector.parse("2147483648") == nil)
        #expect(MonitorSelector.parse("-99999999999999999999") == nil)
        #expect(MonitorSelector.parse("DP-1") == .name("DP-1"))
        #expect(MonitorSelector.parse("2147483647") == .id(2147483647))
        #expect(cmd("workspace", "+9223372036854775807") == nil)
        #expect(cmd("focusmonitor", "+9223372036854775807") == nil)
        #expect(cmd("renameworkspace", "9223372036854775807 x") == nil)
        #expect(cmd("movecursortocorner", "9223372036854775807") == nil)
    }

    @Test func alterZOrderRejectsAWindowPart() {
        #expect(cmd("alterzorder", "top") == .alterZOrder(top: true))
        #expect(cmd("alterzorder", "bottom") == .alterZOrder(top: false))
        #expect(CommandParser.parse(dispatcher: "alterzorder", arguments: "top,class:kitty") == .failure(CommandError("Invalid argument for alterzorder: top,class:kitty")))
        #expect(cmd("alterzorder", "bottom,pid:9") == nil)
    }

    @Test func malformedFullscreenAndCenterArgumentsAreErrors() {
        #expect(CommandParser.parse(dispatcher: "fullscreen", arguments: "set") == .failure(CommandError("Invalid argument for fullscreen: set")))
        #expect(CommandParser.parse(dispatcher: "fullscreen", arguments: "banana") == .failure(CommandError("Invalid argument for fullscreen: banana")))
        #expect(cmd("fullscreen", "1 banana") == nil)
        #expect(cmd("fullscreen", "1 set extra") == nil)
        #expect(cmd("fullscreen", "2") == nil)
        #expect(cmd("fullscreen", "0") == .fullscreen(mode: 0, .toggle))
        #expect(CommandParser.parse(dispatcher: "fullscreenstate", arguments: "1 1 banana") == .failure(CommandError("Invalid argument for fullscreenstate: 1 1 banana")))
        #expect(cmd("fullscreenstate", "1 1 set") == .fullscreen(mode: 1, .set))
        #expect(cmd("fullscreenstate", "0 0") == .fullscreen(mode: 0, .unset))
        #expect(cmd("centerwindow") == .centerWindow)
        #expect(cmd("centerwindow", "1") == .centerWindow)
        #expect(CommandParser.parse(dispatcher: "centerwindow", arguments: "banana") == .failure(CommandError("Invalid argument for centerwindow: banana")))
        #expect(cmd("centerwindow", "2") == nil)
    }

    @Test func unsupportedKeepsInjectionDispatchersOut() {
        #expect(cmd("pass", "class:kitty") == .unsupported("pass"))
        #expect(cmd("sendkeystate", "SUPER, A, down, class:x") == .unsupported("sendkeystate"))
        #expect(cmd("SENDSHORTCUT", "SUPER, F4") == .unsupported("sendshortcut"))
        #expect(cmd("EXEC", " ls ") == .exec("ls", rules: nil, raw: false))
    }

    @Test func unsupportedAndUnknown() {
        #expect(cmd("sendshortcut", "SUPER, F4") == .unsupported("sendshortcut"))
        #expect(cmd("togglegroup") == .unsupported("togglegroup"))
        #expect(CommandParser.parse(dispatcher: "nope", arguments: "") == .failure(CommandError("Invalid dispatcher nope")))
        #expect(CommandParser.parse(dispatcher: "movefocus", arguments: "x") == .failure(CommandError("Invalid argument for movefocus: x")))
    }
}
