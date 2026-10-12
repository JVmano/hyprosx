import Testing
@testable import HyprCore

let ultrawide = MonitorInfo(id: 1, name: "PHL 499P9", frame: Rect(x: 1512, y: 0, width: 3440, height: 1440),
                            visibleFrame: Rect(x: 1512, y: 0, width: 3440, height: 1440))
let full = Rect(x: 0, y: 32, width: 1512, height: 950)
let leftHalf = Rect(x: 0, y: 32, width: 756, height: 950)
let rightHalf = Rect(x: 756, y: 32, width: 756, height: 950)

func reasons(_ effects: [Effect]) -> [WindowID: FrameReason] {
    var out: [WindowID: FrameReason] = [:]
    for case .setFrames(let changes) in effects { for c in changes { out[c.id] = c.reason } }
    return out
}

func hasFocusEffect(_ effects: [Effect]) -> Bool {
    effects.contains { if case .focus = $0 { return true }; return false }
}

func twoWindows(_ text: String = "") -> World {
    let w = world(text)
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    return w
}

@Suite struct WorldWorkspaceEventTests {
    @Test func switchingParksAndRestores() {
        let w = twoWindows()
        w.switchWorkspace(2)
        let away = w.takeEffects()
        #expect(parks(away).keys.sorted() == [1, 2])
        #expect(w.focusedWindow == nil)
        w.switchWorkspace(1)
        let back = w.takeEffects()
        #expect(frames(back) == [1: leftHalf, 2: rightHalf])
        #expect(reasons(back)[1] == .workspaceIn(leftward: false))
        #expect(w.workspaces[2] == nil)
        #expect(back.contains(.focus(2)))
    }

    @Test func backAndForth() {
        let w = twoWindows("binds:workspace_back_and_forth = true")
        w.switchWorkspace(2)
        w.switchWorkspace(2)
        #expect(w.activeWorkspace[0] == 1)
    }

