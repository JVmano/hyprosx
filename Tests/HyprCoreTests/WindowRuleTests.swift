import Testing
@testable import HyprCore

private let here = SourceLocation(file: "/cfg/apps.conf", line: 1)

private func rule(_ v: String, keyword: String = "windowrule") -> WindowRule? {
    WindowRuleParser.parse(keyword: keyword, value: v, location: here).rule
}

private func facts(bundle: String = "com.mitchellh.ghostty", app: String = "Ghostty", title: String = "~",
                   floating: Bool = false, modal: Bool = false, focused: Bool = false) -> WindowFacts {
    WindowFacts(bundleID: bundle, appName: app, title: title, initialTitle: title, isFloating: floating, isFullscreen: false,
                isPinned: false, isFocused: focused, isModal: modal, workspaceID: 1, workspaceName: "1",
                monitorSize: Size(width: 1512, height: 950), windowFrame: Rect(x: 100, y: 100, width: 800, height: 600),
                cursor: Point(x: 50, y: 60))
}

@Suite struct WindowRuleTests {
    @Test func modernInlineForm() {
        let r = rule("float on, match:class .*")
        #expect(r?.effects == [.float(true)])
        #expect(r?.matchers.count == 1)
        let t = rule("match:class com\\.mitchellh\\.ghostty, tile on, match:modal false")
        #expect(t?.effects == [.tile(true)])
        #expect(t?.matchers.count == 2)
    }

    @Test func blockForm() {
        let r = WindowRuleParser.parseBlock([("name", "move-kitty"), ("match:class", "kitty"), ("move", "100 100"), ("animation", "popin")], location: here).rule
        #expect(r?.name == "move-kitty")
        #expect(r?.effects == [.move(ExprPair(x: "100", y: "100")), .animation("popin")])
    }

    @Test func legacyForms() {
        let v51 = rule("float, class:kitty, title:kitty")
        #expect(v51?.effects == [.float(true)])
        #expect(v51?.matchers.count == 2)
        let v2 = rule("noinitialfocus, floating:1, class:^(pavucontrol)$", keyword: "windowrulev2")
        #expect(v2?.effects == [.noInitialFocus(true)])
        #expect(v2?.matchers.contains(.float(true)) == true)
        let v1 = rule("float, ^(kitty)$")
        #expect(v1?.effects == [.float(true)])
        #expect(rule("noborder, class:x")?.effects == [.borderSize(0)])
    }

