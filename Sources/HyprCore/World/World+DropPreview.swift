import Foundation

extension World {
    public func dropPreview(cursor: Point) -> Rect? {
        guard let id = dragging, !dragIsResize, windows[id]?.isFloating == false else { return nil }
        let scratch = scratchCopy()
        guard scratch.endDrag(at: cursor), let ws = scratch.windows[id].flatMap({ scratch.workspaces[$0.workspace] }) else { return nil }
        return scratch.targetFrames(ws)[id]
    }

    func scratchCopy() -> World {
        let copy = World(config: config)
        copy.monitors = monitors
        copy.workspaces = workspaces
        copy.windows = windows
        copy.activeWorkspace = activeWorkspace
        copy.activeSpecial = activeSpecial
        copy.focusedMonitor = focusedMonitor
        copy.focusedWindow = focusedWindow
        copy.focusHistory = focusHistory
        copy.submap = submap
        copy.cursor = cursor
        copy.isStartingUp = isStartingUp
        copy.lastKnownMonitors = lastKnownMonitors
        copy.ignored = ignored
        copy.previousWorkspace = previousWorkspace
        copy.previousPerMonitor = previousPerMonitor
        copy.lastActiveByMonitorName = lastActiveByMonitorName
        copy.nextNamedID = nextNamedID
        copy.spawnRules = spawnRules
        copy.pidRules = pidRules
        copy.nextSpawnToken = nextSpawnToken
        copy.dragging = dragging
        copy.dragIsResize = dragIsResize
        copy.mouseDrag = mouseDrag
        copy.placementOrder = placementOrder
        return copy
    }
}