    @Test func selectors() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        w.switchWorkspace(3)
        _ = w.handle(.windowAppeared(snap(3, pid: 300)))
        w.switchWorkspace(5)
        _ = w.handle(.windowAppeared(snap(5, pid: 500)))
        _ = w.takeEffects()
        #expect(w.resolveWorkspace(.existing(1)) == 1)
        #expect(w.resolveWorkspace(.existing(-1)) == 3)
        #expect(w.resolveWorkspace(.empty(currentMonitorOnly: false, next: false)) == 2)
        #expect(w.resolveWorkspace(.previous) == 3)
        #expect(w.resolveWorkspace(.relative(2)) == 7)
        let web = w.resolveWorkspace(.name("web"))
        #expect(web == 1_000_000 && w.workspaces[1_000_000]?.name == "web")
    }

    @Test func moveToWorkspaceFollows() {
        let w = twoWindows()
        w.moveWindow(2, toWorkspace: 3, silent: false)
        let e = w.takeEffects()
        #expect(w.activeWorkspace[0] == 3)
        #expect(frames(e)[2] == full)
        #expect(parks(e)[1] != nil)
        #expect(w.focusedWindow == 2)
    }

    @Test func moveToWorkspaceSilent() {
        let w = twoWindows()
        w.moveWindow(2, toWorkspace: 3, silent: true)
        let e = w.takeEffects()
        #expect(w.activeWorkspace[0] == 1)
        #expect(frames(e)[1] == full)
        #expect(parks(e)[2] != nil)
        #expect(e.contains(.focus(1)))
    }

    @Test func specialWorkspaceScaleToggleAndCloseOnEmpty() {
        let w = world("dwindle:special_scale_factor = 0.8")
        _ = w.handle(.windowAppeared(snap(1)))
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(1, toWorkspace: special, silent: false)
        let shown = w.takeEffects()
        #expect(w.activeSpecial[0] == special)
        #expect(frames(shown)[1] == Rect(x: 151, y: 127, width: 1210, height: 760))
        w.toggleSpecial(special)
        #expect(parks(w.takeEffects())[1] != nil)
        w.toggleSpecial(special)
        _ = w.takeEffects()
        _ = w.handle(.windowDisappeared(1))
        #expect(w.activeSpecial[0] == nil)
    }

    @Test func pinnedFloatingWindowFollowsSwitch() {
        let w = world("windowrule = float on, match:class Calculator\nwindowrule = pin on, match:class Calculator")
        _ = w.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50)))
        w.switchWorkspace(2)
        let e = w.takeEffects()
        #expect(w.windows[5]?.workspace == 2)
        #expect(parks(e)[5] == nil)
    }

    @Test func unplugAndReplugKeepsWorkspaces() {
        let w = world("workspace = 6, monitor:1, default:true\nwindowrule = float on, match:class Calculator", monitors: [laptop, ultrawide])
        #expect(w.activeWorkspace[1] == 6)
        w.focusMonitor(1)
        _ = w.takeEffects()
        _ = w.handle(.windowAppeared(snap(9, pid: 900)))
        let docked = Rect(x: 2000, y: 100, width: 800, height: 600)
        _ = w.handle(.windowAppeared(snap(10, app: "Calculator", bundle: "com.apple.calculator", pid: 1000, frame: docked)))
        #expect(w.windows[9]?.workspace == 6)
        #expect(w.windows[10]?.workspace == 6)
        let unplug = w.handle(.monitorsChanged([laptop]))
        #expect(parks(unplug)[9] != nil)
        #expect(w.workspaces[6]?.monitor == 0)
        #expect(w.windows[10]?.floatingFrame == Rect(x: 488, y: 100, width: 800, height: 600))
        w.switchWorkspace(6)
        let undocked = w.takeEffects()
        #expect(frames(undocked)[10] == Rect(x: 488, y: 100, width: 800, height: 600))
        w.switchWorkspace(1)
        _ = w.takeEffects()
        let replug = w.handle(.monitorsChanged([laptop, ultrawide]))
        #expect(w.activeWorkspace[1] == 6)
        #expect(frames(replug)[9] == ultrawide.visibleFrame)
        #expect(frames(replug)[10] == docked)
    }

    @Test func focusMonitorWarpsAndSwapActive() {
        let w = world(monitors: [laptop, ultrawide])
        w.focusMonitor(1)
        let e = w.takeEffects()
        #expect(w.focusedMonitor == 1)
        #expect(e.contains(.warpCursor(Point(x: 3232, y: 720))))
        w.swapActiveWorkspaces(0, 1)
        #expect(w.activeWorkspace[0] == 2 && w.activeWorkspace[1] == 1)
    }

    @Test func minimizeAndRestore() {
        let w = twoWindows()
        let gone = w.handle(.windowSuspended(2, .minimized))
        #expect(frames(gone) == [1: full])
        #expect(gone.contains(.focus(1)))
        let back = w.handle(.windowResumed(2))
        #expect(frames(back) == [1: leftHalf, 2: rightHalf])
    }

    @Test func userHiddenAppIsUnhiddenWhenConfigured() {
        let w = twoWindows("macos:unhide_hidden_apps = true")
        #expect(w.handle(.appHidden(pid: 100, byUser: true)).contains(.unhideApp(100)))
        let plain = twoWindows()
        _ = plain.handle(.appHidden(pid: 100, byUser: true))
        #expect(plain.windows[1]?.suspended == .appHidden)
        _ = plain.handle(.appUnhidden(pid: 100))
        #expect(plain.windows[1]?.suspended == nil)
    }

    @Test func earlyTitleRerunsRules() {
        let w = world("windowrule = float on, match:title Picture-in-Picture")
        _ = w.handle(.windowAppeared(snap(1, title: "")))
        #expect(w.windows[1]?.isFloating == false)
        _ = w.handle(.windowTitleChanged(1, "Picture-in-Picture", early: true))
        #expect(w.windows[1]?.isFloating == true)
        _ = w.handle(.windowAppeared(snap(2, pid: 200, title: "")))
        _ = w.handle(.windowTitleChanged(2, "Picture-in-Picture", early: false))
        #expect(w.windows[2]?.isFloating == false)
    }

    @Test func userResizeMovesTheSplit() {
        let w = twoWindows()
        let e = w.handle(.windowFrameChanged(1, Rect(x: 0, y: 32, width: 856, height: 950), userDriven: true))
        #expect(frames(e) == [2: Rect(x: 856, y: 32, width: 656, height: 950)])
        let end = w.handle(.dragEnded(cursor: Point(x: 856, y: 500)))
        #expect(frames(end).isEmpty)
    }

    @Test func userMoveDropsOnAnotherTile() {
        let w = twoWindows()
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        let e = w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))
        #expect(frames(e) == [1: rightHalf, 2: leftHalf])
    }

    @Test func appDrivenMoveIsRefitOnce() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        let first = w.handle(.windowFrameChanged(1, Rect(x: 10, y: 40, width: 800, height: 600), userDriven: false))
        #expect(frames(first) == [1: full])
        let second = w.handle(.windowFrameChanged(1, Rect(x: 10, y: 40, width: 800, height: 600), userDriven: false))
        #expect(frames(second).isEmpty)
    }

    @Test func outsideActivationShowsWorkspaceWithoutFocusEffect() {
        let w = twoWindows()
        w.moveWindow(2, toWorkspace: 3, silent: true)
        _ = w.takeEffects()
        let e = w.handle(.focusChanged(2))
        #expect(w.activeWorkspace[0] == 3)
        #expect(!hasFocusEffect(e))
        #expect(w.focusedWindow == 2)
    }

    @Test func followMouse() {
        let on = twoWindows("input:follow_mouse = 1")
        #expect(on.handle(.cursorMoved(Point(x: 100, y: 500))).contains(.focus(1)))
        let off = twoWindows("input:follow_mouse = 0")
        #expect(!hasFocusEffect(off.handle(.cursorMoved(Point(x: 100, y: 500)))))
    }

    @Test func appTerminationRemovesItsWindows() {
        let w = twoWindows()
        let e = w.handle(.appTerminated(pid: 100))
        #expect(w.windows[1] == nil)
        #expect(frames(e) == [2: full])
    }

    @Test func windowClosedDuringDragLeavesWorldClean() {
        let w = twoWindows()
        _ = w.handle(.focusChanged(1))
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        let gone = w.handle(.windowDisappeared(1))
        #expect(frames(gone) == [2: full])
        #expect(w.focusedWindow == 2)
        #expect(frames(w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))).isEmpty)
        #expect(w.handle(.windowFrameChanged(1, Rect(x: 0, y: 0, width: 10, height: 10), userDriven: true)).isEmpty)
        #expect(w.handle(.windowTitleChanged(1, "late", early: true)).isEmpty)
        #expect(w.handle(.windowDisappeared(1)).isEmpty)
    }
}

