import Testing
@testable import HyprCore

func threeWindows(_ text: String = "") -> World {
    let w = world(text)
    for id: WindowID in 1...3 { _ = w.handle(.windowAppeared(snap(id, pid: Int32(id) * 100))) }
    return w
}

func ok(_ r: CommandResult) -> Bool { !r.isError }

@Suite struct WorldDispatchTests {
    @Test func moveFocusUsesEdgesAndHistory() {
        let w = threeWindows()
        #expect(w.run(.moveFocus(.up)).effects.contains(.focus(2)))
        #expect(w.run(.moveFocus(.left)).effects.contains(.focus(1)))
        #expect(w.run(.moveFocus(.right)).effects.contains(.focus(2)))
    }

    @Test func moveFocusFallsBackToMonitorThenWraps() {
        let two = world(monitors: [laptop, ultrawide])
        _ = two.handle(.windowAppeared(snap(1)))
        _ = two.run(.moveFocus(.right))
        #expect(two.focusedMonitor == 1)
        let single = world()
        _ = single.handle(.windowAppeared(snap(1)))
        _ = single.handle(.windowAppeared(snap(2, pid: 200)))
        _ = single.run(.focusWindow(.address(1)))
        #expect(single.run(.moveFocus(.left)).effects.contains(.focus(2)))
    }

    @Test func cycleNextAndPrevious() {
        let w = threeWindows()
        #expect(w.run(.cycleNext(CycleOptions())).effects.contains(.focus(1)))
        var prev = CycleOptions()
        prev.previous = true
        #expect(w.run(.cycleNext(prev)).effects.contains(.focus(3)))
    }

    @Test func toggleFloatingCentersAtSixtyPercent() {
        let w = threeWindows()
        let e = w.run(.floating(.toggle, .active)).effects
        #expect(frames(e)[3] == Rect(x: 302, y: 222, width: 907, height: 570))
        #expect(w.windows[3]?.isFloating == true)
        _ = w.run(.floating(.unset, .active))
        #expect(w.windows[3]?.isFloating == false)
    }

    @Test func fullscreenModes() {
        let w = world("general:gaps_out = 10")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        #expect(frames(w.run(.fullscreen(mode: 0, .toggle)).effects)[2] == Rect(x: 0, y: 32, width: 1512, height: 950))
        #expect(frames(w.run(.fullscreen(mode: 1, .set)).effects)[2] == Rect(x: 10, y: 42, width: 1492, height: 930))
        #expect(frames(w.run(.fullscreen(mode: 1, .toggle)).effects)[2] == Rect(x: 756, y: 42, width: 746, height: 930))
    }

    @Test func pinNeedsFloating() {
        let w = threeWindows()
        #expect(w.run(.pin(.active)).reply == "pin works only on floating windows")
        _ = w.run(.floating(.set, .active))
        #expect(ok(w.run(.pin(.active))))
        #expect(w.windows[3]?.isPinned == true)
    }

