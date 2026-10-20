import Testing
import Foundation
@testable import HyprCore

@Suite struct SpawnerTests {
    @Test func spawnedCommandIsItsOwnResponsibleProcess() throws {
        #expect(Spawner.isAvailable)
        let pid = try Spawner.spawn("/bin/sleep 1", environment: ProcessInfo.processInfo.environment).get()
        #expect(Spawner.responsiblePID(for: pid) == pid)
        #expect(Spawner.responsiblePID(for: pid) != Spawner.responsiblePID(for: getpid()))
        kill(pid, SIGKILL)
    }

    @Test func environmentPrefixesPathAndAddsEnvValues() {
        let env = Spawner.environment(base: ["HOME": "/Users/x", "PATH": "/usr/bin:/bin"], extra: [EnvVar(name: "HYPROSX_TEST", value: "ok")])
        #expect(env["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/Users/x/.local/bin:/usr/bin:/bin")
        #expect(env["HYPROSX_TEST"] == "ok")
        #expect(Spawner.environment(base: ["HOME": "/h"], extra: [])["PATH"] == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/h/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func commandRunsThroughTheShellWithTheEnvironment() throws {
        let dir = try scratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("out").path
        let env = Spawner.environment(base: ProcessInfo.processInfo.environment, extra: [EnvVar(name: "HYPROSX_TEST", value: "a b")])
        _ = try Spawner.spawn("printf '%s' \"$HYPROSX_TEST\" > '\(out)'", environment: env).get()
        var text: String?
        for _ in 0..<200 where text != "a b" {
            usleep(10_000)
            text = try? String(contentsOfFile: out, encoding: .utf8)
        }
        #expect(text == "a b")
    }

    @Test func emptyBlankAndNulInputsAreRefused() {
        for command in ["", "   ", "\n\t ", "echo a\0b"] {
            #expect((try? Spawner.spawn(command, environment: [:]).get()) == nil)
        }
        #expect((try? Spawner.spawn("true", environment: ["A\0B": "x"]).get()) == nil)
        #expect((try? Spawner.spawn("true", environment: ["A": "x\0y"]).get()) == nil)
    }

    @Test func childHasNullStdioNoInheritedDescriptorsAndItsOwnSession() throws {
        let opened = open("/dev/null", O_RDONLY)
        let leaked = fcntl(opened, F_DUPFD, 200)
        close(opened)
        defer { close(leaked) }
        #expect(leaked >= 200)
        let dir = try scratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("out").path
        let script = "r=ok; [ -e /dev/fd/\(leaked) ] && r=leaked; "
            + "[ /dev/fd/0 -ef /dev/null ] && [ /dev/fd/1 -ef /dev/null ] && [ /dev/fd/2 -ef /dev/null ] || r=stdio; "
            + "p=$(ps -o pgid= -p $$); [ \"$(echo $p)\" = \"$$\" ] || r=\"$r+session\"; printf '%s' \"$r\" > '\(out)'"
        _ = try Spawner.spawn(script, environment: ProcessInfo.processInfo.environment).get()
        #expect(waitForText(out) == "ok")
    }

    @Test func childStartsWithDefaultSignalsAndAnEmptyMask() throws {
        signal(SIGUSR2, SIG_IGN)
        defer { signal(SIGUSR2, SIG_DFL) }
        var blocked = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, SIGUSR1)
        var previous = sigset_t()
        pthread_sigmask(SIG_BLOCK, &blocked, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        let dir = try scratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let env = ProcessInfo.processInfo.environment
        func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
        let a = try Spawner.spawn("printf ran > '\(path("ignored.ran"))'; kill -USR2 $$; printf survived > '\(path("ignored"))'", environment: env).get()
        let b = try Spawner.spawn("printf ran > '\(path("masked.ran"))'; kill -USR1 $$; printf survived > '\(path("masked"))'", environment: env).get()
        #expect(waitForExit(a) && waitForExit(b))
        #expect((try? String(contentsOfFile: path("ignored.ran"), encoding: .utf8)) == "ran")
        #expect((try? String(contentsOfFile: path("masked.ran"), encoding: .utf8)) == "ran")
        #expect(!FileManager.default.fileExists(atPath: path("ignored")))
        #expect(!FileManager.default.fileExists(atPath: path("masked")))
    }

    @Test func everySpawnedChildIsReaped() throws {
        let env = ProcessInfo.processInfo.environment
        let pids = try (0..<2000).map { _ in try Spawner.spawn("true", environment: env).get() }
        var remaining = pids
        let deadline = ContinuousClock.now + .seconds(15)
        while !remaining.isEmpty && ContinuousClock.now < deadline {
            remaining = remaining.filter { processState($0) != nil }
            if !remaining.isEmpty { usleep(10_000) }
        }
        let zombies = remaining.filter { processState($0) == SZOMB }
        #expect(zombies.isEmpty, "unreaped children: \(zombies)")
        #expect(remaining.isEmpty)
    }

    private func scratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyprosx-spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func waitForText(_ path: String) -> String? {
        for _ in 0..<300 {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty { return text }
            usleep(10_000)
        }
        return nil
    }

    private func processState(_ pid: pid_t) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return Int32(info.kp_proc.p_stat)
    }

    private func waitForExit(_ pid: pid_t) -> Bool {
        for _ in 0..<300 {
            if processState(pid) == nil || processState(pid) == SZOMB { return true }
            usleep(10_000)
        }
        return false
    }
}
