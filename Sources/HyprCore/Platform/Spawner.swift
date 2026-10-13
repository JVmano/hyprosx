import Foundation

public struct SpawnError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum Spawner {
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    typealias ResponsibleFor = @convention(c) (pid_t) -> pid_t

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let setDisclaim = dlsym(handle, "responsibility_spawnattrs_setdisclaim").map { unsafeBitCast($0, to: SetDisclaim.self) }
    private static let responsibleFor = dlsym(handle, "responsibility_get_pid_responsible_for_pid").map { unsafeBitCast($0, to: ResponsibleFor.self) }
    private static let reaperQueue = DispatchQueue(label: "dev.hyprosx.reaper")
    private static var reapers: [pid_t: DispatchSourceProcess] = [:]

    public static var isAvailable: Bool { setDisclaim != nil }

    public static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsibleFor else { return nil }
        let responsible = responsibleFor(pid)
        return responsible > 0 ? responsible : nil
    }

    public static func environment(base: [String: String], extra: [EnvVar]) -> [String: String] {
        var env = base
        let home = base["HOME"] ?? NSHomeDirectory()
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(home)/.local/bin:" + (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for e in extra { env[e.name] = e.value }
        return env
    }

    public static func spawn(_ command: String, environment: [String: String]) -> Result<pid_t, SpawnError> {
        guard let setDisclaim else { return .failure(SpawnError("commands are disabled: responsibility_spawnattrs_setdisclaim is missing")) }
        if command.allSatisfy(\.isWhitespace) { return .failure(SpawnError("cannot start an empty command")) }
        if command.utf8.contains(0) { return .failure(SpawnError("cannot start a command that contains a NUL byte")) }
        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else { return .failure(SpawnError("cannot start command: spawn attributes failed")) }
        defer { posix_spawnattr_destroy(&attr) }
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        let flags = Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
        guard posix_spawnattr_setsigmask(&attr, &noSignals) == 0, posix_spawnattr_setsigdefault(&attr, &allSignals) == 0,
              posix_spawnattr_setflags(&attr, flags) == 0 else { return .failure(SpawnError("cannot start command: spawn attributes failed")) }
        guard setDisclaim(&attr, 1) == 0 else { return .failure(SpawnError("commands are disabled: cannot disclaim responsibility")) }
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return .failure(SpawnError("cannot start command: file actions failed")) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0) == 0 else {
            return .failure(SpawnError("cannot start command: file actions failed"))
        }
        if environment.contains(where: { $0.key.utf8.contains(0) || $0.value.utf8.contains(0) }) {
            return .failure(SpawnError("cannot start command: the environment contains a NUL byte"))
        }
        let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/sh", "-c", command].map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        guard !argv.dropLast().contains(where: { $0 == nil }), !envp.dropLast().contains(where: { $0 == nil }) else {
            return .failure(SpawnError("cannot start command: out of memory"))
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/sh", &actions, &attr, argv, envp)
        guard rc == 0 else { return .failure(SpawnError("cannot start command: \(String(cString: strerror(rc)))")) }
        reap(pid)
        return .success(pid)
    }

    private static func reap(_ pid: pid_t) {
        reaperQueue.async {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: reaperQueue)
            source.setEventHandler { collect(pid, wait: true) }
            reapers[pid] = source
            source.resume()
            collect(pid, wait: false)
        }
    }

    private static func collect(_ pid: pid_t, wait: Bool) {
        guard let source = reapers[pid] else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, wait ? 0 : WNOHANG) } while result == -1 && errno == EINTR
        if result == 0 { return }
        reapers[pid] = nil
        source.cancel()
    }
}
