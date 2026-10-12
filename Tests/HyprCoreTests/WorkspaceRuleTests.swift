import Testing
@testable import HyprCore

private let here = SourceLocation(file: "/cfg/hyprland.conf", line: 4)
private func ws(_ id: Int, name: String? = nil, special: Bool = false, monitor: String = "Built-in Retina Display",
                tiled: Int = 0, floating: Int = 0, fullscreen: Int = -1) -> WorkspaceFacts {
    WorkspaceFacts(id: id, name: name ?? String(id), isSpecial: special, monitorName: monitor, tiledCount: tiled,
                   floatingCount: floating, fullscreenMode: fullscreen)
}

@Suite struct WorkspaceRuleTests {
    @Test func parsesRules() {
        let r = WorkspaceRule.parse("1, monitor:0, default:true, gapsout:20, layoutopt:orientation:top, layout:master", location: here)
        #expect(r.diagnostics.isEmpty)
        #expect(r.rule?.selector == .id(1))
        #expect(r.rule?.monitor == "0")
        #expect(r.rule?.isDefault == true)
        #expect(r.rule?.gapsOut == Edges(all: 20))
        #expect(r.rule?.orientation == "top")
        #expect(r.rule?.layout == "master")
    }

    @Test func monitorDescriptionKeepsColons() {
        #expect(WorkspaceRule.parse("name:gaming, monitor:desc:PHL 499P9", location: here).rule?.monitor == "desc:PHL 499P9")
    }

    @Test func smartGapsFilters() {
        let tv1 = WorkspaceRule.parse("w[tv1], gapsout:0, gapsin:0", location: here).rule!
        #expect(tv1.matches(ws(1, tiled: 1), monitorMatches: { _ in true }))
        #expect(!tv1.matches(ws(1, tiled: 2), monitorMatches: { _ in true }))
        let f1 = WorkspaceRule.parse("f[1], gapsout:0", location: here).rule!
        #expect(f1.matches(ws(2, tiled: 3, fullscreen: 1), monitorMatches: { _ in true }))
        let combo = WorkspaceRule.parse("w[tv1]s[false], gapsout:0", location: here).rule!
        #expect(!combo.matches(ws(-99, name: "special", special: true, tiled: 1), monitorMatches: { _ in true }))
    }

    @Test func idNameSpecialAndMonitorFilters() {
        #expect(WorkspaceRule.parse("3, bordersize:0", location: here).rule!.matches(ws(3), monitorMatches: { _ in true }))
        #expect(WorkspaceRule.parse("name:web, persistent:true", location: here).rule!.matches(ws(1000000, name: "web"), monitorMatches: { _ in true }))
        #expect(WorkspaceRule.parse("special:magic, gapsout:50", location: here).rule!.matches(ws(-98, name: "magic", special: true), monitorMatches: { _ in true }))
        let m = WorkspaceRule.parse("m[1], gapsout:20", location: here).rule!
        #expect(m.matches(ws(4), monitorMatches: { $0 == "1" }))
        #expect(!m.matches(ws(4), monitorMatches: { _ in false }))
        #expect(WorkspaceRule.parse("r[1-5], gapsout:20", location: here).rule!.matches(ws(5), monitorMatches: { _ in true }))
    }

    @Test func acceptedAndInvalid() {
        #expect(WorkspaceRule.parse("2, rounding:false, shadow:false", location: here).diagnostics.isEmpty)
        #expect(WorkspaceRule.parse("2, wobble:true", location: here).diagnostics.first?.message == "invalid workspace rule 'wobble'")
        #expect(WorkspaceRule.parse("x[1], gapsin:0", location: here).diagnostics.first?.message == "invalid workspace selector 'x[1]'")
    }

    @Test func commasInsideBracketsDoNotSplit() {
        let r = WorkspaceRule.parse("n[s:a,b], gapsout:5", location: here)
        #expect(r.diagnostics.isEmpty)
        #expect(r.rule?.selector == .filters([.nameStarts("a,b")]))
        #expect(r.rule?.gapsOut == Edges(all: 5))
    }

    @Test func outOfRangeIdsAndCountsAreErrorsNotTraps() {
        for bad in ["99999999999", "9223372036854775807", "r[1-99999999999]", "w[t99999999999]", "f[99999999999999999999]"] {
            let r = WorkspaceRule.parse("\(bad), gapsout:0", location: here)
            #expect(r.rule == nil, "\(bad)")
            #expect(r.diagnostics.first?.message == "invalid workspace selector '\(bad)'", "\(bad)")
        }
    }

    @Test func invertedAndMalformedRangesAreErrors() {
        for bad in ["r[5-1]", "r[5]", "r[-1-5]", "r[a-b]", "r[1-2-3]", "w[t3-1]", "w[t-1]", "w[t]", "w[]", "w[t1-]"] {
            #expect(WorkspaceRule.parse("\(bad), gapsout:0", location: here).rule == nil, "\(bad)")
        }
    }