@Suite struct WorldWorkspaceEventExtraTests {
    @Test func visibleSpecialClosesOnEmptyAndFreesItsID() {
        let w = twoWindows()
        let special = w.resolveWorkspace(.special("magic"))!
        #expect(special == -98)
        w.moveWindow(2, toWorkspace: special, silent: false)
        #expect(w.activeSpecial[0] == special)
        #expect(w.focusedWindow == 2)
        _ = w.takeEffects()
        let e = w.handle(.windowDisappeared(2))
        #expect(w.activeSpecial[0] == nil)
        #expect(w.workspaces[special] == nil)
        #expect(w.focusedWindow == 1)
        #expect(e.contains(.focus(1)))
        #expect(w.resolveWorkspace(.special("other")) == special)
    }

    @Test func closeSpecialOnEmptyCanBeDisabled() {
        let w = twoWindows("misc:close_special_on_empty = false")
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(2, toWorkspace: special, silent: false)
        _ = w.handle(.windowDisappeared(2))
        #expect(w.activeSpecial[0] == special)
    }

    @Test func terminatedAppClosesAnEmptiedSpecial() {
        let w = twoWindows()
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(1, toWorkspace: special, silent: false)
        _ = w.handle(.appTerminated(pid: 100))
        #expect(w.activeSpecial[0] == nil)
        #expect(w.workspaces[special] == nil)
        #expect(w.focusedWindow == 2)
    }

    @Test func movingTheLastWindowOutOfAVisibleSpecialClosesIt() {
        let w = twoWindows()
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(2, toWorkspace: special, silent: false)
        w.moveWindow(2, toWorkspace: 1, silent: false)
        #expect(w.activeSpecial[0] == nil)
        #expect(w.workspaces[special] == nil)
        #expect(w.focusedWindow == 2)
    }

