import Foundation

public struct FrameAnimation: Equatable, Sendable {
    public var begun: Rect
    public var goal: Rect
    public var start: Double
    public var timing: MotionTiming

    public init(begun: Rect, goal: Rect, start: Double, timing: MotionTiming) {
        self.begun = begun; self.goal = goal; self.start = start; self.timing = timing
    }

    public func progress(at now: Double) -> Double {
        guard timing.duration > 0 else { return 1 }
        return min(max((now - start) / timing.duration, 0), 1)
    }

    public func value(at now: Double) -> Rect {
        let p = progress(at: now)
        guard p < 1 else { return goal }
        let k = timing.curve.y(at: p)
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * k }
        return Rect(x: mix(begun.x, goal.x), y: mix(begun.y, goal.y), width: mix(begun.width, goal.width), height: mix(begun.height, goal.height))
    }
}

public enum AnimationStep: Equatable, Sendable {
    case frame(WindowID, Rect, writesSize: Bool)
    case finished(WindowID, Rect, parkAt: Point?)
}

public struct Animator: Equatable, Sendable {
    struct Running: Equatable, Sendable {
        var animation: FrameAnimation
        var live: Bool
        var sizeSent: Bool
        var parkAt: Point?
    }

    private var running: [WindowID: Running] = [:]

    public init() {}

    public var isActive: Bool { !running.isEmpty }
    public var animating: Set<WindowID> { Set(running.keys) }

    public func current(_ id: WindowID, at now: Double) -> Rect? { running[id]?.animation.value(at: now) }

    public mutating func animate(_ id: WindowID, _ plan: MotionPlan, live: Bool, now: Double, parkAt: Point? = nil) {
        if let r = running[id], r.animation.goal == plan.to, r.parkAt == parkAt { return }
        let begun = running[id]?.animation.value(at: now) ?? plan.from
        let animation = FrameAnimation(begun: begun, goal: plan.to, start: now, timing: plan.timing)
        running[id] = Running(animation: animation, live: live, sizeSent: begun.size == plan.to.size, parkAt: parkAt)
    }

    public mutating func cancel(_ id: WindowID) { running[id] = nil }

    public mutating func tick(_ now: Double) -> [AnimationStep] {
        var steps: [AnimationStep] = []
        for id in running.keys.sorted() {
            guard var r = running[id] else { continue }
            let p = r.animation.progress(at: now)
            if p >= 1 {
                steps.append(.finished(id, r.animation.goal, parkAt: r.parkAt))
                running[id] = nil
                continue
            }
            var frame = r.animation.value(at: now)
            var writesSize = r.live
            if !r.live && !r.sizeSent && p >= 0.5 {
                frame = Rect(origin: frame.origin, size: r.animation.goal.size)
                writesSize = true
                r.sizeSent = true
            }
            steps.append(.frame(id, frame, writesSize: writesSize))
            running[id] = r
        }
        return steps
    }
}
