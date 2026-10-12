import Testing
@testable import HyprCore

let laptop = MonitorInfo(id: 0, name: "Built-in Retina Display", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
                         visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950))

func makeConfig(_ text: String = "") -> Config {
    let parser = HyprlangParser(environment: [:], readFile: { _ in nil }, glob: { _ in [] })
    let base = "general {\n gaps_in = 0\n gaps_out = 0\n border_size = 0\n}\n"
    return ConfigBuilder.build(parser.parse(text: base + text, path: "/t.conf").entries).config
}

func snap(_ id: WindowID, app: String = "Ghostty", bundle: String = "com.mitchellh.ghostty", pid: Int32 = 100,
          frame: Rect = Rect(x: 100, y: 100, width: 600, height: 400), kind: WindowKind = .normal, title: String = "t") -> WindowSnapshot {
    WindowSnapshot(id: id, pid: pid, bundleID: bundle, appName: app, title: title, frame: frame, kind: kind)
}

func frames(_ effects: [Effect]) -> [WindowID: Rect] {
    var out: [WindowID: Rect] = [:]
    for case .setFrames(let changes) in effects { for c in changes { out[c.id] = c.frame } }
    return out
}

func parks(_ effects: [Effect]) -> [WindowID: Point] {
    var out: [WindowID: Point] = [:]
    for case .park(let p) in effects { for r in p { out[r.id] = r.origin } }
    return out
}

func world(_ text: String = "", monitors: [MonitorInfo] = [laptop]) -> World {
    let w = World(config: makeConfig(text))
    _ = w.handle(.monitorsChanged(monitors))
    return w
}

@Suite struct WorldCoreTests {
    @Test func monitorGetsWorkspaceOne() {
        let w = world()
        #expect(w.activeWorkspace[0] == 1)
        #expect(w.workspaces[1]?.monitor == 0)
    }

    @Test func firstWindowFillsTheVisibleFrameAndGetsFocus() {
        let w = world()
        let e = w.handle(.windowAppeared(snap(1)))
        #expect(frames(e) == [1: Rect(x: 0, y: 32, width: 1512, height: 950)])
        #expect(e.contains(.focus(1)))
        #expect(w.focusedWindow == 1)
    }

    @Test func secondWindowSplitsAndOnlyChangedFramesAreSent() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2)))
        #expect(frames(e) == [1: Rect(x: 0, y: 32, width: 756, height: 950), 2: Rect(x: 756, y: 32, width: 756, height: 950)])
        let again = w.handle(.monitorsChanged([laptop]))
        #expect(frames(again).isEmpty)
    }

    @Test func gapsBordersAndReservedArea() {
        let w = world("general:gaps_in = 4\ngeneral:gaps_out = 10\ngeneral:border_size = 2\nmonitor = , addreserved, 20, 0, 0, 0")
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2)))
        #expect(frames(e)[1] == Rect(x: 12, y: 64, width: 738, height: 906))
        #expect(frames(e)[2] == Rect(x: 762, y: 64, width: 738, height: 906))
    }

    @Test func floatRuleKeepsAppFrameWithoutWrites() {
        let w = world("windowrule = float on, match:class Calculator")
        let e = w.handle(.windowAppeared(snap(1, app: "Calculator", bundle: "com.apple.calculator")))
        #expect(frames(e).isEmpty)
        #expect(w.windows[1]?.isFloating == true)
    }

    @Test func dialogsFloatByDefault() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1, kind: .dialog)))
        #expect(w.windows[1]?.isFloating == true)
    }

    @Test func floatByDefaultPolicyWithTileAllowList() {
        let w = world("windowrule = float on, match:class .*\nwindowrule = tile on, match:class Ghostty, match:modal false")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, app: "Mail", bundle: "com.apple.mail")))
        _ = w.handle(.windowAppeared(snap(3, kind: .dialog)))
        #expect(w.windows[1]?.isFloating == false)
        #expect(w.windows[2]?.isFloating == true)
        #expect(w.windows[3]?.isFloating == true)
    }

    @Test func ignoreRuleLeavesWindowUnmanaged() {
        let w = world("windowrule = ignore on, match:class Raycast")
        let e = w.handle(.windowAppeared(snap(1, app: "Raycast", bundle: "com.raycast.macos")))
        #expect(e.isEmpty)
        #expect(w.windows[1] == nil)
    }

    @Test func appWithoutBundleIdIsManagedByName() {
        let w = world("windowrule = float on, match:class Minecraft")
        _ = w.handle(.windowAppeared(snap(1, app: "Minecraft", bundle: "")))
        #expect(w.windows[1]?.isFloating == true)
    }

    @Test func silentRuleWorkspaceParksWindowAndKeepsFocus() {
        let w = world("windowrule = workspace 3 silent, match:class Slack")
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", pid: 200)))
        #expect(w.windows[2]?.workspace == 3)
        #expect(parks(e)[2] == Point(x: 1511, y: 981))
        #expect(e.contains(.focus(1)))
        #expect(w.focusedWindow == 1)
    }

    @Test func closingFocusedWindowFocusesNeighbourAndRetiles() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2)))
        let e = w.handle(.windowDisappeared(2))
        #expect(frames(e) == [1: Rect(x: 0, y: 32, width: 1512, height: 950)])
        #expect(e.contains(.focus(1)))
    }

    @Test func parkingCornerAndZoom() {
        #expect(Parking.origin(windowSize: Size(width: 500, height: 400), monitor: laptop, among: [laptop], bundleID: "x") == Point(x: 1511, y: 981))
        #expect(Parking.origin(windowSize: Size(width: 500, height: 400), monitor: laptop, among: [laptop], bundleID: "us.zoom.xos") == Point(x: 1512, y: 982))
        let right = MonitorInfo(id: 1, name: "PHL", frame: Rect(x: 1512, y: 0, width: 5120, height: 1440), visibleFrame: Rect(x: 1512, y: 0, width: 5120, height: 1440))
        #expect(Parking.usesBottomLeft(laptop, among: [laptop, right]))
    }
}

