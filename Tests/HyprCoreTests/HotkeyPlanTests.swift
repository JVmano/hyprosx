import Testing
import Foundation
@testable import HyprCore

@Suite struct HotkeyPlanTests {
    func bind(_ line: String, submap: String = "") -> Bind {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return BindParser.parse(keyword: parts[0], value: parts[1], submap: submap, location: SourceLocation(file: "t.conf", line: 1)).bind!
    }

    @Test func groupsByKeyInFileOrder() {
        let groups = HotkeyPlan.groups([
            bind("bind = ALT, H, movefocus, l"),
            bind("bind = CTRL CMD, 1, setfloating"),
            bind("bind = CTRL CMD, 1, resizeactive, exact 33% 100%"),
            bind("bindr = ALT, H, exec, true"),
            bind("binde = ALT SHIFT, minus, resizeactive, -50 0"),
            bind("bindm = CTRL ALT, mouse:272, movewindow"),
            bind("bind = CTRL ALT, mouse_down, workspace, e+1"),
        ])
        #expect(groups.count == 3)
        #expect(groups[0].modifiers == .option && groups[0].keyCode == 0x04)
        #expect(groups[0].press.map(\.dispatcher) == ["movefocus"])
        #expect(groups[0].release.map(\.dispatcher) == ["exec"])
        #expect(!groups[0].repeats)
        #expect(groups[1].press.map(\.dispatcher) == ["setfloating", "resizeactive"])
        #expect(groups[2].keyCode == 0x1B && groups[2].repeats)
    }

    @Test func sameKeyWithOtherModifiersIsAnotherGroup() {
        let groups = HotkeyPlan.groups([bind("bind = ALT, 1, workspace, 1"), bind("bind = ALT SHIFT, 1, movetoworkspace, 1")])
        #expect(groups.map(\.modifiers) == [.option, [.option, .shift]])
    }

    @Test func carbonModifierMask() {
        #expect(HotkeyPlan.carbonModifiers([.command, .shift]) == 0x0100 | 0x0200)
        #expect(HotkeyPlan.carbonModifiers([.option, .control]) == 0x0800 | 0x1000)
        #expect(HotkeyPlan.carbonModifiers([]) == 0)
    }

    @Test func ownerConfigSampleGroupsExactly() {
        let groups = HotkeyPlan.groups([
            bind("bind = ALT, h, movefocus, l"),
            bind("bind = ALT SHIFT, h, movewindow, l"),
            bind("bind = ALT, 1, workspace, 1"),
            bind("bind = ALT SHIFT, 1, movetoworkspace, 1"),
            bind("bind = CTRL CMD, 1, workspace, 1"),
            bind("bind = CTRL CMD, 1, movecurrentworkspacetomonitor, 0"),
            bind("bind = CTRL CMD, 1, focusmonitor, 0"),
            bind("bind = ALT, slash, togglesplit"),
            bind("bind = ALT, space, togglefloating"),
            bind("bind = CTRL ALT, left, workspace, e-1"),
            bind("bind = CTRL ALT, right, workspace, e+1"),
            bind("bind = ALT, r, submap, resize"),
            bind("binde = , h, resizeactive, -40 0", submap: "resize"),
            bind("binde = , l, resizeactive, 40 0", submap: "resize"),
            bind("bind = , Escape, submap, reset", submap: "resize"),
            bind("bind = , Return, submap, reset", submap: "resize"),
        ])
        #expect(groups.map(\.keyCode) == [0x04, 0x04, 0x12, 0x12, 0x12, 0x2C, 0x31, 0x7B, 0x7C, 0x0F, 0x04, 0x25, 0x35, 0x24])
        #expect(groups.map(\.modifiers) == [
            .option, [.option, .shift], .option, [.option, .shift], [.control, .command], .option, .option,
            [.control, .option], [.control, .option], .option, [], [], [], [],
        ])
        #expect(groups[4].press.map(\.dispatcher) == ["workspace", "movecurrentworkspacetomonitor", "focusmonitor"])
        #expect(groups[4].press.map(\.arguments) == ["1", "0", "0"])
        #expect(groups.map(\.repeats) == [false, false, false, false, false, false, false, false, false, false, true, true, false, false])
        #expect(groups.allSatisfy { $0.release.isEmpty })
    }

    @Test func submapKeysWithoutModifiersGroupApart() {
        let groups = HotkeyPlan.groups([
            bind("binde = , h, resizeactive, -40 0", submap: "resize"),
            bind("bind = ALT, h, movefocus, l"),
        ])
        #expect(groups.map(\.modifiers) == [[], .option])
        #expect(groups.map(\.repeats) == [true, false])
    }
}