    @Test func extremeSelectorValuesNeverTrap() {
        let w = twoWindows()
        #expect(w.resolveWorkspace(.relative(Int.max)) == Int(Int32.max))
        #expect(w.resolveWorkspace(.relative(Int.min)) == 1)
        #expect(w.resolveWorkspace(.id(Int.max)) == Int(Int32.max))
        #expect(w.resolveWorkspace(.existing(Int.min)) == 1)
        #expect(w.resolveWorkspace(.existing(Int.max)) == 1)
        #expect(w.resolveWorkspace(.existingAbsolute(Int.min)) == nil)
        #expect(w.resolveWorkspace(.onMonitor(Int.max, includeEmpty: true)) == Int(Int32.max))
        #expect(w.resolveWorkspace(.onMonitor(Int.min, includeEmpty: false)) == 1)
        #expect(w.resolveWorkspace(.onMonitorAbsolute(Int.min, includeEmpty: false)) == nil)
        #expect(w.resolveMonitor(.relative(Int.max)) == 0)
        #expect(w.resolveMonitor(.relative(Int.min)) == 0)
        _ = w.handle(.appHidden(pid: Int32.min, byUser: true))
        _ = w.handle(.appHidden(pid: Int32.max, byUser: false))
        _ = w.handle(.appUnhidden(pid: Int32.min))
        _ = w.handle(.appTerminated(pid: Int32.min))
        #expect(w.windows.count == 2)
    }

    @Test func monitorSelectorsResolveAcrossTwoMonitors() {
        let w = world(monitors: [laptop, ultrawide])
        #expect(w.resolveMonitor(.current) == 0)
        #expect(w.resolveMonitor(.direction(.right)) == 1)
        #expect(w.resolveMonitor(.direction(.left)) == nil)
        #expect(w.resolveMonitor(.relative(1)) == 1)
        #expect(w.resolveMonitor(.relative(-1)) == 1)
        #expect(w.resolveMonitor(.id(1)) == 1)
        #expect(w.resolveMonitor(.id(5)) == nil)
        #expect(w.resolveMonitor(.name("PHL")) == 1)
        #expect(w.monitorInDirection(from: 1, .left) == 0)
    }

