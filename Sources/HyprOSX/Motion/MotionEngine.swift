import AppKit
import QuartzCore
import HyprCore

final class MotionEngine: NSObject {
    private var animator = Animator()
    private var written: [WindowID: Rect] = [:]
    private var link: CADisplayLink?
    private let thread: (WindowID) -> AXAppThread?
    private let world: () -> World?
    var onFrame: (WindowID, Rect) -> Void = { _, _ in }
    var onSettled: (WindowID) -> Void = { _ in }

    init(thread: @escaping (WindowID) -> AXAppThread?, world: @escaping () -> World?) {
        self.thread = thread
        self.world = world
        super.init()
    }

    var animating: Set<WindowID> { animator.animating }

    static var environment: MotionEnvironment {
        MotionEnvironment(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                          reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func setFrames(_ changes: [FrameChange]) {
        guard let world = world() else { return }
        let environment = Self.environment
        let now = CACurrentMediaTime()
        for change in changes {
            let t = thread(change.id)
            let live = (t?.callCount ?? 0) == 0 || (t?.averageLatencyMs ?? 0) < world.config.macos.liveResizeMaxLatency
            let current = animator.current(change.id, at: now) ?? written[change.id] ?? world.windows[change.id]?.lastFrame
            let monitor = world.monitorFrame(of: change.id) ?? change.frame
            if let plan = Motion.plan(change, current: current, monitor: monitor, config: world.config, environment: environment,
                                      window: world.motion(for: change.id), live: live) {
                animator.animate(change.id, plan, live: live, now: now)
            } else {
                animator.cancel(change.id)
                t?.setFrame(change.id, change.frame)
                written[change.id] = change.frame
                onFrame(change.id, change.frame)
            }
        }
        startIfNeeded()
    }

    func park(_ parks: [ParkRequest]) {
        guard let world = world() else { return }
        let environment = Self.environment
        let now = CACurrentMediaTime()
        for p in parks {
            let w = world.windows[p.id]
            let current = animator.current(p.id, at: now) ?? w?.appliedFrame ?? w?.lastFrame
            if let current, let monitor = world.monitorFrame(of: p.id),
               let plan = Motion.planOut(p, current: current, monitor: monitor, config: world.config, environment: environment,
                                         window: world.motion(for: p.id)) {
                animator.animate(p.id, plan, live: false, now: now, parkAt: p.origin)
            } else {
                animator.cancel(p.id)
                thread(p.id)?.setPosition(p.id, p.origin)
            }
            written[p.id] = nil
        }
        startIfNeeded()
    }

    func cancel(_ id: WindowID) {
        animator.cancel(id)
        written[id] = nil
    }

    func stopAll() {
        animator = Animator()
        written = [:]
        link?.invalidate()
        link = nil
    }

    private func startIfNeeded() {
        guard animator.isActive, link == nil, let screen = NSScreen.main else { return }
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ sender: CADisplayLink) {
        for step in animator.tick(CACurrentMediaTime()) {
            switch step {
            case .frame(let id, let frame, let writesSize):
                if writesSize { thread(id)?.setFrame(id, frame) } else { thread(id)?.setPosition(id, frame.origin) }
                written[id] = frame
                onFrame(id, frame)
            case .finished(let id, let frame, let parkAt):
                if let parkAt {
                    thread(id)?.setPosition(id, parkAt)
                    written[id] = nil
                } else {
                    thread(id)?.setFrame(id, frame)
                    written[id] = frame
                    onFrame(id, frame)
                    onSettled(id)
                }
            }
        }
        if !animator.isActive {
            sender.invalidate()
            link = nil
        }
    }
}
