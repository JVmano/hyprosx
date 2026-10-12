import Testing
@testable import HyprCore

@Suite struct AnimationTests {
    @Test func bezierEndpointsAndClamping() {
        let b = Bezier(p1: Point(x: 0.23, y: 1), p2: Point(x: 0.32, y: 1))
        #expect(b.y(at: 0) == 0)
        #expect(b.y(at: 1) == 1)
        #expect(b.y(at: -1) == 0)
        #expect(b.y(at: 2) == 1)
    }

    @Test func bezierMatchesHandComputedPoint() {
        let b = Bezier(p1: Point(x: 0.23, y: 1), p2: Point(x: 0.32, y: 1))
        #expect(abs(b.y(at: 0.33125) - 0.875) < 0.005)
        let linear = Bezier.builtIns["linear"]!
        #expect(abs(linear.y(at: 0.3) - 0.3) < 0.002)
    }

    @Test func overshootCurveExceedsOne() {
        let b = Bezier(p1: Point(x: 0.05, y: 0.9), p2: Point(x: 0.1, y: 1.1))
        #expect(stride(from: 0.0, through: 1.0, by: 0.01).contains { b.y(at: $0) > 1 })
    }

    @Test func defaultCurveIsBuiltIn() {
        #expect(Bezier.builtIns["default"] == Bezier(p1: Point(x: 0, y: 0.75), p2: Point(x: 0.15, y: 1)))
    }

    @Test func parseBezierLine() {
        let r = Bezier.parse("easeOutQuint,   0.23, 1,    0.32, 1")
        #expect(r?.name == "easeOutQuint")
        #expect(r?.curve == Bezier(p1: Point(x: 0.23, y: 1), p2: Point(x: 0.32, y: 1)))
        #expect(Bezier.parse("bad, 1, 2") == nil)
    }

    @Test func treeDefaults() {
        let t = AnimationTree()
        #expect(t.leaf("windowsIn") == AnimationLeaf(enabled: true, speed: 8, curve: "default", style: ""))
        #expect(t.leaf("borderangle").enabled == false)
        #expect(t.leaf("windowsMove").durationMs == 800)
    }

    @Test func inheritanceIsAllOrNothing() {
        var t = AnimationTree()
        let curves: Set<String> = ["default", "linear", "easeOutQuint"]
        #expect(t.apply("windows, 1, 4.79, easeOutQuint", curves: curves) == nil)
        #expect(t.apply("windowsIn, 1, 4.1, easeOutQuint, popin 87%", curves: curves) == nil)
        #expect(t.leaf("windowsMove") == AnimationLeaf(enabled: true, speed: 4.79, curve: "easeOutQuint", style: ""))
        #expect(t.leaf("windowsIn").style == "popin 87%")
        #expect(t.leaf("windowsOut").speed == 4.79)
        #expect(t.leaf("workspacesIn").speed == 8)
    }

    @Test func disabledLeafNeedsNoMoreFields() {
        var t = AnimationTree()
        #expect(t.apply("fade, 0", curves: ["default"]) == nil)
        #expect(t.leaf("fadeIn").enabled == false)
    }

    @Test func validation() {
        var t = AnimationTree()
        let c: Set<String> = ["default"]
        #expect(t.apply("windowz, 1, 3, default", curves: c) == "no such animation 'windowz'")
        #expect(t.apply("windows, 1, 0, default", curves: c) == "animation speed must be positive")
        #expect(t.apply("windows, 1, 3, nope", curves: c) == "no such bezier 'nope'")
        #expect(t.apply("windows, 1, 3, default, wobble", curves: c) == "invalid animation style 'wobble' for windows")
        #expect(t.apply("workspaces, 1, 3, default, slidefade 20%", curves: c) == nil)
        #expect(t.apply("borderangle, 1, 30, default, loop", curves: c) == nil)
        #expect(t.apply("workspaces, 1, 3, default, slide top", curves: c) == nil)
    }

    @Test func bundledAndOwnerConfigLinesApplyWithoutErrors() {
        let bezierLines = [
            "easeOutQuint, 0.23, 1, 0.32, 1",
            "easeInOutCubic, 0.65, 0.05, 0.36, 1",
            "linear, 0, 0, 1, 1",
            "almostLinear, 0.5, 0.5, 0.75, 1",
            "quick, 0.15, 0, 0.1, 1",
        ]
        let animationLines = [
            "global, 1, 10, default",
            "border, 1, 5.39, easeOutQuint",
            "windows, 1, 4.79, easeOutQuint",
            "windowsIn, 1, 4.1, easeOutQuint, popin 87%",
            "windowsOut, 1, 1.49, linear, popin 87%",
            "fadeIn, 1, 1.73, almostLinear",
            "fadeOut, 1, 1.46, almostLinear",
            "fade, 1, 3.03, quick",
            "workspaces, 1, 1.94, almostLinear, fade",
            "workspacesIn, 1, 1.21, almostLinear, fade",
            "workspacesOut, 1, 1.94, almostLinear, fade",
        ]
        var curves = Set(Bezier.builtIns.keys)
        for line in bezierLines {
            let parsed = Bezier.parse(line)
            #expect(parsed != nil, "\(line)")
            if let parsed { curves.insert(parsed.name) }
        }
        #expect(curves == ["default", "linear", "easeOutQuint", "easeInOutCubic", "almostLinear", "quick"])
        var tree = AnimationTree()
        for line in animationLines {
            #expect(tree.apply(line, curves: curves) == nil, "\(line)")
        }
        #expect(tree.leaf("global").speed == 10)
        #expect(tree.leaf("windowsOut") == AnimationLeaf(enabled: true, speed: 1.49, curve: "linear", style: "popin 87%"))
        #expect(tree.leaf("fadeSwitch") == AnimationLeaf(enabled: true, speed: 3.03, curve: "quick", style: ""))
        #expect(tree.leaf("specialWorkspaceIn").speed == 1.94)
        #expect(tree.leaf("borderangle").enabled == false)
    }

