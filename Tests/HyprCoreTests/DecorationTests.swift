import Testing
@testable import HyprCore

private let colors = "general {\n border_size = 2\n col.active_border = rgb(ff0000)\n col.inactive_border = rgb(00ff00)\n}\n"

private func run(_ w: World, _ dispatcher: String, _ arguments: String = "") {
    _ = w.run(try! CommandParser.parse(dispatcher: dispatcher, arguments: arguments).get())
}

private func pair(_ text: String) -> World {
    let w = world(colors + text)
    _ = w.handle(.windowAppeared(snap(1)))
    _ = w.handle(.windowAppeared(snap(2, pid: 200)))
    run(w, "focuswindow", "address:0x1")
    return w
}

private func deco(_ w: World, _ id: WindowID) -> Decoration? { w.decorations().windows.first { $0.id == id } }

@Suite struct DecorationTests {
    @Test func theFocusedWindowGetsTheActiveColor() {
        let w = pair("")
        #expect(deco(w, 1)?.isActive == true)
        #expect(deco(w, 1)?.border?.colors.first?.r == 1)
        #expect(deco(w, 2)?.border?.colors.first?.g == 1)
        #expect(deco(w, 1)?.borderWidth == 2)
        #expect(deco(w, 1)?.frame == w.windows[1]?.appliedFrame)
    }

    @Test func aTransparentInactiveColorMeansNoInactiveBorder() {
        let w = pair("general {\n col.inactive_border = rgba(00000000)\n}\n")
        #expect(deco(w, 2)?.border == nil)
        #expect(deco(w, 1)?.border != nil)
    }

    @Test func zeroWidthAndFullscreenMeanNoBorder() {
        let zero = pair("general {\n border_size = 0\n}\n")
        #expect(deco(zero, 1)?.border == nil)
        let full = pair("")
        run(full, "fullscreen", "0")
        #expect(deco(full, 1)?.border == nil)
    }

    @Test func parkedWindowsGetNoDecoration() {
        let w = pair("")
        run(w, "movetoworkspacesilent", "2,address:0x2")
        #expect(deco(w, 2) == nil)
        #expect(deco(w, 1) != nil)
    }

    @Test func rulesAndSetpropOverrideTheBorder() {
        let w = pair("windowrule = border_size 5, match:class Ghostty\n")
        #expect(deco(w, 1)?.borderWidth == 5)
        run(w, "setprop", "address:0x1 border_size 7")
        #expect(deco(w, 1)?.borderWidth == 7)
        run(w, "setprop", "address:0x1 border_color rgb(0000ff)")
        #expect(deco(w, 1)?.border?.colors.first?.b == 1)
    }

    @Test func dimInactiveDimsOnlyInactiveTiledWindows() {
        let w = pair("decoration {\n dim_inactive = true\n dim_strength = 0.3\n}\n")
        #expect(deco(w, 1)?.dim == 0)
        #expect(deco(w, 2)?.dim == 0.3)
        run(w, "setfloating", "address:0x2")
        #expect(deco(w, 2)?.dim == 0)
    }

    @Test func dimAroundListsMatchingVisibleWindows() {
        let w = pair("windowrule = dim_around on, match:class Ghostty\n")
        #expect(w.decorations().dimAround == [1, 2])
        #expect(w.decorations().dimAroundStrength == 0.4)
    }
}