let phl = MonitorInfo(id: 1, name: "PHL", frame: Rect(x: 1512, y: 0, width: 5120, height: 1440),
                      visibleFrame: Rect(x: 1512, y: 0, width: 5120, height: 1440))

func allBounded(_ effects: [Effect], limit: Double = 1_000_000) -> Bool {
    var ok = true
    for case .setFrames(let list) in effects {
        for c in list {
            let f = c.frame
            for v in [f.x, f.y, f.width, f.height] where !(v.isFinite && abs(v) <= limit) { ok = false }
        }
    }
    for case .park(let list) in effects {
        for r in list where !(r.origin.x.isFinite && r.origin.y.isFinite && abs(r.origin.x) <= limit && abs(r.origin.y) <= limit) { ok = false }
    }
    return ok
}

@Suite struct WorldCoreExtraTests {
    @Test func extremeConfigValuesNeverTrapOrEscapeTheScreen() {
        let w = world("""
        general:gaps_in = 1e300
        general:gaps_out = 1e300
        general:border_size = 9000000000000000000
        dwindle:special_scale_factor = 1e300
        master:special_scale_factor = -1e300
        monitor = , addreserved, 1e300, 0, 0, 0
        windowrule = float on, size 99999999999999999999999 99999999999999999999999, move 99999999999999999999999 -99999999999999999999999, match:class Calc
        windowrule = workspace 99999999999999999999, match:class Slack
        windowrule = workspace special:big, match:class Big
        """)
        var all: [Effect] = []
        all += w.handle(.windowAppeared(snap(1)))
        all += w.handle(.windowAppeared(snap(2)))
        all += w.handle(.windowAppeared(snap(3, app: "Calc", bundle: "com.apple.calculator")))
        all += w.handle(.windowAppeared(snap(4, app: "Slack", bundle: "com.tinyspeck.slackmacgap")))
        all += w.handle(.windowAppeared(snap(5, app: "Big", bundle: "x.big")))
        all += w.handle(.monitorsChanged([laptop, phl]))
        #expect(allBounded(all))
        #expect(w.windows[4]?.workspace == 1)
        #expect(w.windows[5]?.workspace == -98)
    }