    @Test func bezierRejectsNonFiniteAbsurdAndMalformedNumbers() {
        #expect(Bezier.parse("c, nan, 0, 1, 1") == nil)
        #expect(Bezier.parse("c, 0, inf, 1, 1") == nil)
        #expect(Bezier.parse("c, 0, 0, -infinity, 1") == nil)
        #expect(Bezier.parse("c, 1e308, 0, 1, 1") == nil)
        #expect(Bezier.parse("c, 0, 0, 1, 2.5") == nil)
        #expect(Bezier.parse("c, 0, -1.5, 1, 1") == nil)
        #expect(Bezier.parse("c, 0, 0, 1, 1, 1") == nil)
        #expect(Bezier.parse("c,,0,0,1,1") == nil)
        #expect(Bezier.parse("c, 0,, 0, 1, 1") == nil)
        #expect(Bezier.parse(", 0, 0, 1, 1") == nil)
        #expect(Bezier.parse("c, 0, 0, 1, x") == nil)
        #expect(Bezier.parse("c, -1, -1, 2, 2") != nil)
    }

    @Test func bezierEvaluationNeverReturnsNaN() {
        let b = Bezier.builtIns["default"]!
        #expect(b.y(at: .nan) == 0)
        #expect(b.y(at: .infinity) == 1)
        #expect(b.y(at: -.infinity) == 0)
    }

    @Test func animationRejectsNonFiniteAndAbsurdNumbers() {
        var t = AnimationTree()
        let c: Set<String> = ["default"]
        let before = t
        #expect(t.apply("windows, 1, nan, default", curves: c) != nil)
        #expect(t.apply("windows, 1, inf, default", curves: c) != nil)
        #expect(t.apply("windows, 1, -inf, default", curves: c) != nil)
        #expect(t.apply("windows, 1, 1e300, default", curves: c) == "animation speed is too large")
        #expect(t.apply("windows, 1, -3, default", curves: c) == "animation speed must be positive")
        #expect(t.apply("windows, 1, , default", curves: c) != nil)
        #expect(t.apply("windows, , 3, default", curves: c) != nil)
        #expect(t.apply("windows,, 1, 3, default", curves: c) != nil)
        #expect(t.apply("windows", curves: c) != nil)
        #expect(t.apply("", curves: c) == "no such animation ''")
        #expect(t.apply("windows, 1, 3, default, popin nan%", curves: c) != nil)
        #expect(t.apply("windows, 1, 3, default, popin inf%", curves: c) != nil)
        #expect(t.apply("windows, 1, 3, default, popin 1e300%", curves: c) != nil)
        #expect(t.apply("windows, 1, 3, default, popin -5%", curves: c) != nil)
        #expect(t.apply("workspaces, 1, 3, default, slide nan%", curves: c) != nil)
        #expect(t == before)
        #expect(t.apply("windows, 1, 3, default, popin 0%", curves: c) == nil)
        #expect(t.apply("windows, 1, 3, default, popin 87.5%", curves: c) == nil)
    }

    @Test func styleFamilies() {
        var t = AnimationTree()
        let c: Set<String> = ["default"]
        #expect(t.apply("windowsIn, 1, 3, default, slide left", curves: c) == nil)
        #expect(t.apply("windowsIn, 1, 3, default, slide sideways", curves: c) == "invalid animation style 'slide sideways' for windowsIn")
        #expect(t.apply("windowsIn, 1, 3, default, gnomed", curves: c) == nil)
        #expect(t.apply("windowsIn, 1, 3, default, gnomed 5", curves: c) != nil)
        #expect(t.apply("layersIn, 1, 3, default, fade anything goes", curves: c) == nil)
        #expect(t.apply("layersIn, 1, 3, default, gnomed", curves: c) != nil)
        #expect(t.apply("specialWorkspaceIn, 1, 3, default, slidefadevert 30% top", curves: c) == nil)
        #expect(t.apply("workspacesIn, 1, 3, default, slide diagonal", curves: c) != nil)
        #expect(t.apply("borderangle, 1, 3, default, once", curves: c) == nil)
        #expect(t.apply("shadowangle, 1, 3, default, spin", curves: c) != nil)
        #expect(t.apply("fadeIn, 1, 3, default, whatever", curves: c) == nil)
    }
}
