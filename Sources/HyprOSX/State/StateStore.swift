import Foundation
import HyprCore

final class StateStore {
    let url: URL
    private var pending: DispatchWorkItem?

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HyprOSX/state.json")) {
        self.url = url
    }

    func load() -> StateSnapshot? {
        guard let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(StateSnapshot.self, from: data),
              snapshot.version == StateSnapshot.currentVersion else { return nil }
        return snapshot
    }

    func schedule(_ snapshot: @escaping () -> StateSnapshot?) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if let s = snapshot() { self?.saveNow(s) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow(_ snapshot: StateSnapshot) {
        pending?.cancel()
        pending = nil
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(snapshot), (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
