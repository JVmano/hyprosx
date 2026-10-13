import AppKit

final class MouseUpMonitor {
    private var monitor: Any?
    private let onMouseUp: () -> Void

    init(onMouseUp: @escaping () -> Void) { self.onMouseUp = onMouseUp }

    func arm() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.fire() }
        if !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            DispatchQueue.main.async { [weak self] in self?.fire() }
        }
    }

    private func fire() {
        guard let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
        onMouseUp()
    }
}