    @Test func movingAWindowToTheCurrentWorkspaceNeverBouncesBack() {
        let w = world("binds:workspace_back_and_forth = true", monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        w.switchWorkspace(3)
        w.switchWorkspace(1)
        w.focusMonitor(1)
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        #expect(w.windows[2]?.workspace == 2)
        w.focusMonitor(0)
        w.moveWindow(2, toWorkspace: 1, silent: false)
        #expect(w.activeWorkspace[0] == 1)
        #expect(w.windows[2]?.workspace == 1)
        #expect(w.focusedWindow == 2)
    }

    @Test func ruleWorkspaceIsShownWhenNotSilent() {
        let w = world("windowrule = workspace 3, match:class Slack\nwindowrule = workspace special:big, match:class Big")
        _ = w.handle(.windowAppeared(snap(1)))
        let e = w.handle(.windowAppeared(snap(2, app: "Slack", bundle: "x.slack", pid: 200)))
        #expect(w.activeWorkspace[0] == 3)
        #expect(parks(e)[1] != nil)
        #expect(frames(e)[2] == full)
        #expect(e.filter { $0 == .focus(2) }.count == 1)
        #expect(w.focusedWindow == 2)
        let s = w.handle(.windowAppeared(snap(3, app: "Big", bundle: "x.big", pid: 300)))
        #expect(w.activeSpecial[0] == -98)
        #expect(w.focusedWindow == 3)
        #expect(s.filter { $0 == .focus(3) }.count == 1)
    }

    @Test func unusableWorkspaceIDsAreRejected() {
        let w = twoWindows()
        w.switchWorkspace(-5)
        w.switchWorkspace(0)
        w.switchWorkspace(Int.max)
        w.moveWindow(2, toWorkspace: -5, silent: false)
        w.focusWorkspaceOnCurrentMonitor(Int.min)
        #expect(w.workspaces.keys.sorted() == [1])
        #expect(w.windows[2]?.workspace == 1)
    }

    @Test func suspendedWindowsAreNotMoved() {
        let w = twoWindows()
        _ = w.handle(.windowSuspended(2, .minimized))
        w.moveWindow(2, toWorkspace: 3, silent: true)
        #expect(w.windows[2]?.workspace == 1)
        #expect(w.workspaces[3] == nil)
    }

    @Test func togglingFloatSizesTheWindowAndKeepsTheFocusRestore() {
        let w = twoWindows()
        w.setFloating(2, true)
        #expect(w.windows[2]?.floatingFrame == Rect(x: 302, y: 222, width: 907, height: 570))
        _ = w.takeEffects()
        w.switchWorkspace(2)
        _ = w.takeEffects()
        w.switchWorkspace(1)
        #expect(w.takeEffects().contains(.focus(2)))
        let pinned = world("windowrule = float on, match:class Calculator\nwindowrule = pin on, match:class Calculator")
        _ = pinned.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50)))
        #expect(pinned.windows[5]?.isPinned == true)
        pinned.setFloating(5, false)
        #expect(pinned.windows[5]?.isPinned == false)
        #expect(pinned.windows[5]?.isFloating == false)
    }

    @Test func switchHidesTheSpecialWorkspaceOnlyWhenConfigured() {
        let hide = twoWindows("binds:hide_special_on_workspace_change = true")
        let special = hide.resolveWorkspace(.special("magic"))!
        hide.moveWindow(2, toWorkspace: special, silent: false)
        _ = hide.takeEffects()
        hide.switchWorkspace(2)
        #expect(hide.activeSpecial[0] == nil)
        #expect(parks(hide.takeEffects())[2] != nil)
        let keep = twoWindows()
        let kept = keep.resolveWorkspace(.special("magic"))!
        keep.moveWindow(2, toWorkspace: kept, silent: false)
        keep.switchWorkspace(2)
        #expect(keep.activeSpecial[0] == kept)
    }

    @Test func specialWorkspaceMovesBetweenMonitors() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(1, toWorkspace: special, silent: false)
        _ = w.takeEffects()
        w.toggleSpecial(special, show: true, on: 1)
        let e = w.takeEffects()
        #expect(w.activeSpecial[0] == nil && w.activeSpecial[1] == special)
        #expect(w.workspaces[special]?.monitor == 1)
        #expect(frames(e)[1].map { ultrawide.frame.contains($0.center) } == true)
    }

    @Test func followMouseInMonocleKeepsTheFocusedWindow() {
        let w = twoWindows("general:layout = monocle\ninput:follow_mouse = 1")
        #expect(w.focusedWindow == 2)
        #expect(!hasFocusEffect(w.handle(.cursorMoved(Point(x: 100, y: 500)))))
        #expect(w.focusedWindow == 2)
    }

    @Test func dropOnAnotherTileSwapsInOtherLayouts() {
        let w = twoWindows("general:layout = master")
        let a = w.windows[1]!.appliedFrame!, b = w.windows[2]!.appliedFrame!
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: a.width, height: a.height), userDriven: true))
        let e = w.handle(.dragEnded(cursor: b.center))
        #expect(frames(e) == [1: b, 2: a])
    }

    @Test func dropOutsideEveryTileSnapsBackInOtherLayouts() {
        let w = twoWindows("general:layout = master")
        let a = w.windows[1]!.appliedFrame!
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: a.width, height: a.height), userDriven: true))
        let e = w.handle(.dragEnded(cursor: Point(x: 1000, y: 10)))
        #expect(frames(e) == [1: a])
    }

    @Test func minimizingTheDraggedWindowEndsTheDrag() {
        let w = twoWindows()
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        _ = w.handle(.windowSuspended(1, .minimized))
        _ = w.handle(.windowResumed(1))
        #expect(frames(w.handle(.dragEnded(cursor: Point(x: 1300, y: 800)))).isEmpty)
    }

    @Test func removingTheDraggedWindowClearsTheDragState() {
        let w = twoWindows()
        _ = w.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        #expect(w.dragging == 1)
        _ = w.handle(.windowDisappeared(1))
        #expect(w.dragging == nil)
        let m = twoWindows()
        _ = m.handle(.windowFrameChanged(1, Rect(x: 300, y: 200, width: 756, height: 950), userDriven: true))
        _ = m.handle(.windowSuspended(1, .minimized))
        #expect(m.dragging == nil)
    }

    @Test func refitIsAllowedAgainAfterTheTargetChanged() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        let off = Rect(x: 10, y: 40, width: 800, height: 600)
        #expect(frames(w.handle(.windowFrameChanged(1, off, userDriven: false))) == [1: full])
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        _ = w.handle(.windowDisappeared(2))
        #expect(frames(w.handle(.windowFrameChanged(1, off, userDriven: false))) == [1: full])
    }

    @Test func earlyTitleCanIgnoreAWindowAndFocusMovesOn() {
        let w = world("windowrule = ignore on, match:title Secret")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200, title: "")))
        let e = w.handle(.windowTitleChanged(2, "Secret", early: true))
        #expect(w.windows[2] == nil)
        #expect(frames(e) == [1: full])
        #expect(e.contains(.focus(1)))
        #expect(w.handle(.windowAppeared(snap(2, pid: 200))).isEmpty)
    }

    @Test func unplugMovesFocusOffTheHiddenWorkspace() {
        let w = world("workspace = 6, monitor:1, default:true", monitors: [laptop, ultrawide])
        w.focusMonitor(1)
        _ = w.handle(.windowAppeared(snap(9, pid: 900)))
        #expect(w.focusedWindow == 9)
        _ = w.handle(.monitorsChanged([laptop]))
        #expect(w.focusedWindow == nil)
        #expect(w.focusedMonitor == 0)
    }

    @Test func moveWorkspaceToMonitorReplacesTheShownOne() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.takeEffects()
        w.moveWorkspace(1, toMonitor: 1)
        let e = w.takeEffects()
        #expect(w.activeWorkspace[1] == 1)
        #expect(w.workspaces[1]?.monitor == 1)
        #expect(w.activeWorkspace[0] == 3)
        #expect(w.workspaces[2] == nil)
        #expect(frames(e)[1] == ultrawide.visibleFrame)
        #expect(w.focusedMonitor == 1)
    }

    @Test func focusWorkspaceOnCurrentMonitorSwapsOrMoves() {
        let w = world(monitors: [laptop, ultrawide])
        w.focusWorkspaceOnCurrentMonitor(2)
        #expect(w.activeWorkspace[0] == 2 && w.activeWorkspace[1] == 1)
        w.focusWorkspaceOnCurrentMonitor(7)
        #expect(w.activeWorkspace[0] == 7 && w.workspaces[7]?.monitor == 0)
        w.focusWorkspaceOnCurrentMonitor(1)
        #expect(w.activeWorkspace[0] == 1)
    }

    @Test func focusMonitorWarpsEvenWithNoWarps() {
        let w = world("cursor:no_warps = true", monitors: [laptop, ultrawide])
        w.focusMonitor(1)
        let e = w.takeEffects()
        #expect(w.focusedMonitor == 1)
        #expect(e.contains(.warpCursor(Point(x: 3232, y: 720))))
        w.focusMonitor(1)
        #expect(!w.takeEffects().contains { if case .warpCursor = $0 { return true }; return false })
    }

    @Test func floatingWindowsMoveWithTheirMonitor() {
        let calc = "windowrule = float on, match:class Calculator"
        let a = Rect(x: 100, y: 100, width: 600, height: 400)
        func floatWorld() -> World {
            let w = world(calc, monitors: [laptop, ultrawide])
            _ = w.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50, frame: a)))
            _ = w.takeEffects()
            return w
        }
        let moved = floatWorld()
        moved.moveWindow(5, toWorkspace: 2, silent: false)
        #expect(frames(moved.takeEffects())[5] == Rect(x: 1612, y: 100, width: 600, height: 400))
        moved.moveWindow(5, toWorkspace: 1, silent: true)
        #expect(moved.windows[5]?.floatingFrame == a)

        let workspace = floatWorld()
        workspace.moveWorkspace(1, toMonitor: 1)
        #expect(frames(workspace.takeEffects())[5] == Rect(x: 1612, y: 100, width: 600, height: 400))

        let swapped = floatWorld()
        _ = swapped.handle(.windowAppeared(snap(6, app: "Calculator", bundle: "com.apple.calculator", pid: 60, frame: Rect(x: 2000, y: 300, width: 500, height: 300))))
        swapped.focusMonitor(1)
        _ = swapped.handle(.windowAppeared(snap(7, app: "Calculator", bundle: "com.apple.calculator", pid: 70, frame: Rect(x: 2000, y: 300, width: 500, height: 300))))
        _ = swapped.takeEffects()
        swapped.swapActiveWorkspaces(0, 1)
        let e = frames(swapped.takeEffects())
        #expect(e[5] == Rect(x: 1612, y: 100, width: 600, height: 400))
        #expect(e[7] == Rect(x: 488, y: 300, width: 500, height: 300))
    }

    @Test func specialWorkspaceFloatsFollowItAcrossMonitors() {
        let w = world("windowrule = float on, match:class Calculator", monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50)))
        let special = w.resolveWorkspace(.special("magic"))!
        w.moveWindow(5, toWorkspace: special, silent: false)
        _ = w.takeEffects()
        w.toggleSpecial(special, show: true, on: 1)
        #expect(frames(w.takeEffects())[5] == Rect(x: 1612, y: 100, width: 600, height: 400))
    }

    @Test func unreachableFloatsAreFittedIntoTheirMonitor() {
        let w = world("windowrule = float on, match:class Calculator")
        _ = w.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50)))
        w.windows[5]?.floatingFrame = Rect(x: 2000, y: 300, width: 600, height: 400)
        let e = w.reload(w.config)
        #expect(frames(e)[5] == Rect(x: 912, y: 300, width: 600, height: 400))
        w.windows[5]?.floatingFrame = Rect(x: -5000, y: 2000, width: 5000, height: 5000)
        #expect(frames(w.reload(w.config))[5] == laptop.visibleFrame)
    }

    @Test func floatEchoOfAClampedFrameIsNotStored() {
        let w = world("windowrule = float on, match:class Calculator")
        _ = w.handle(.windowAppeared(snap(5, app: "Calculator", bundle: "com.apple.calculator", pid: 50)))
        w.windows[5]?.floatingFrame = Rect(x: 2000, y: 300, width: 600, height: 400)
        _ = w.reload(w.config)
        let echo = w.handle(.windowFrameChanged(5, Rect(x: 912, y: 300, width: 600, height: 400), userDriven: false))
        #expect(echo.isEmpty)
        #expect(w.windows[5]?.floatingFrame == Rect(x: 2000, y: 300, width: 600, height: 400))
    }

    @Test func previousWorkspaceRoundTripsAcrossMonitors() {
        let w = world(monitors: [laptop, ultrawide])
        _ = w.handle(.windowAppeared(snap(1)))
        w.switchWorkspace(2)
        #expect(w.focusedMonitor == 1)
        #expect(w.resolveWorkspace(.previous) == 1)
        w.switchWorkspace(w.resolveWorkspace(.previous)!)
        #expect(w.focusedMonitor == 0)
        #expect(w.focusedWindow == 1)
        #expect(w.resolveWorkspace(.previous) == 2)
        w.switchWorkspace(w.resolveWorkspace(.previous)!)
        #expect(w.focusedMonitor == 1)
        #expect(w.resolveWorkspace(.previous) == 1)
    }

    @Test func lateFocusEventsForUnknownWindowsAreIgnored() {
        let w = twoWindows()
        #expect(w.focusedWindow == 2)
        #expect(w.handle(.focusChanged(99)).isEmpty)
        #expect(w.focusedWindow == 2)
        _ = w.handle(.windowDisappeared(2))
        #expect(w.focusedWindow == 1)
        #expect(w.handle(.focusChanged(2)).isEmpty)
        #expect(w.focusedWindow == 1)
        _ = w.handle(.focusChanged(nil))
        #expect(w.focusedWindow == nil)
    }

    @Test func focusOnAnIgnoredWindowClearsTheFocus() {
        let w = world("windowrule = ignore on, match:class Raycast")
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, app: "Raycast", bundle: "com.raycast.macos", pid: 200)))
        #expect(w.windows[2] == nil)
        #expect(w.focusedWindow == 1)
        _ = w.handle(.focusChanged(2))
        #expect(w.focusedWindow == nil)
        _ = w.handle(.focusChanged(1))
        #expect(w.focusedWindow == 1)
        _ = w.handle(.windowDisappeared(2))
        _ = w.handle(.focusChanged(2))
        #expect(w.focusedWindow == 1)
    }
}
