import Testing
import Foundation
@testable import HyprCore

@Suite struct KeyTapMatcherTests {
    func bind(_ line: String, submap: String = "") -> Bind {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return BindParser.parse(keyword: parts[0], value: parts[1], submap: submap, location: HyprCore.SourceLocation(file: "t.conf", line: 1)).bind!
    }

    func matcher(_ lines: [String]) -> KeyTapMatcher {
        var m = KeyTapMatcher()
        m.setGroups(HotkeyPlan.groups(lines.map { bind($0) }))
        return m
    }

    let h: UInt16 = 0x04
    let l: UInt16 = 0x25

    @Test func steadyHoldOfBindeRepeatsThenReleases() {
        var m = matcher(["binde = ALT SHIFT, l, resizeactive, 40 0"])
        let down = m.handle(.keyDown, keyCode: l, modifiers: [.option, .shift], autorepeat: false)
        #expect(down.consume && down.binds.map(\.dispatcher) == ["resizeactive"])
        for _ in 0..<3 {
            let again = m.handle(.keyDown, keyCode: l, modifiers: [.option, .shift], autorepeat: true)
            #expect(again.consume && again.binds.map(\.dispatcher) == ["resizeactive"])
        }
        let up = m.handle(.keyUp, keyCode: l, modifiers: [.option, .shift], autorepeat: false)
        #expect(up.consume && up.binds.isEmpty)
        #expect(!m.handle(.keyUp, keyCode: l, modifiers: [], autorepeat: false).consume)
    }

    @Test func autorepeatOfNonRepeatingGroupIsConsumedWithoutRunning() {
        var m = matcher(["bind = ALT, h, movefocus, l"])
        #expect(m.handle(.keyDown, keyCode: h, modifiers: .option, autorepeat: false).binds.count == 1)
        let again = m.handle(.keyDown, keyCode: h, modifiers: .option, autorepeat: true)
        #expect(again.consume && again.binds.isEmpty)
    }

    @Test func releaseBindsRunOnKeyUpEvenAfterOptionIsReleasedFirst() {
        var m = matcher(["bindr = ALT, h, exec, true"])
        let down = m.handle(.keyDown, keyCode: h, modifiers: .option, autorepeat: false)
        #expect(down.consume && down.binds.isEmpty)
        let up = m.handle(.keyUp, keyCode: h, modifiers: [], autorepeat: false)
        #expect(up.consume && up.binds.map(\.dispatcher) == ["exec"])
    }

    @Test func holdAcrossSwapToEmptyTableStaysConsumed() {
        var m = matcher(["bind = ALT, r, submap, resize"])
        #expect(m.handle(.keyDown, keyCode: 0x0F, modifiers: .option, autorepeat: false).consume)
        m.setGroups([])
        let again = m.handle(.keyDown, keyCode: 0x0F, modifiers: .option, autorepeat: true)
        #expect(again.consume && again.binds.isEmpty)
        let up = m.handle(.keyUp, keyCode: 0x0F, modifiers: [], autorepeat: false)
        #expect(up.consume && up.binds.isEmpty)
        #expect(!m.handle(.keyUp, keyCode: 0x0F, modifiers: [], autorepeat: false).consume)
    }

    @Test func missedKeyUpDoesNotSwallowALaterPlainPress() {
        var m = matcher(["bind = ALT, h, movefocus, l"])
        #expect(m.handle(.keyDown, keyCode: h, modifiers: .option, autorepeat: false).consume)
        #expect(!m.handle(.keyDown, keyCode: h, modifiers: [], autorepeat: false).consume)
        #expect(!m.handle(.keyUp, keyCode: h, modifiers: [], autorepeat: false).consume)
    }

    @Test func shiftReleasedDuringHoldKeepsRepeatingTheHeldGroup() {
        var m = matcher(["binde = ALT SHIFT, l, resizeactive, 40 0", "bind = ALT, l, movefocus, r"])
        #expect(m.handle(.keyDown, keyCode: l, modifiers: [.option, .shift], autorepeat: false).consume)
        let again = m.handle(.keyDown, keyCode: l, modifiers: .option, autorepeat: true)
        #expect(again.consume && again.binds.map(\.dispatcher) == ["resizeactive"])
        #expect(m.handle(.keyUp, keyCode: l, modifiers: .option, autorepeat: false).consume)
    }

    @Test func autorepeatWithoutKeyDownAdoptsAMatchingGroup() {
        var m = matcher(["binde = ALT, l, resizeactive, 40 0"])
        let again = m.handle(.keyDown, keyCode: l, modifiers: .option, autorepeat: true)
        #expect(again.consume && again.binds.count == 1)
        #expect(m.handle(.keyUp, keyCode: l, modifiers: [], autorepeat: false).consume)
    }

    @Test func nonMatchingEventsAreNeverConsumed() {
        var m = matcher(["bind = ALT, h, movefocus, l"])
        let events: [(KeyTapMatcher.Kind, UInt16, Modifiers, Bool)] = [
            (.keyDown, 0x04, [], false), (.keyDown, 0x04, [.option, .command], false), (.keyDown, 0x04, [.option, .shift], false),
            (.keyDown, 0x04, [], true), (.keyUp, 0x04, .option, false), (.keyDown, 0x00, .option, false), (.keyUp, 0x00, [], false),
        ]
        for (kind, code, mods, repeated) in events {
            let decision = m.handle(kind, keyCode: code, modifiers: mods, autorepeat: repeated)
            #expect(!decision.consume && decision.binds.isEmpty)
        }
    }

    @Test func resetForgetsHeldKeys() {
        var m = matcher(["bind = ALT, h, movefocus, l"])
        _ = m.handle(.keyDown, keyCode: h, modifiers: .option, autorepeat: false)
        m.reset()
        #expect(!m.handle(.keyUp, keyCode: h, modifiers: [], autorepeat: false).consume)
        #expect(m.handle(.keyDown, keyCode: h, modifiers: .option, autorepeat: false).consume)
    }
}