    @Test func moveWindowInLayoutToMonitorAndFloatingEdge() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        _ = w.run(.moveWindow(.direction(.left), silent: false))
        #expect(w.workspaces[1]?.tiledIDs == [2, 1])
        _ = w.run(.moveWindow(.monitor(.id(1)), silent: false))
        #expect(w.windows[2]?.workspace == w.activeWorkspace[1])
        #expect(w.focusedMonitor == 1)
        _ = w.run(.focusWindow(.address(1)))
        _ = w.run(.floating(.set, .active))
        _ = w.run(.moveWindow(.direction(.right), silent: false))
        #expect(w.windows[1]?.floatingFrame.maxX == 1512)
    }

    @Test func swapWindowAndSwapNext() {
        let w = threeWindows()
        _ = w.run(.swapWindow(.direction(.left)))
        #expect(w.workspaces[1]?.tiledIDs == [3, 2, 1])
        _ = w.run(.swapNext(previous: false))
        #expect(w.workspaces[1]?.tiledIDs == [2, 3, 1])
    }

    @Test func resizeTiledAndExactFloatingLikeRectangle() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        let resized = w.run(.resizeActive(.relative(.pixels(-100), .pixels(0)))).effects
        #expect(frames(resized)[1] == Rect(x: 0, y: 32, width: 656, height: 950))
        _ = w.run(.floating(.set, .active))
        _ = w.run(.resizeActive(.exact(.percent(33), .percent(100))))
        let placed = w.run(.moveActive(.exact(.percent(0), .percent(0)))).effects
        #expect(frames(placed)[2] == Rect(x: 0, y: 32, width: 499, height: 950))
        #expect(w.run(.moveActive(.relative(.pixels(1), .pixels(1)))).isError == false)
        _ = w.run(.floating(.unset, .active))
        #expect(w.run(.moveActive(.relative(.pixels(1), .pixels(1)))).reply == "moveactive works only on floating windows")
    }

    @Test func layoutMessagesAndWorkspaceLayout() {
        let w = threeWindows("dwindle:preserve_split = true")
        #expect(ok(w.run(.layoutMessage("togglesplit"))))
        #expect(w.run(.layoutMessage("bogus")).reply == "unknown dwindle layout message 'bogus'")
        #expect(ok(w.run(.workspaceLayout(["dwindle", "monocle"]))))
        #expect(w.workspaces[1]?.layout.kind == .monocle)
        let e = w.run(.workspaceLayout(["dwindle", "monocle"])).effects
        #expect(w.workspaces[1]?.layout.kind == .dwindle)
        #expect(!frames(e).isEmpty)
        _ = w.run(.workspaceLayout(["monocle"]))
        #expect(w.run(.moveFocus(.right)).effects.contains(.focus(1)))
    }

    @Test func submapsAndActiveBinds() {
        let w = world("bind = ALT, R, submap, resize\nsubmap = resize\nbinde = , H, resizeactive, -50 0\nbindu = , F1, exec, true\nsubmap = reset")
        #expect(w.activeBinds.map(\.dispatcher) == ["submap", "exec"])
        let r = w.run(.submap("resize"))
        #expect(r.effects.contains(.submapChanged("resize")))
        #expect(w.activeBinds.map(\.dispatcher) == ["resizeactive", "exec"])
        _ = w.run(.submap("reset"))
        #expect(w.submap == "")
    }

    @Test func killAndSignals() {
        let w = threeWindows()
        #expect(w.run(.killActive(force: false)).effects.contains(.close(3)))
        #expect(w.run(.killActive(force: true)).effects.contains(.signal(pid: 300, signal: 9)))
        #expect(w.run(.signal(15, .classRegex("Ghostty"))).effects.contains(.signal(pid: 100, signal: 15)))
    }

    @Test func focusWindowSwitchesToItsWorkspace() {
        let w = threeWindows()
        _ = w.run(.moveToWorkspace(.id(4), .address(1), silent: true))
        let e = w.run(.focusWindow(.address(1))).effects
        #expect(w.activeWorkspace[0] == 4)
        #expect(e.contains(.focus(1)))
        #expect(w.run(.focusCurrentOrLast).effects.contains(.focus(3)))
    }

    @Test func cursorAndRenameAndUnsupported() {
        let w = threeWindows()
        #expect(w.run(.moveCursorToCorner(3)).effects.contains(.warpCursor(Point(x: 756, y: 507))))
        #expect(ok(w.run(.renameWorkspace(1, "code"))))
        #expect(w.workspaces[1]?.name == "code")
        #expect(w.run(.unsupported("sendshortcut")).reply == "sendshortcut is not supported on macOS")
        #expect(w.run(.exit).effects.contains(.exitApp))
    }

    @Test func workspaceDispatchers() {
        let w = threeWindows()
        _ = w.run(.workspace(.id(2)))
        #expect(w.activeWorkspace[0] == 2)
        _ = w.run(.workspace(.previous))
        #expect(w.activeWorkspace[0] == 1)
        _ = w.run(.toggleSpecialWorkspace("magic"))
        #expect(w.activeSpecial[0] != nil)
        _ = w.run(.toggleSpecialWorkspace("magic"))
        #expect(w.activeSpecial[0] == nil)
    }
}

let portrait = MonitorInfo(id: 0, name: "Portrait", frame: Rect(x: 0, y: 0, width: 800, height: 1200),
                           visibleFrame: Rect(x: 0, y: 0, width: 800, height: 1200))

func sentSignals(_ effects: [Effect]) -> [Effect] {
    effects.filter { if case .signal = $0 { return true } else { return false } }
}

func twoFloatsAndOneTile() -> World {
    let w = world("windowrule = float on, match:class Calc")
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    _ = w.handle(.windowAppeared(snap(3, app: "Calc", bundle: "x.calc", pid: 300, frame: Rect(x: 100, y: 100, width: 200, height: 200))))
    return w
}

