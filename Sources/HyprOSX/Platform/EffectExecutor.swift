import AppKit
import HyprCore

final class EffectExecutor {
    private let tracker: AppTracker
    private let windowPID: (WindowID) -> pid_t?
    private let environment: () -> [String: String]
    private let motion: MotionEngine
    var onSpawned: (Int, pid_t) -> Void = { _, _ in }
    var onSpawnFailed: (String) -> Void = { _ in }
    var onAppEffect: (Effect) -> Void = { _ in }

    init(tracker: AppTracker, windowPID: @escaping (WindowID) -> pid_t?, environment: @escaping () -> [String: String],
         motion: MotionEngine) {
        self.tracker = tracker
        self.windowPID = windowPID
        self.environment = environment
        self.motion = motion
    }

    func execute(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .setFrames(let changes):
                motion.setFrames(changes)
            case .park(let parks):
                motion.park(parks)
            case .focus(let id):
                thread(id)?.focus(id)
            case .raise(let id):
                thread(id)?.raise(id)
            case .close(let id):
                thread(id)?.close(id)
            case .signal(let pid, let signal):
                kill(pid, signal)
            case .hideApp(let pid):
                tracker.hide(pid)
            case .unhideApp(let pid):
                tracker.unhide(pid)
            case .spawn(let command, let token):
                switch Spawner.spawn(command, environment: environment()) {
                case .success(let pid): if let token { onSpawned(token, pid) }
                case .failure(let error): onSpawnFailed(error.message)
                }
            case .warpCursor(let p):
                CGWarpMouseCursorPosition(CGPoint(p))
                CGAssociateMouseAndMouseCursorPosition(1)
            case .submapChanged, .statusChanged, .saveState, .reloadConfig, .exitApp:
                onAppEffect(effect)
            }
        }
    }

    private func thread(_ id: WindowID) -> AXAppThread? {
        windowPID(id).flatMap { tracker.threads[$0] }
    }
}
