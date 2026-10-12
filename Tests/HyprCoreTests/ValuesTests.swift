import Testing
@testable import HyprCore

@Suite struct ValuesTests {
    @Test(arguments: [("true", true), ("yes", true), ("on", true), ("1", true), ("yes, please :)", true),
                      ("false", false), ("no", false), ("off", false), ("0", false)])
    func bools(_ raw: String, _ expected: Bool) { #expect(ConfigValue.bool(raw) == expected) }

    @Test func badBoolIsNil() { #expect(ConfigValue.bool("maybe") == nil) }

    @Test func ints() {
        #expect(ConfigValue.int("42") == 42)
        #expect(ConfigValue.int("-3") == -3)
        #expect(ConfigValue.int("0x10") == 16)
        #expect(ConfigValue.int("true") == 1)
        #expect(ConfigValue.int("x") == nil)
    }

    @Test func hugeOrNonFiniteIntIsNil() {
        #expect(ConfigValue.int("1e30") == nil)
        #expect(ConfigValue.int("inf") == nil)
        #expect(ConfigValue.int("2.0") == 2)
    }

    @Test func floats() {
        #expect(ConfigValue.float("0.55") == 0.55)
        #expect(ConfigValue.float("1") == 1)
        #expect(ConfigValue.float("nope") == nil)
    }

    @Test func colorForms() {
        #expect(ConfigValue.color("rgba(ff000080)") == Color(r: 1, g: 0, b: 0, a: 128.0 / 255))
        #expect(ConfigValue.color("rgb(00ff00)") == Color(r: 0, g: 1, b: 0, a: 1))
        #expect(ConfigValue.color("rgba(255, 0, 0, 0.5)") == Color(r: 1, g: 0, b: 0, a: 0.5))
        #expect(ConfigValue.color("rgb(0,0,255)") == Color(r: 0, g: 0, b: 1, a: 1))
        #expect(ConfigValue.color("0xff444444") == Color(r: 68.0 / 255, g: 68.0 / 255, b: 68.0 / 255, a: 1))
        #expect(ConfigValue.color("blue") == nil)
    }

    @Test func gradientWithAngle() {
        let g = ConfigValue.gradient("rgba(33ccffee) rgba(00ff99ee) 45deg")
        #expect(g?.colors.count == 2)
        #expect(g?.angleDegrees == 45)
        #expect(ConfigValue.gradient("rgba(595959aa)")?.angleDegrees == 0)
        #expect(ConfigValue.gradient("0xffffffff")?.colors == [Color(r: 1, g: 1, b: 1, a: 1)])
        #expect(ConfigValue.gradient("45deg") == nil)
    }

    @Test func vec2() {
        #expect(ConfigValue.vec2("10 -20.5").map { [$0.0, $0.1] } == [10, -20.5])
        #expect(ConfigValue.vec2("10") == nil)
    }

    @Test func edges() {
        #expect(ConfigValue.edges("5") == Edges(all: 5))
        #expect(ConfigValue.edges("5 10") == Edges(top: 5, right: 10, bottom: 5, left: 10))
        #expect(ConfigValue.edges("5,10,15,20") == Edges(top: 5, right: 10, bottom: 15, left: 20))
        #expect(ConfigValue.edges("a") == nil)
    }

    @Test func nonFiniteNumbersAreNil() {
        #expect(ConfigValue.float("nan") == nil)
        #expect(ConfigValue.float("inf") == nil)
        #expect(ConfigValue.float("1e999") == nil)
        #expect(ConfigValue.vec2("nan 1") == nil)
        #expect(ConfigValue.vec2("nan inf") == nil)
        #expect(ConfigValue.edges("inf") == nil)
        #expect(ConfigValue.edges("nan") == nil)
        #expect(ConfigValue.color("rgb(nan,0,0)") == nil)
        #expect(ConfigValue.color("rgba(0,0,0,inf)") == nil)
        #expect(ConfigValue.gradient("rgba(33ccffee) infdeg") == nil)
        #expect(ConfigValue.gradient("rgba(33ccffee) nandeg") == nil)
    }

    @Test func outOfRangeCommaColorsAreNil() {
        #expect(ConfigValue.color("rgb(300,0,0)") == nil)
        #expect(ConfigValue.color("rgb(-1,0,0)") == nil)
        #expect(ConfigValue.color("rgba(0,0,0,-1)") == nil)
        #expect(ConfigValue.color("rgba(255,0,0,128)") == nil)
        #expect(ConfigValue.color("rgba(255,0,0,1)") == Color(r: 1, g: 0, b: 0, a: 1))
        #expect(ConfigValue.color("rgb(255,255,255)") == Color(r: 1, g: 1, b: 1, a: 1))
    }

    @Test func junkTokensAreNil() {
        #expect(ConfigValue.vec2("10 abc 20") == nil)
        #expect(ConfigValue.vec2("10 abc") == nil)
        #expect(ConfigValue.vec2("1 2 3") == nil)
        #expect(ConfigValue.color("rgb(1,,2,3)") == nil)
        #expect(ConfigValue.color("rgb(1,2,x)") == nil)
        #expect(ConfigValue.edges("5 x 10") == nil)
    }

    @Test func threeValueEdgesAndSpacedGradient() {
        #expect(ConfigValue.edges("5 10 15") == Edges(top: 5, right: 10, bottom: 15, left: 10))
        let g = ConfigValue.gradient("rgba(255, 0, 0, 0.5) rgb(0, 255, 0) 90deg")
        #expect(g?.colors == [Color(r: 1, g: 0, b: 0, a: 0.5), Color(r: 0, g: 1, b: 0, a: 1)])
        #expect(g?.angleDegrees == 90)
    }
}
