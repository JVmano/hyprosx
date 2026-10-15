import AppKit
import Carbon.HIToolbox
import HyprCore

final class HotkeyManager {
    private static let signature: OSType = 0x4859_5052

    private let run: ([Bind]) -> Void
    private let keyTap: KeyTap
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var groups: [UInt32: HotkeyGroup] = [:]
    private var repeatTimer: Timer?
    private var heldID: UInt32?
    private var nextID: UInt32 = 1
    private var generation = 0
    private(set) var failures: [Diagnostic] = []

    init(run: @escaping ([Bind]) -> Void) {
        self.run = run
        keyTap = KeyTap(run: run)
    }

    deinit {
        deactivate()
        if let handler { RemoveEventHandler(handler) }
    }

    @discardableResult
    func install() -> Bool {
        guard handler == nil else { return true }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.hotkey(id.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        return status == noErr
    }

    func activate(_ binds: [Bind], allBinds: [Bind]) {
        releaseCarbon()
        failures = []
        let split = HotkeyPlan.split(HotkeyPlan.groups(binds))
        for group in split.carbon {
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(group.keyCode), HotkeyPlan.carbonModifiers(group.modifiers),
                                             EventHotKeyID(signature: HotkeyManager.signature, id: id), GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                groups[id] = group
            } else if let first = group.press.first ?? group.release.first {
                failures.append(Diagnostic(first.location, "this hotkey could not be registered; another app may own it", isWarning: true))
            }
        }
        if !keyTap.update(split.tap, keepRunning: HotkeyPlan.needsTap(allBinds)) {
            let anyTap = split.tap.first ?? HotkeyPlan.split(HotkeyPlan.groups(allBinds)).tap.first
            if let first = anyTap?.press.first ?? anyTap?.release.first {
                failures.append(Diagnostic(first.location, "Option shortcuts need the keyboard tap; it could not start"))
            }
        }
    }

    func deactivate() {
        releaseCarbon()
        keyTap.stop()
    }

    private func releaseCarbon() {
        generation += 1
        stopRepeat()
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        groups = [:]
    }

    private func hotkey(_ id: UInt32, pressed: Bool) {
        guard let group = groups[id] else { return }
        if pressed {
            stopRepeat()
            let current = generation
            run(group.press)
            guard group.repeats, generation == current else { return }
            heldID = id
            repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatDelay, repeats: false) { [weak self] _ in
                self?.startRepeating(id, group)
            }
        } else {
            if heldID == id { stopRepeat() }
            run(group.release)
        }
    }

    private func startRepeating(_ id: UInt32, _ group: HotkeyGroup) {
        guard repeatOnce(id, group) else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatInterval, repeats: true) { [weak self] _ in
            self?.repeatOnce(id, group)
        }
    }

    @discardableResult
    private func repeatOnce(_ id: UInt32, _ group: HotkeyGroup) -> Bool {
        guard heldID == id else { return false }
        guard CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(group.keyCode)) else {
            stopRepeat()
            return false
        }
        let current = generation
        run(group.press.filter { $0.flags.contains(.repeating) })
        return generation == current && heldID == id
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        heldID = nil
    }
}
