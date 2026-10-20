import Testing
@testable import HyprCore

private let linear = MotionTiming(duration: 1, curve: Bezier.builtIns["linear"]!)
private let a = Rect(x: 0, y: 0, width: 100, height: 100)
private let b = Rect(x: 100, y: 0, width: 300, height: 100)

private func close(_ x: Rect?, _ y: Rect) -> Bool {
    guard let x else { return false }
    return abs(x.x - y.x) < 0.5 && abs(x.y - y.y) < 0.5 && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.5
}

@Suite struct AnimatorTests {
    @Test func aLiveAnimationWritesEveryFrameWithItsSize() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 10)
        guard case .frame(1, let f, let size)? = m.tick(10.5).first else { Issue.record("no frame"); return }
        #expect(close(f, Rect(x: 50, y: 0, width: 200, height: 100)))
        #expect(size)
    }

    @Test func theEndWritesTheExactGoalAndStops() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        #expect(m.tick(1.2) == [.finished(1, b, parkAt: nil)])
        #expect(!m.isActive)
        #expect(m.tick(1.3).isEmpty)
    }

    @Test func aRetargetStartsFromTheCurrentValue() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        let c = Rect(x: 300, y: 0, width: 100, height: 100)
        m.animate(1, MotionPlan(from: a, to: c, timing: linear), live: true, now: 0.5)
        #expect(close(m.current(1, at: 0.5), Rect(x: 50, y: 0, width: 200, height: 100)))
        #expect(close(m.current(1, at: 1.0), Rect(x: 175, y: 0, width: 150, height: 100)))
    }

    @Test func theSameGoalDoesNotRestartTheTimer() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0.5)
        #expect(m.tick(1.0) == [.finished(1, b, parkAt: nil)])
    }

    @Test func aSlowAppGetsPositionTicksAndOneSizeWriteAtTheMiddle() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: false, now: 0)
        guard case .frame(_, _, let early)? = m.tick(0.2).first,
              case .frame(_, let mid, let midSize)? = m.tick(0.6).first,
              case .frame(_, _, let late)? = m.tick(0.8).first else { Issue.record("missing frames"); return }
        #expect(!early)
        #expect(midSize && mid.size == b.size)
        #expect(!late)
    }

    @Test func aParkGlideEndsWithThePark() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: false, now: 0, parkAt: Point(x: 1511, y: 981))
        #expect(m.tick(2) == [.finished(1, b, parkAt: Point(x: 1511, y: 981))])
    }

    @Test func aNewGoalWithoutParkClearsThePark() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: false, now: 0, parkAt: Point(x: 1511, y: 981))
        m.animate(1, MotionPlan(from: b, to: a, timing: linear), live: true, now: 0.5)
        #expect(m.tick(3) == [.finished(1, a, parkAt: nil)])
    }

    @Test func cancelStopsTheWindow() {
        var m = Animator()
        m.animate(1, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        m.animate(2, MotionPlan(from: a, to: b, timing: linear), live: true, now: 0)
        m.cancel(1)
        #expect(m.animating == [2])
        #expect(m.current(1, at: 0.5) == nil)
    }
}