    @Test func directlyBuiltInvertedRangesMatchNothing() {
        var rule = WorkspaceRule.parse("1, gapsout:0", location: here).rule!
        rule.selector = .filters([.idRange(5, 1)])
        #expect(!rule.matches(ws(3), monitorMatches: { _ in true }))
        rule.selector = .filters([.windowCount(tiled: true, floating: false, min: 3, max: 1)])
        #expect(!rule.matches(ws(3, tiled: 2), monitorMatches: { _ in true }))
    }

    @Test func windowCountFlagsPickTheCountedWindows() {
        let facts = ws(1, tiled: 2, floating: 1)
        let any = { (_: String) in true }
        #expect(WorkspaceRule.parse("w[t2], gapsout:0", location: here).rule!.matches(facts, monitorMatches: any))
        #expect(WorkspaceRule.parse("w[f1], gapsout:0", location: here).rule!.matches(facts, monitorMatches: any))
        #expect(WorkspaceRule.parse("w[3], gapsout:0", location: here).rule!.matches(facts, monitorMatches: any))
        #expect(WorkspaceRule.parse("w[tfgp3], gapsout:0", location: here).rule!.matches(facts, monitorMatches: any))
        #expect(WorkspaceRule.parse("w[1-3], gapsout:0", location: here).rule!.matches(facts, monitorMatches: any))
        #expect(!WorkspaceRule.parse("w[4-9], gapsout:0", location: here).rule!.matches(facts, monitorMatches: any))
    }

    @Test func invalidRuleValuesGiveDiagnostics() {
        let cases: [(String, String)] = [
            ("1, default:maybe", "invalid value 'maybe' for default"),
            ("1, persistent:x", "invalid value 'x' for persistent"),
            ("1, border:x", "invalid value 'x' for border"),
            ("1, bordersize:-3", "invalid value '-3' for bordersize"),
            ("1, bordersize:99999999999", "invalid value '99999999999' for bordersize"),
            ("1, bordersize:0xFFFFFFFFFFFFFFF", "invalid value '0xFFFFFFFFFFFFFFF' for bordersize"),
            ("1, gapsout:nan", "invalid value 'nan' for gapsout"),
            ("1, gapsin:inf", "invalid value 'inf' for gapsin"),
            ("1, gapsin:1e300", "invalid value '1e300' for gapsin"),
            ("1, gapsout:1 2 3 4 5", "invalid value '1 2 3 4 5' for gapsout"),
        ]
        for (value, message) in cases {
            let r = WorkspaceRule.parse(value, location: here)
            #expect(r.rule?.selector == .id(1), "\(value)")
            #expect(r.diagnostics.map(\.message) == [message], "\(value)")
        }
        let none = WorkspaceRule.parse("1, default:maybe, bordersize:-3, gapsout:nan", location: here).rule!
        #expect(none.isDefault == nil && none.borderSize == nil && none.gapsOut == nil)
    }

    @Test func validNumbersAndEdges() {
        let r = WorkspaceRule.parse("1, bordersize:3, border:false, gapsin:5 10, gapsout:1 2 3 4", location: here)
        #expect(r.diagnostics.isEmpty)
        #expect(r.rule?.borderSize == 3)
        #expect(r.rule?.border == false)
        #expect(r.rule?.gapsIn == Edges(top: 5, right: 10, bottom: 5, left: 10))
        #expect(r.rule?.gapsOut == Edges(top: 1, right: 2, bottom: 3, left: 4))
    }

    @Test func layoutoptAndRemainingKeys() {
        let r = WorkspaceRule.parse("2, defaultName:main, on-created-empty:open -a Ghostty, layoutopt:mfact:0.6", location: here)
        #expect(r.rule?.defaultName == "main")
        #expect(r.rule?.onCreatedEmpty == "open -a Ghostty")
        #expect(r.rule?.orientation == nil)
        #expect(r.diagnostics.map(\.message) == ["unsupported workspace layoutopt 'mfact'"])
        #expect(r.diagnostics.first?.isWarning == true)
    }

    @Test func emptyAndSpecialSelectors() {
        #expect(WorkspaceRule.parse("", location: here).diagnostics.first?.message == "invalid workspace selector ''")
        #expect(WorkspaceRule.parse("special, gapsout:0", location: here).rule?.selector == .special(nil))
        let plain = WorkspaceRule.parse("special, gapsout:0", location: here).rule!
        #expect(plain.matches(ws(-99, name: "special", special: true), monitorMatches: { _ in true }))
        #expect(!plain.matches(ws(1), monitorMatches: { _ in true }))
        let named = WorkspaceRule.parse("name:web, gapsout:0", location: here).rule!
        #expect(!named.matches(ws(-98, name: "web", special: true), monitorMatches: { _ in true }))
    }
}