    @Test func extremeWorkspaceRuleValuesStayBounded() {
        let w = world("workspace = 1, gapsin:2147483647, gapsout:2147483647, bordersize:2147483647")
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2)))
        #expect(allBounded(e))
    }

    @Test func spawnRulesRegisteredForAPidApplyToItsWindow() {
        let w = world()
        w.spawnRules[7] = "float; workspace 2 silent"
        w.registerSpawn(token: 7, pid: 555)
        _ = w.handle(.windowAppeared(snap(9, app: "kitty", bundle: "net.kovidgoyal.kitty", pid: 555)))
        #expect(w.windows[9]?.isFloating == true)
        #expect(w.windows[9]?.workspace == 2)
        #expect(w.pidRules[555] == nil)
    }

    @Test func secondMonitorGetsItsOwnWorkspaceAndWindowsFollowTheMonitor() {
        let w = world("windowrule = workspace 2, match:class Term", monitors: [laptop, phl])
        #expect(w.activeWorkspace == [0: 1, 1: 2])
        _ = w.handle(.windowAppeared(snap(1)))
        let open = w.handle(.windowAppeared(snap(2, app: "Term", bundle: "x.term")))
        #expect(frames(open)[2] == Rect(x: 1512, y: 0, width: 5120, height: 1440))
        #expect(w.focusedMonitor == 1)
        let unplug = w.handle(.monitorsChanged([laptop]))
        #expect(w.activeWorkspace == [0: 1])
        #expect(w.workspaces[2]?.monitor == 0)
        #expect(w.focusedMonitor == 0)
        #expect(parks(unplug)[2] == Point(x: 1511, y: 981))
        let replug = w.handle(.monitorsChanged([laptop, phl]))
        #expect(w.activeWorkspace == [0: 1, 1: 2])
        #expect(frames(replug)[2] == Rect(x: 1512, y: 0, width: 5120, height: 1440))
        #expect(w.windows[2]?.isParked == false)
    }

    @Test func hiddenWindowsParkAgainWhenTheMonitorLayoutChanges() {
        let w = world("windowrule = workspace 3 silent, match:class Slack")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", pid: 200)))
        #expect(parks(w.handle(.monitorsChanged([laptop]))).isEmpty)
        let e = w.handle(.monitorsChanged([laptop, phl]))
        #expect(parks(e)[2] == Point(x: -599, y: 981))
        #expect(w.activeWorkspace == [0: 1, 1: 2])
    }

    @Test func workspaceRuleDefaultBindsAWorkspaceToItsMonitor() {
        let w = world("workspace = 5, monitor:Built-in Retina Display, default:true")
        #expect(w.activeWorkspace[0] == 5)
        #expect(w.workspaces[5]?.homeMonitorName == "Built-in Retina Display")
    }

    @Test func closingTheLastWindowOfAHiddenWorkspaceDestroysIt() {
        let w = world("windowrule = workspace 3 silent, match:class Slack")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, app: "Slack", bundle: "com.tinyspeck.slackmacgap", pid: 200)))
        #expect(w.workspaces[3] != nil)
        _ = w.handle(.windowDisappeared(2))
        #expect(w.workspaces[3] == nil)
        #expect(w.workspaces[1] != nil)
    }

    @Test func focusOnCloseFollowsTheConfiguredMode() {
        func scenario(_ mode: Int, cursor: Point) -> WindowID? {
            let w = world("input:focus_on_close = \(mode)")
            _ = w.handle(.windowAppeared(snap(1)))
            _ = w.handle(.windowAppeared(snap(2)))
            _ = w.handle(.windowAppeared(snap(3)))
            w.focusWindow(1, warp: false, emitEffect: false)
            w.focusWindow(3, warp: false, emitEffect: false)
            w.cursor = cursor
            _ = w.handle(.windowDisappeared(3))
            return w.focusedWindow
        }
        #expect(scenario(0, cursor: Point(x: 1e9, y: 1e9)) == 2)
        #expect(scenario(1, cursor: Point(x: 100, y: 500)) == 1)
        #expect(scenario(2, cursor: Point(x: 1e9, y: 1e9)) == 1)
    }

    @Test func suspendedWindowsNeverGetFrames() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2)))
        w.windows[2]?.suspended = .minimized
        let targets = w.targetFrames(w.workspaces[1]!)
        #expect(targets[1] != nil)
        #expect(targets[2] == nil)
    }

    @Test func specialWorkspaceUsesBareNameScaleAndRuleGaps() {
        let w = world("""
        dwindle:special_scale_factor = 0.5
        workspace = special:magic, gapsout:100
        windowrule = workspace special:magic, match:class Term
        windowrule = workspace special:other, match:class Notes
        """)
        let e = w.handle(.windowAppeared(snap(1, app: "Term", bundle: "x.term")))
        #expect(w.windows[1]?.workspace == -98)
        #expect(w.workspaces[-98]?.name == "magic")
        #expect(w.activeSpecial == [0: -98])
        #expect(frames(e)[1] == Rect(x: 428, y: 320, width: 656, height: 375))
        _ = w.handle(.windowAppeared(snap(2, app: "Notes", bundle: "x.notes")))
        #expect(w.windows[2]?.workspace == -97)
        #expect(w.activeSpecial == [0: -97])
    }

    @Test func unnamedSpecialWorkspaceIsMinus99() {
        let w = world("windowrule = workspace special, match:class Term")
        _ = w.handle(.windowAppeared(snap(1, app: "Term", bundle: "x.term")))
        #expect(w.windows[1]?.workspace == -99)
        #expect(w.workspaces[-99]?.name == "special")
    }

    @Test func takeEffectsKeepsTheLastFramePerWindowAndOrdersTheBatch() {
        let w = world()
        let a = FrameChange(id: 1, frame: Rect(x: 0, y: 0, width: 10, height: 10), reason: .layout)
        let b = FrameChange(id: 1, frame: Rect(x: 5, y: 5, width: 10, height: 10), reason: .open)
        let c = FrameChange(id: 2, frame: Rect(x: 1, y: 1, width: 10, height: 10), reason: .layout)
        _ = w.takeEffects()
        w.emit(.focus(9))
        w.emit(.setFrames([a, c]))
        w.emit(.statusChanged)
        w.emit(.park([ParkRequest(id: 2, origin: Point(x: 7, y: 7))]))
        w.emit(.setFrames([b]))
        w.emit(.saveState)
        w.emit(.statusChanged)
        #expect(w.takeEffects() == [.setFrames([b]), .park([ParkRequest(id: 2, origin: Point(x: 7, y: 7))]), .focus(9), .statusChanged, .saveState])
        #expect(w.takeEffects().isEmpty)
    }

    @Test func focusWarpsTheCursorUnlessDisabledOrInside() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        w.cursor = Point(x: 5, y: 5)
        w.focusWindow(1, warp: true, emitEffect: false)
        #expect(w.takeEffects().contains(.warpCursor(Point(x: 756, y: 507))))
        w.focusWindow(1, warp: true, emitEffect: false)
        #expect(!w.takeEffects().contains { if case .warpCursor = $0 { return true } else { return false } })
        let quiet = world("cursor:no_warps = true")
        _ = quiet.handle(.windowAppeared(snap(1)))
        quiet.cursor = Point(x: 5, y: 5)
        quiet.focusWindow(1, warp: true, emitEffect: false)
        #expect(!quiet.takeEffects().contains { if case .warpCursor = $0 { return true } else { return false } })
    }

    @Test func reloadRefreshesFramesWithTheNewConfig() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.reload(makeConfig("general:gaps_out = 10"))
        #expect(frames(e) == [1: Rect(x: 10, y: 42, width: 1492, height: 930)])
        #expect(e.contains(.statusChanged))
    }

    @Test func fullscreenAndMaximizeRulesUseTheirAreas() {
        let text = "general:gaps_out = 10\ngeneral:border_size = 2\nmonitor = , addreserved, 20, 0, 0, 0\n"
        let full = world(text + "windowrule = fullscreen on, match:class Game")
        let e = full.handle(.windowAppeared(snap(1, app: "Game", bundle: "x.game")))
        #expect(frames(e)[1] == Rect(x: 0, y: 52, width: 1512, height: 930))
        #expect(full.windows[1]?.fullscreenMode == 0)
        let max = world(text + "windowrule = maximize on, match:class Game")
        _ = max.handle(.windowAppeared(snap(1)))
        let m = max.handle(.windowAppeared(snap(2, app: "Game", bundle: "x.game")))
        #expect(frames(m)[2] == Rect(x: 12, y: 64, width: 1488, height: 906))
        #expect(max.windows[1]?.fullscreenMode == nil)
    }

    @Test func workspaceRuleCanRemoveTheBorder() {
        let w = world("general:border_size = 4\nworkspace = 1, border:false")
        let e = w.handle(.windowAppeared(snap(1)))
        #expect(frames(e)[1] == Rect(x: 0, y: 32, width: 1512, height: 950))
    }

    @Test func startupPlacesWindowsOnTheMonitorUnderTheirCenter() {
        let w = world(monitors: [laptop, phl])
        w.isStartingUp = true
        _ = w.handle(.windowAppeared(snap(1, frame: Rect(x: 1600, y: 100, width: 500, height: 400))))
        #expect(w.windows[1]?.workspace == 2)
        #expect(w.focusedMonitor == 1)
    }

    @Test func floatingRulesSizeCenterAndMove() {
        let w = world("""
        windowrule = float on, size 400 300, center on, match:class Calc
        windowrule = float on, move 10 20, match:class Move
        """)
        let e = w.handle(.windowAppeared(snap(1, app: "Calc", bundle: "x.calc")))
        #expect(frames(e)[1] == Rect(x: 556, y: 357, width: 400, height: 300))
        let m = w.handle(.windowAppeared(snap(2, app: "Move", bundle: "x.move")))
        #expect(frames(m)[2] == Rect(x: 10, y: 20, width: 600, height: 400))
    }

    @Test func pseudoRuleKeepsTheAppSizeCenteredInItsTile() {
        let w = world("windowrule = pseudo on, match:class Ghostty")
        let e = w.handle(.windowAppeared(snap(1)))
        #expect(frames(e)[1] == Rect(x: 456, y: 307, width: 600, height: 400))
    }

    @Test func ignoredIdsAreForgottenWhenTheWindowDisappears() {
        let w = world("windowrule = ignore on, match:class Raycast")
        _ = w.handle(.windowAppeared(snap(1, app: "Raycast", bundle: "com.raycast.macos")))
        #expect(w.ignored.contains(1))
        _ = w.handle(.windowDisappeared(1))
        #expect(!w.ignored.contains(1))
    }

    @Test func namedSpecialWorkspaceIdsAreReusedAfterTheyEmpty() {
        let w = world("""
        windowrule = workspace special:magic silent, match:class Term
        windowrule = workspace special:other silent, match:class Notes
        """)
        for i in 1...100 {
            let id = WindowID(i)
            _ = w.handle(.windowAppeared(snap(id, app: "Term", bundle: "x.term")))
            #expect(w.windows[id]?.workspace == -98)
            _ = w.handle(.windowDisappeared(id))
            #expect(w.workspaces[-98] == nil)
        }
        _ = w.handle(.windowAppeared(snap(200, app: "Term", bundle: "x.term")))
        _ = w.handle(.windowAppeared(snap(201, app: "Notes", bundle: "x.notes")))
        #expect(w.windows[200]?.workspace == -98)
        #expect(w.windows[201]?.workspace == -97)
        _ = w.handle(.windowDisappeared(200))
        _ = w.handle(.windowAppeared(snap(202, app: "Term", bundle: "x.term")))
        #expect(w.windows[202]?.workspace == -98)
        #expect(w.workspaces[-97]?.name == "other")
    }

    @Test func namedWorkspaceIdsSkipIdsAlreadyInUse() {
        let w = world("""
        windowrule = workspace 1000000, match:class A
        windowrule = workspace name:web, match:class B
        """)
        _ = w.handle(.windowAppeared(snap(1, app: "A", bundle: "x.a")))
        _ = w.handle(.windowAppeared(snap(2, app: "B", bundle: "x.b")))
        #expect(w.windows[1]?.workspace == 1_000_000)
        #expect(w.windows[2]?.workspace == 1_000_001)
        #expect(w.workspaces[1_000_000]?.name == "1000000")
        #expect(w.workspaces[1_000_001]?.name == "web")
    }

    @Test func noInitialFocusHandsFocusBackToThePreviousWindow() {
        let w = world("windowrule = no_initial_focus on, match:class Quiet")
        let first = w.handle(.windowAppeared(snap(1, app: "Quiet", bundle: "x.quiet")))
        #expect(w.focusedWindow == nil)
        #expect(!first.contains { if case .focus = $0 { return true } else { return false } })
        _ = w.handle(.windowAppeared(snap(2)))
        let e = w.handle(.windowAppeared(snap(3, app: "Quiet", bundle: "x.quiet")))
        #expect(w.focusedWindow == 2)
        #expect(e.contains(.focus(2)))
        #expect(!e.contains(.focus(3)))
    }
}
