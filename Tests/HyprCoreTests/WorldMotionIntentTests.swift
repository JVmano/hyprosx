import Testing
@testable import HyprCore

private func run(_ w: World, _ dispatcher: String, _ arguments: String = "") -> [Effect] {
    w.run(try! CommandParser.parse(dispatcher: dispatcher, arguments: arguments).get()).effects
}

private func slides(_ effects: [Effect]) -> [WindowID: SlideOut?] {
    var out: [WindowID: SlideOut?] = [:]
    for case .park(let parks) in effects { for p in parks { out[p.id] = p.slide } }
    return out
}

private func twoWorkspaces(_ text: String = "") -> World {
    let w = world(text)
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    _ = run(w, "movetoworkspacesilent", "2,address:0x2")
    return w
}

@Suite struct WorldMotionIntentTests {
    @Test func aSwitchToAHigherIDSlidesLeftAndTagsTheParks() {
        let w = twoWorkspaces()
        let e = run(w, "workspace", "2")
        #expect(reasons(e)[2] == .workspaceIn(leftward: true))
        #expect(slides(e)[1] == .workspace(leftward: true))
    }

    @Test func aSwitchToALowerIDSlidesRight() {
        let w = twoWorkspaces()
        _ = run(w, "workspace", "2")
        let e = run(w, "workspace", "1")
        #expect(reasons(e)[1] == .workspaceIn(leftward: false))
        #expect(slides(e)[2] == .workspace(leftward: false))
    }

    @Test func wraparoundTreatsLastToFirstAsForward() {
        let w = twoWorkspaces("animations {\n workspace_wraparound = true\n}\n")
        _ = run(w, "movetoworkspacesilent", "3,address:0x2")
        _ = run(w, "workspace", "3")
        let e = run(w, "workspace", "1")
        #expect(reasons(e)[1] == .workspaceIn(leftward: true))
    }

    @Test func specialWorkspacesUseTheirOwnIntent() {
        let w = twoWorkspaces()
        _ = run(w, "movetoworkspacesilent", "special:magic,address:0x2")
        let shown = run(w, "togglespecialworkspace", "magic")
        #expect(reasons(shown)[2] == .specialIn)
        let hidden = run(w, "togglespecialworkspace", "magic")
        #expect(slides(hidden)[2] == .special)
    }

    @Test func aSpecialHiddenByAWorkspaceSwitchGlidesOut() {
        let w = twoWorkspaces("binds {\n hide_special_on_workspace_change = true\n}\n")
        _ = run(w, "movetoworkspacesilent", "special:magic,address:0x2")
        _ = run(w, "togglespecialworkspace", "magic")
        let e = run(w, "workspace", "2")
        #expect(slides(e)[2] == .special)
    }

    @Test func plainParksCarryNoSlide() {
        let w = twoWorkspaces()
        let e = run(w, "movetoworkspacesilent", "3,address:0x1")
        #expect(slides(e)[1] == .some(nil))
    }

    @Test func aUserResizeTagsTheNeighboursAsManual() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        _ = w.handle(.windowAppeared(snap(2, pid: 200)))
        let a = w.windows[1]!.appliedFrame!
        let e = w.handle(.windowFrameChanged(1, Rect(x: a.x, y: a.y, width: a.width - 100, height: a.height), userDriven: true))
        #expect(reasons(e)[2] == .manualResize)
    }

    @Test func motionReadsRulesAndSetprop() {
        let w = world("windowrule = animation popin 50%, match:class Ghostty\n")
        _ = w.handle(.windowAppeared(snap(1)))
        #expect(w.motion(for: 1) == WindowMotion(noAnim: false, style: "popin 50%"))
        _ = run(w, "setprop", "address:0x1 no_anim 1")
        #expect(w.motion(for: 1).noAnim)
        let r = world("windowrule = no_anim on, match:class Ghostty\n")
        _ = r.handle(.windowAppeared(snap(1)))
        #expect(r.motion(for: 1).noAnim)
    }

    @Test func monitorFrameFollowsTheWorkspaceMonitor() {
        let w = world()
        _ = w.handle(.windowAppeared(snap(1)))
        #expect(w.monitorFrame(of: 1) == laptop.frame)
        #expect(w.monitorFrame(of: 99) == nil)
    }
}