@Suite struct WorldDispatchExtraTests {
    @Test func exactSizesAndPositionsAreRelativeToTheWorkAreaLikeRectangle() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        _ = w.run(.floating(.set, .active))
        _ = w.run(.resizeActive(.exact(.percent(33.33), .percent(100))))
        let third = w.run(.moveActive(.exact(.percent(66.67), .percent(0)))).effects
        #expect(frames(third)[2] == Rect(x: 1008, y: 32, width: 504, height: 950))
        let gapped = world("general:gaps_out = 10")
        _ = gapped.handle(.windowAppeared(snap(1)))
        _ = gapped.run(.floating(.set, .active))
        _ = gapped.run(.resizeActive(.exact(.percent(50), .percent(100))))
        let half = gapped.run(.moveActive(.exact(.percent(50), .percent(0)))).effects
        #expect(frames(half)[1] == Rect(x: 756, y: 42, width: 746, height: 930))
    }

    @Test func selectorsMatchNonAsciiTitlesAndAppNames() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1, app: "Café Müller", bundle: "com.example.cafe", pid: 100, title: "Résumé – 日本語 😀")))
        _ = w.handle(.windowAppeared(snap(2, app: "Terminal", bundle: "com.apple.terminal", pid: 200, title: "plain")))
        #expect(w.matchingWindows(.title("Résumé – 日本語 😀")) == [1])
        #expect(w.matchingWindows(.title(".*日本語.*")) == [1])
        #expect(w.matchingWindows(.title(".*😀")) == [1])
        #expect(w.matchingWindows(.title("R.sum. .* 日本語 .")) == [1])
        #expect(w.matchingWindows(.title("Résumé")) == [])
        #expect(w.matchingWindows(.title("negative:.*日本語.*")) == [2])
        #expect(w.matchingWindows(.initialTitle("Résumé.*")) == [1])
        #expect(w.matchingWindows(.classRegex("Café Müller")) == [1])
        #expect(w.matchingWindows(.classRegex("Caf.* M.ller")) == [1])
        #expect(w.matchingWindows(.initialClass("negative:Café.*")) == [2])
        #expect(w.run(.focusWindow(.title(".*日本語.*"))).effects.contains(.focus(1)))
    }

    @Test func selectorsTreatComposedAndDecomposedTextAsEqual() {
        let w = world()
        let composed = "Caf\u{e9} \u{2013} r\u{e9}sum\u{e9}"
        let decomposed = "Cafe\u{301} \u{2013} re\u{301}sume\u{301}"
        #expect(Array(composed.unicodeScalars) != Array(decomposed.unicodeScalars))
        _ = w.handle(.windowAppeared(snap(1, app: decomposed, bundle: "", pid: 100, title: decomposed)))
        _ = w.handle(.windowAppeared(snap(2, app: composed, bundle: "", pid: 200, title: composed)))
        #expect(w.matchingWindows(.title(composed)) == [1, 2])
        #expect(w.matchingWindows(.title(decomposed)) == [1, 2])
        #expect(w.matchingWindows(.classRegex("Caf\u{e9}.*")) == [1, 2])
        #expect(w.matchingWindows(.classRegex("Cafe\u{301}.*")) == [1, 2])
        #expect(w.matchingWindows(.title("[\u{e9}c].*")) == [])
    }

    @Test func floatingAndTiledSelectorsPickTheFirstOnTheCurrentWorkspace() {
        let w = world("windowrule = float on, match:class Calc")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, app: "Calc", bundle: "x.calc", pid: 200)))
        _ = w.handle(.windowAppeared(snap(3, pid: 300)))
        _ = w.handle(.windowAppeared(snap(4, app: "Calc", bundle: "x.calc", pid: 400)))
        #expect(w.matchingWindows(.floating) == [2])
        #expect(w.matchingWindows(.tiled) == [1])
        #expect(w.matchingWindows(.pid(300)) == [3])
        #expect(w.matchingWindows(.address(4)) == [4])
        #expect(w.matchingWindows(.address(99)) == [])
        #expect(w.matchingWindows(.tag("x")) == [])
        #expect(w.matchingWindows(.classRegex("(")) == [])
        #expect(w.run(.closeWindow(.floating, force: false)).effects.contains(.close(2)))
        #expect(w.run(.closeWindow(.pid(400), force: true)).effects.contains(.signal(pid: 400, signal: 9)))
        #expect(w.run(.closeWindow(.title("zzz"), force: false)).reply == "no matching window")
    }

    @Test func signalsAreValidatedAndOnlyGoToRealProcesses() {
        let w = world()
        for (id, pid) in [(1, Int32(100)), (2, 0), (3, -1), (4, 1), (5, Int32.min)] { _ = w.handle(.windowAppeared(snap(WindowID(id), pid: pid))) }
        #expect(w.run(.signal(15, .pid(100))).effects.contains(.signal(pid: 100, signal: 15)))
        #expect(w.run(.signal(31, .pid(100))).isError == false)
        for pid in [Int32(0), -1, 1, Int32.min] {
            let r = w.run(.signal(9, .pid(pid)))
            #expect(r.isError)
            #expect(sentSignals(r.effects).isEmpty)
        }
        for sig in [Int32(0), -1, 32, 99, Int32.max, Int32.min] {
            let r = w.run(.signal(sig, .pid(100)))
            #expect(r.reply == "invalid signal \(sig)")
            #expect(sentSignals(r.effects).isEmpty)
        }
        let kill = w.run(.killActive(force: true))
        #expect(kill.isError)
        #expect(sentSignals(kill.effects).isEmpty)
        #expect(w.run(.killActive(force: false)).effects.contains(.close(5)))
        #expect(w.run(.closeWindow(.pid(0), force: true)).isError)
    }

    @Test func everyUnsupportedDispatcherRepliesAnErrorAndDoesNothing() {
        let w = threeWindows()
        let names = ["pass", "sendshortcut", "sendkeystate", "global", "event", "dpms", "forceidle", "toggleswallow", "tagwindow",
                     "togglegroup", "changegroupactive", "lockgroups", "lockactivegroup", "moveintogroup", "moveintoorcreategroup",
                     "moveoutofgroup", "movewindoworgroup", "movegroupwindow", "denywindowfromgroup", "setignoregrouplock"]
        for name in names {
            guard case .success(let command) = CommandParser.parse(dispatcher: name, arguments: "ctrl, c, activewindow") else {
                Issue.record("\(name) did not parse")
                continue
            }
            let r = w.run(command)
            #expect(r.isError)
            #expect(r.reply == "\(name) is not supported on macOS")
            #expect(r.effects.isEmpty)
        }
        #expect(w.run(.noop).isError == false)
    }

    @Test func extremeNumbersNeverEscapeTheBounds() {
        let w = threeWindows()
        _ = w.run(.floating(.set, .active))
        let huge = [1e308, -1e308, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 1e15, Double.nan, Double.infinity, -Double.infinity]
        for v in huge {
            let all = [w.run(.resizeActive(.relative(.pixels(v), .percent(v)))), w.run(.resizeActive(.exact(.percent(v), .pixels(v)))),
                       w.run(.moveActive(.relative(.pixels(v), .percent(v)))), w.run(.moveActive(.exact(.percent(v), .pixels(v)))),
                       w.run(.resizeWindow(.relative(.percent(v), .pixels(v)), .address(1))), w.run(.moveWindowTo(.exact(.pixels(v), .percent(v)), .address(3))),
                       w.run(.moveCursor(v, -v))]
            for r in all { #expect(allBounded(r.effects, limit: 1_000_000)) }
            let f = w.windows[3]!.floatingFrame
            #expect(abs(f.x) <= World.extent && abs(f.y) <= World.extent)
            #expect(f.width >= 20 && f.width <= World.extent && f.height >= 20 && f.height <= World.extent)
            #expect(abs(w.cursor.x) <= World.extent && abs(w.cursor.y) <= World.extent)
        }
        for _ in 0 ..< 5 {
            _ = w.run(.moveActive(.relative(.pixels(1e308), .pixels(-1e308))))
            _ = w.run(.resizeActive(.relative(.percent(1e308), .percent(1e308))))
        }
        let f = w.windows[3]!.floatingFrame
        #expect(abs(f.x) <= World.extent && abs(f.y) <= World.extent && f.width <= World.extent && f.height <= World.extent)
    }

    @Test func everyCommandIsSafeOnEmptyAndExtremeInput() {
        let all: [Command] = [
            .exec("true", rules: "float", raw: false), .exec("", rules: nil, raw: true), .killActive(force: true), .closeWindow(.active, force: false),
            .signal(15, .active), .workspace(.id(3)), .workspace(.previous), .workspace(.previousPerMonitor), .workspace(.relative(-5)),
            .workspace(.special("a")), .workspace(.special(nil)), .workspace(.name("web")), .workspace(.empty(currentMonitorOnly: true, next: true)),
            .workspace(.existing(-3)), .workspace(.existingAbsolute(2)), .workspace(.onMonitor(2, includeEmpty: true)), .workspace(.onMonitorAbsolute(1, includeEmpty: false)),
            .moveToWorkspace(.id(2), .active, silent: false), .moveToWorkspace(.id(2), .tiled, silent: true), .floating(.toggle, .active),
            .fullscreen(mode: 0, .toggle), .pin(.active), .pseudo(.active), .moveFocus(.left), .moveFocus(.down),
            .moveWindow(.direction(.up), silent: false), .moveWindow(.monitor(.relative(1)), silent: true), .swapWindow(.direction(.down)),
            .swapWindow(.window(.floating)), .centerWindow, .resizeActive(.relative(.pixels(5), .percent(5))), .moveActive(.exact(.percent(50), .pixels(0))),
            .resizeWindow(.exact(.pixels(300), .pixels(300)), .tiled), .moveWindowTo(.relative(.pixels(3), .pixels(3)), .floating),
            .cycleNext(CycleOptions()), .swapNext(previous: true), .focusWindow(.tiled), .focusMonitor(.relative(1)), .focusMonitor(.direction(.right)),
            .focusCurrentOrLast, .focusUrgentOrLast, .moveCurrentWorkspaceToMonitor(.direction(.right)), .moveWorkspaceToMonitor(.id(2), .id(0)),
            .focusWorkspaceOnCurrentMonitor(.id(3)), .swapActiveWorkspaces(.id(0), .id(1)), .toggleSpecialWorkspace(nil),
            .toggleSpecialWorkspace("a"), .renameWorkspace(1, "x"), .layoutMessage("togglesplit"), .submap("x"), .alterZOrder(top: true),
            .moveCursorToCorner(2), .moveCursor(1, 2), .workspaceLayout(["monocle"]), .workspaceLayout(["dwindle", "master"]),
            .setProp(.active, "border_size", "3"), .exit, .noop, .unsupported("pass"),
            .workspace(.id(Int.min)), .workspace(.id(Int.max)), .workspace(.relative(Int.min)), .workspace(.relative(Int.max)),
            .workspace(.onMonitor(Int.min, includeEmpty: true)), .workspace(.onMonitor(Int.max, includeEmpty: false)),
            .workspace(.existing(Int.min)), .workspace(.existingAbsolute(Int.max)), .workspace(.onMonitorAbsolute(Int.min, includeEmpty: true)),
            .moveToWorkspace(.relative(Int.max), .active, silent: false), .renameWorkspace(Int.min, "x"), .renameWorkspace(Int.max, ""),
            .moveCursorToCorner(Int.min), .moveCursorToCorner(Int.max), .moveCursorToCorner(-1), .moveCursorToCorner(4),
            .fullscreen(mode: Int.min, .set), .fullscreen(mode: Int.max, .toggle), .fullscreen(mode: 2, .unset),
            .focusMonitor(.relative(Int.min)), .focusMonitor(.relative(Int.max)), .focusMonitor(.id(Int.max)), .focusMonitor(.id(Int.min)),
            .moveWindow(.monitor(.relative(Int.min)), silent: false), .swapActiveWorkspaces(.id(Int.min), .id(Int.max)),
            .moveWorkspaceToMonitor(.id(Int.max), .relative(Int.max)), .signal(Int32.min, .pid(Int32.min)), .signal(Int32.max, .pid(Int32.max)),
            .signal(-1, .address(UInt32.max)), .killActive(force: false), .setProp(.pid(Int32.min), "border_size", "1e999"),
            .workspaceLayout([]), .workspaceLayout(["a", "b", "c"]), .layoutMessage(""), .submap(""),
            .moveCursor(.nan, .infinity), .moveCursor(-.infinity, 1e308), .resizeActive(.exact(.pixels(.nan), .percent(.infinity))),
            .moveActive(.relative(.percent(-.infinity), .pixels(.nan))),
            .layoutMessage("splitratio exact 1e308"), .layoutMessage("splitratio -1e308"), .layoutMessage("splitratio 1e308"),
            .layoutMessage("splitratio exact -1e308"), .layoutMessage("splitratio nan"), .layoutMessage("splitratio inf"),
            .layoutMessage("mfact exact 1e308"), .layoutMessage("mfact -1e308"), .layoutMessage("mfact nan"),
            .layoutMessage("addmaster"), .layoutMessage("removemaster"), .layoutMessage("orientationnext"), .layoutMessage("cyclenext"),
            .layoutMessage("swapwithmaster"), .layoutMessage("rollnext"), .layoutMessage("rollprev"), .layoutMessage("movetoroot"),
            .layoutMessage("preselect l"), .layoutMessage("swapsplit"), .layoutMessage("splitratio 9223372036854775807"),
        ]
        let worlds: [() -> World] = [
            { World(config: makeConfig()) },
            { world() },
            { world(monitors: [laptop, ultrawide]) },
            { threeWindows() },
            { threeWindows("general:layout = master") },
            { threeWindows("general:layout = monocle") },
            {
                let w = world(monitors: [laptop, ultrawide])
                for id: WindowID in 1 ... 3 { _ = w.handle(.windowAppeared(snap(id, pid: Int32(id) * 100))) }
                _ = w.run(.floating(.set, .address(1)))
                return w
            },
        ]
        for make in worlds {
            let w = make()
            for command in all {
                let r = w.run(command)
                #expect(allBounded(r.effects, limit: 1_000_000))
            }
        }
    }

    @Test func execAllocatesTokensOnlyForRulesAndKeepsPendingRulesBounded() {
        let w = world()
        #expect(w.run(.exec("true", rules: nil, raw: false)).effects == [.spawn("true", token: nil)])
        #expect(w.run(.exec("true", rules: "", raw: false)).effects == [.spawn("true", token: nil)])
        #expect(w.run(.exec("", rules: nil, raw: false)).isError)
        let first = w.run(.exec("kitty", rules: "float", raw: false)).effects
        #expect(first == [.spawn("kitty", token: 1)])
        var last = 0
        for _ in 0 ..< 400 {
            for case .spawn(_, let t?) in w.run(.exec("kitty", rules: "float", raw: false)).effects { last = t }
        }
        #expect(w.spawnRules.count <= World.pendingSpawnLimit)
        w.registerSpawn(token: last, pid: 77)
        #expect(w.pidRules[77] == "float")
        w.registerSpawn(token: 1, pid: 78)
        #expect(w.pidRules[78] == nil)
    }

    @Test func moveFocusFollowsTheFocusPreferredMethodAndRanksNeverFocusedLast() {
        let history = threeWindows()
        _ = history.run(.focusWindow(.address(1)))
        #expect(history.run(.moveFocus(.right)).effects.contains(.focus(3)))
        let overlap = threeWindows("binds:focus_preferred_method = 1")
        _ = overlap.run(.focusWindow(.address(1)))
        #expect(overlap.run(.moveFocus(.right)).effects.contains(.focus(2)))
        let unfocused = threeWindows()
        unfocused.focusHistory = [3, 1]
        unfocused.focusedWindow = 1
        #expect(unfocused.run(.moveFocus(.right)).effects.contains(.focus(3)))
        let none = threeWindows()
        none.focusHistory = [1]
        none.focusedWindow = 1
        #expect(none.run(.moveFocus(.right)).effects.contains(.focus(2)))
    }

    @Test func moveFocusWarpsTheCursorUnlessNoWarps() {
        let w = threeWindows()
        let e = w.run(.moveFocus(.up)).effects
        #expect(e.contains(.warpCursor(Point(x: 1134, y: 269.5))))
        #expect(w.cursor == Point(x: 1134, y: 269.5))
        let quiet = threeWindows("cursor:no_warps = true")
        let q = quiet.run(.moveFocus(.up)).effects
        #expect(q.contains(.focus(2)))
        #expect(q.contains(.raise(2)))
        #expect(!q.contains { if case .warpCursor = $0 { return true } else { return false } })
    }

    @Test func moveFocusWrapRulesAndMonocleSteps() {
        let stacked = world(monitors: [portrait])
        _ = stacked.handle(.windowAppeared(snap(1)))
        _ = stacked.handle(.windowAppeared(snap(2, pid: 200)))
        #expect(stacked.windows[1] != nil && stacked.focusedWindow == 2)
        _ = stacked.run(.moveFocus(.left))
        #expect(stacked.focusedWindow == 2)
        _ = stacked.run(.moveFocus(.right))
        #expect(stacked.focusedWindow == 2)
        #expect(stacked.run(.moveFocus(.down)).effects.contains(.focus(1)))
        #expect(stacked.run(.moveFocus(.up)).effects.contains(.focus(2)))
        let strict = world("general:no_focus_fallback = true")
        _ = strict.handle(.windowAppeared(snap(1)))
        _ = strict.handle(.windowAppeared(snap(2, pid: 200)))
        _ = strict.run(.focusWindow(.address(1)))
        #expect(!strict.run(.moveFocus(.left)).effects.contains(.focus(2)))
        #expect(strict.focusedWindow == 1)
        let single = world()
        _ = single.handle(.windowAppeared(snap(1)))
        #expect(single.run(.moveFocus(.left)).effects.isEmpty)
        let monocle = threeWindows()
        _ = monocle.run(.workspaceLayout(["monocle"]))
        #expect(monocle.run(.moveFocus(.left)).effects.contains(.focus(2)))
        #expect(monocle.run(.moveFocus(.down)).effects.contains(.focus(3)))
    }

    @Test func moveFocusCyclesFullscreenWindowsWhenAsked() {
        let on = threeWindows("binds:movefocus_cycles_fullscreen = true")
        _ = on.run(.fullscreen(mode: 0, .set))
        #expect(on.run(.moveFocus(.left)).effects.contains(.focus(2)))
        let forward = threeWindows("binds:movefocus_cycles_fullscreen = true")
        _ = forward.run(.fullscreen(mode: 1, .set))
        #expect(forward.run(.moveFocus(.down)).effects.contains(.focus(1)))
        let off = threeWindows()
        _ = off.run(.fullscreen(mode: 0, .set))
        #expect(off.run(.moveFocus(.left)).effects.contains(.focus(1)))
    }

    @Test func moveFocusIgnoresWindowsHiddenUnderASpecialWorkspace() {
        let w = world("dwindle:special_scale_factor = 0.5\nwindowrule = workspace special:magic, match:class Magic")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        _ = w.handle(.windowAppeared(snap(3, app: "Magic", bundle: "x.magic", pid: 300)))
        #expect(w.activeSpecial[0] != nil)
        #expect(w.focusedWindow == 3)
        for d in Direction.allCases {
            _ = w.run(.moveFocus(d))
            #expect(w.focusedWindow == 3)
        }
    }

    @Test func floatingOriginSearchesFloatsThenTiles() {
        let w = twoFloatsAndOneTile()
        #expect(w.windows[3]?.isFloating == true)
        #expect(w.focusedWindow == 3)
        #expect(w.run(.moveFocus(.right)).effects.contains(.focus(2)))
        _ = w.run(.focusWindow(.address(3)))
        #expect(w.run(.moveFocus(.left)).effects.contains(.focus(2)))
        let floats = world("windowrule = float on, match:class Calc")
        for (id, x) in [(1, 100.0), (2, 500.0), (3, 900.0)] {
            _ = floats.handle(.windowAppeared(snap(WindowID(id), app: "Calc", bundle: "x.calc", pid: Int32(id) * 10,
                                                   frame: Rect(x: x, y: 100, width: 200, height: 200))))
        }
        _ = floats.run(.focusWindow(.address(1)))
        #expect(floats.run(.moveFocus(.right)).effects.contains(.focus(2)))
        #expect(floats.run(.moveFocus(.right)).effects.contains(.focus(3)))
        #expect(floats.run(.moveFocus(.left)).effects.contains(.focus(2)))
    }

    @Test func focusCurrentOrLastSkipsSuspendedWindowsAndWorksWithoutFocus() {
        let w = threeWindows()
        _ = w.handle(.windowSuspended(2, .minimized))
        #expect(w.run(.focusCurrentOrLast).effects.contains(.focus(1)))
        let blank = threeWindows()
        _ = blank.handle(.focusChanged(nil))
        #expect(blank.focusedWindow == nil)
        #expect(blank.run(.focusUrgentOrLast).effects.contains(.focus(3)))
        let one = world()
        _ = one.handle(.windowAppeared(snap(1)))
        #expect(one.run(.focusCurrentOrLast).effects.isEmpty)
    }

    @Test func focusWindowWarpsAndRaisesAcrossWorkspaces() {
        let w = threeWindows()
        _ = w.run(.moveToWorkspace(.id(4), .address(1), silent: true))
        let e = w.run(.focusWindow(.address(1))).effects
        #expect(e.filter { $0 == .focus(1) }.count == 1)
        #expect(e.contains(.raise(1)))
        #expect(e.contains(.warpCursor(Point(x: 756, y: 507))))
        let quiet = threeWindows("cursor:no_warps = true")
        _ = quiet.run(.moveToWorkspace(.id(4), .address(1), silent: true))
        let q = quiet.run(.focusWindow(.address(1))).effects
        #expect(q.contains(.focus(1)) && q.contains(.raise(1)))
        #expect(!q.contains { if case .warpCursor = $0 { return true } else { return false } })
        #expect(quiet.run(.focusWindow(.address(99))).reply == "no matching window")
    }

    @Test func cycleVariants() {
        let w = threeWindows()
        _ = w.run(.floating(.set, .address(2)))
        var tiled = CycleOptions()
        tiled.tiledOnly = true
        #expect(w.run(.cycleNext(tiled)).effects.contains(.focus(1)))
        var floating = CycleOptions()
        floating.floatingOnly = true
        #expect(w.run(.cycleNext(floating)).effects.contains(.focus(2)))
        var both = CycleOptions()
        both.floatingOnly = true
        both.tiledOnly = true
        #expect(w.run(.cycleNext(both)).effects.isEmpty)
        let h = threeWindows()
        var hist = CycleOptions()
        hist.history = true
        #expect(h.run(.cycleNext(hist)).effects.contains(.focus(2)))
        hist.previous = true
        let h2 = threeWindows()
        #expect(h2.run(.cycleNext(hist)).effects.contains(.focus(1)))
        let two = world(monitors: [laptop, ultrawide])
        _ = two.handle(.windowAppeared(snap(1)))
        _ = two.handle(.windowAppeared(snap(2, pid: 200)))
        _ = two.run(.moveWindow(.monitor(.id(1)), silent: true))
        #expect(two.focusedWindow == 1)
        var visible = CycleOptions()
        visible.visible = true
        #expect(two.run(.cycleNext(visible)).effects.contains(.focus(2)))
        #expect(two.focusedMonitor == 1)
        var local = CycleOptions()
        local.previous = true
        _ = two.run(.focusWindow(.address(1)))
        #expect(two.run(.cycleNext(local)).effects.contains(.focus(1)))
    }

    @Test func swapWindowByTargetAndSwapNextBackwards() {
        let w = threeWindows()
        _ = w.run(.swapWindow(.window(.address(1))))
        #expect(w.workspaces[1]?.tiledIDs == [3, 2, 1])
        #expect(w.run(.swapWindow(.window(.address(3)))).reply == "no window to swap with")
        #expect(w.run(.swapWindow(.window(.address(99)))).reply == "no window to swap with")
        _ = w.run(.floating(.set, .address(2)))
        #expect(w.run(.swapWindow(.window(.address(2)))).reply == "no window to swap with")
        _ = w.run(.swapNext(previous: true))
        #expect(w.workspaces[1]?.tiledIDs == [1, 3])
        _ = w.run(.floating(.set, .active))
        #expect(w.run(.swapNext(previous: false)).reply == "no tiled active window")
        #expect(w.run(.swapWindow(.direction(.left))).reply == "no tiled active window")
    }

    @Test func workspaceDispatchersReportBadInput() {
        let w = threeWindows()
        #expect(w.run(.workspace(.previous)).reply == "invalid workspace")
        #expect(w.run(.moveToWorkspace(.previous, .active, silent: false)).reply == "invalid workspace")
        #expect(w.run(.moveToWorkspace(.id(2), .title("zzz"), silent: false)).reply == "no matching window")
        #expect(w.run(.focusMonitor(.id(5))).reply == "invalid monitor")
        #expect(w.run(.renameWorkspace(42, "x")).reply == "no such workspace")
        #expect(w.run(.toggleSpecialWorkspace("")).reply == "invalid workspace")
        _ = w.run(.toggleSpecialWorkspace("magic"))
        let special = w.activeSpecial[0]!
        #expect(w.run(.renameWorkspace(special, "other")).reply == "cannot rename a special workspace")
        #expect(w.workspaces[special]?.name == "magic")
        #expect(w.run(.renameWorkspace(1, "")).isError == false)
        #expect(w.workspaces[1]?.name == "1")
    }

    @Test func moveWorkspaceToMonitorDoesNotLeaveEmptyWorkspacesBehind() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.run(.moveWorkspaceToMonitor(.id(7), .id(0)))
        #expect(w.workspaces[7] == nil)
        _ = w.run(.moveWorkspaceToMonitor(.name("ghost"), .id(0)))
        #expect(w.workspaces.values.contains { $0.name == "ghost" } == false)
        _ = w.run(.moveWorkspaceToMonitor(.id(7), .id(1)))
        #expect(w.workspaces[7]?.monitor == 1)
        #expect(w.activeWorkspace[1] == 7)
    }

    @Test func workspaceLayoutAcceptsOneOrTwoKnownLayouts() {
        let w = threeWindows()
        #expect(w.run(.workspaceLayout(["dwindle", "master", "monocle"])).reply == "invalid layout")
        #expect(w.run(.workspaceLayout(["dwindle", "spiral"])).reply == "invalid layout")
        #expect(w.run(.workspaceLayout([])).reply == "invalid layout")
        #expect(w.run(.workspaceLayout(["master"])).isError == false)
        #expect(w.workspaces[1]?.layout.kind == .master)
        #expect(w.workspaces[1]?.tiledIDs.sorted() == [1, 2, 3])
        #expect(w.run(.workspaceLayout(["master"])).effects.isEmpty)
        _ = w.run(.workspaceLayout(["master", "monocle"]))
        #expect(w.workspaces[1]?.layout.kind == .monocle)
        _ = w.run(.workspaceLayout(["master", "monocle"]))
        #expect(w.workspaces[1]?.layout.kind == .master)
    }

    @Test func setPropValidatesAndUnsets() {
        let w = twoWindows()
        let thick = w.run(.setProp(.active, "border_size", "4")).effects
        #expect(frames(thick)[2] != nil && frames(thick)[2] != rightHalf)
        #expect(w.windows[2]?.props["border_size"] == "4")
        #expect(frames(w.run(.setProp(.pid(200), "border_size", "unset")).effects)[2] == rightHalf)
        #expect(w.windows[2]?.props["border_size"] == nil)
        #expect(w.run(.setProp(.active, "border_size", "abc")).reply == "invalid value for border_size: abc")
        #expect(w.run(.setProp(.active, "border_size", "1e999")).isError)
        #expect(w.run(.setProp(.active, "border_color", "nope")).isError)
        #expect(w.run(.setProp(.active, "no_anim", "maybe")).isError)
        #expect(w.run(.setProp(.active, "border_color", "rgba(89b482ee)")).isError == false)
        #expect(w.run(.setProp(.active, "no_anim", "1")).isError == false)
        #expect(w.windows[2]?.props["no_anim"] == "1")
        #expect(w.run(.setProp(.active, "alpha", "0.5")).reply == "setprop alpha is not supported on macOS")
        #expect(w.run(.setProp(.address(77), "no_anim", "1")).reply == "no matching window")
        _ = w.run(.setProp(.active, "border_size", "1e300"))
        #expect(allBounded(w.takeEffects()))
    }

    @Test func degenerateCommandsAnswerWithErrors() {
        let w = threeWindows()
        #expect(w.run(.fullscreen(mode: 2, .toggle)).reply == "invalid fullscreen mode")
        #expect(w.run(.moveCursorToCorner(4)).reply == "invalid corner")
        #expect(w.run(.moveCursorToCorner(-1)).reply == "invalid corner")
        #expect(w.run(.centerWindow).reply == "no floating active window")
        #expect(w.run(.resizeWindow(.exact(.pixels(300), .pixels(300)), .address(99))).reply == "no matching window")
        #expect(w.run(.moveWindowTo(.relative(.pixels(1), .pixels(1)), .address(1))).reply == "movewindowpixel works only on floating windows")
        #expect(w.run(.alterZOrder(top: true)).effects.contains(.raise(3)))
        _ = w.handle(.focusChanged(nil))
        #expect(w.run(.killActive(force: false)).reply == "no active window")
        #expect(w.run(.fullscreen(mode: 0, .toggle)).reply == "no active window")
        #expect(w.run(.moveCursorToCorner(0)).reply == "no active window")
        #expect(w.run(.resizeActive(.exact(.pixels(300), .pixels(300)))).reply == "no active window")
    }

    @Test func submapResetAndRepeatedSubmapEntries() {
        let w = world("bind = ALT, R, submap, resize\nsubmap = resize\nbinde = , H, resizeactive, -50 0\nsubmap = reset")
        #expect(w.run(.submap("resize")).effects.contains(.submapChanged("resize")))
        #expect(w.submap == "resize")
        let reset = w.run(.submap("reset")).effects
        #expect(reset.contains(.submapChanged("")))
        #expect(w.submap == "")
    }
}