    @Test func effectsWithArguments() {
        #expect(rule("workspace 2 silent, match:class x")?.effects == [.workspace("2", silent: true)])
        #expect(rule("workspace unset, match:class x")?.effects == [.workspaceUnset])
        #expect(rule("size 800 600, match:class x")?.effects == [.size(ExprPair(x: "800", y: "600"))])
        #expect(rule("opacity 0.8, match:class x")?.effects == [.accepted("opacity")])
        let bc = rule("border_color rgb(FF0000) rgb(880808), match:fullscreen 1")?.effects.first
        if case .borderColor(let a, let i) = bc { #expect(a.colors.count == 1 && i?.colors.count == 1) } else { Issue.record("no border color") }
    }

    @Test func diagnostics() {
        func msg(_ v: String) -> String? { WindowRuleParser.parse(keyword: "windowrule", value: v, location: here).diagnostics.first?.message }
        #expect(msg("float on") == "rule needs at least one match prop")
        #expect(msg("float on, match:class a, match:class b") == "duplicate rule prop 'class'")
        #expect(msg("float on, match:bogus a") == "invalid rule prop 'bogus'")
        #expect(msg("explode, match:class a") == "invalid rule effect 'explode'")
        #expect(msg("float on, match:class (") == "invalid regex '('")
    }

    @Test func classMatchesBundleIdOrAppName() {
        let byId = rule("tile on, match:class com\\.mitchellh\\.ghostty")!
        let byName = rule("tile on, match:class Ghostty")!
        #expect(RuleEngine.matches(byId, facts()))
        #expect(RuleEngine.matches(byName, facts()))
        #expect(!RuleEngine.matches(rule("tile on, match:class ghost")!, facts()))
    }

    @Test func appWithoutBundleIdMatchesByName() {
        let r = rule("float on, match:class Minecraft")!
        #expect(RuleEngine.matches(r, facts(bundle: "", app: "Minecraft")))
        #expect(!RuleEngine.matches(rule("float on, match:class ")!, facts(bundle: "", app: "Minecraft")))
    }

    @Test func negativeRegexAndUnicodeTitles() {
        #expect(RuleEngine.matches(rule("float on, match:class negative:kitty")!, facts()))
        #expect(!RuleEngine.matches(rule("float on, match:class negative:kitty")!, facts(bundle: "net.kovidgoyal.kitty", app: "kitty")))
        #expect(RuleEngine.matches(rule("float on, match:title .*日本語.*")!, facts(title: "メモ 日本語 \"q\" \\ 🎉")))
    }

    @Test func lastMatchWinsAndNamedRulesFirst() {
        let rules = [
            rule("float on, match:class .*")!,
            rule("tile on, match:class Ghostty, match:modal false")!,
            WindowRuleParser.parseBlock([("name", "named"), ("match:class", ".*"), ("float", "on")], location: SourceLocation(file: "/x", line: 99)).rule!,
        ]
        #expect(RuleEngine.ordered(rules).first?.name == "named")
        #expect(RuleEngine.staticOutcome(rules, facts()).floating == false)
        #expect(RuleEngine.staticOutcome(rules, facts(modal: true)).floating == true)
        #expect(RuleEngine.staticOutcome(rules, facts(bundle: "com.apple.calculator", app: "Calculator")).floating == true)
    }

    @Test func ignoreWorkspaceAndMatchedLines() {
        let rules = [rule("ignore on, match:class Raycast")!, rule("workspace 3 silent, match:class Raycast")!]
        let o = RuleEngine.staticOutcome(rules, facts(bundle: "com.raycast.macos", app: "Raycast"))
        #expect(o.ignore)
        #expect(o.workspace == WorkspaceTarget(selector: "3", silent: true))
        #expect(o.matched.count == 2)
    }

    @Test func dynamicOutcomeUsesFocus() {
        let rules = [rule("border_size 4, match:focus true")!, rule("no_anim on, match:class Ghostty")!]
        #expect(RuleEngine.dynamicOutcome(rules, facts(focused: true)).borderSize == 4)
        #expect(RuleEngine.dynamicOutcome(rules, facts(focused: false)).borderSize == nil)
        #expect(RuleEngine.dynamicOutcome(rules, facts()).noAnim)
    }

    @Test func expressions() {
        let vars = ["monitor_w": 1000.0, "window_w": 200.0]
        #expect(RuleEngine.evaluate("monitor_w*0.5", axisLength: 1000, variables: vars) == 500)
        #expect(RuleEngine.evaluate("(monitor_w-window_w)/2", axisLength: 1000, variables: vars) == 400)
        #expect(RuleEngine.evaluate("-10+5", axisLength: 1000, variables: vars) == -5)
        #expect(RuleEngine.evaluate("25%", axisLength: 1000, variables: vars) == 250)
        #expect(RuleEngine.evaluate("bogus", axisLength: 1000, variables: vars) == nil)
        let p = RuleEngine.resolveMove(ExprPair(x: "monitor_w-window_w", y: "20"), facts())
        #expect(p == Point(x: 712, y: 20))
    }
}

@Suite struct WindowRuleHardeningTests {
    @Test func regexCannotEscapeItsAnchors() {
        #expect(RuleRegex("a)|(b") == nil)
        #expect(RuleRegex("abc\\") == nil)
        #expect(RuleRegex("(?i)kitty")?.matches("KITTY") == true)
    }

    @Test func expressionsRejectNonFiniteResults() {
        let v = ["big": 1e200]
        #expect(RuleEngine.evaluate("nan%", axisLength: 1000, variables: v) == nil)
        #expect(RuleEngine.evaluate("inf%", axisLength: 1000, variables: v) == nil)
        #expect(RuleEngine.evaluate("1e999%", axisLength: 1000, variables: v) == nil)
        #expect(RuleEngine.evaluate("big*big", axisLength: 1000, variables: v) == nil)
        #expect(RuleEngine.evaluate(String(repeating: "9", count: 400), axisLength: 1000, variables: v) == nil)
        #expect(RuleEngine.resolveMove(ExprPair(x: "nan%", y: "1"), facts()) == nil)
        #expect(RuleEngine.resolveSize(ExprPair(x: "1", y: "big*big"), facts()) == nil)
    }

    @Test func deeplyNestedExpressionsAreRejectedNotCrashed() {
        let parens = String(repeating: "(", count: 100_000) + "1" + String(repeating: ")", count: 100_000)
        #expect(RuleEngine.evaluate(parens, axisLength: 1000, variables: [:]) == nil)
        #expect(RuleEngine.evaluate(String(repeating: "-", count: 100_000) + "1", axisLength: 1000, variables: [:]) == nil)
        #expect(RuleEngine.evaluate("((((1))))", axisLength: 1000, variables: [:]) == 1)
    }

    @Test func numericEffectsAreRangeChecked() {
        #expect(rule("border_size 99999999999999, match:class x") == nil)
        #expect(rule("border_size -1, match:class x") == nil)
        #expect(rule("border_size 2147483647, match:class x")?.effects == [.borderSize(2147483647)])
        #expect(rule("min_size -5 10, match:class x") == nil)
        #expect(rule("max_size 1e300 10, match:class x") == nil)
        #expect(rule("max_size nan 10, match:class x") == nil)
        #expect(rule("min_size 100 200, match:class x")?.effects == [.minSize(Size(width: 100, height: 200))])
    }

    @Test func badBoolOnDroppedPropIsAnError() {
        #expect(rule("float on, match:xwayland maybe") == nil)
        #expect(rule("float on, match:group maybe") == nil)
        #expect(rule("float on, match:xwayland false, match:class x")?.matchers.count == 1)
    }
}
