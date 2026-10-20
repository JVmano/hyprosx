import Testing
import Foundation
@testable import HyprCore

@Suite struct SocketTests {
    func freshTmp() -> String {
        let tmp = "/tmp/hyprosx-t\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        mkdir(tmp, 0o700)
        return tmp
    }

    func mode(_ path: String) -> (type: mode_t, perms: mode_t) {
        var st = stat()
        lstat(path, &st)
        return (st.st_mode & S_IFMT, st.st_mode & 0o777)
    }

    func rawConnect(_ path: String) -> Int32 {
        var addr = SocketIO.address(path)!
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        SocketIO.prepare(fd)
        return fd
    }

    @Test func roundTripWithOwnerOnlyPermissions() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        let server = SocketServer(path: path, queue: DispatchQueue(label: "socket-test-1")) { "reply to \($0)" }
        try server.start()
        #expect(SocketClient.send("j/clients", to: path) == "reply to j/clients")
        #expect(SocketClient.send("/dispatch workspace 2", to: path) == "reply to /dispatch workspace 2")
        #expect(mode(SocketPaths.directory(tmp: tmp)) == (S_IFDIR, 0o700))
        #expect(mode(path) == (S_IFSOCK, 0o600))
    }

    @Test func staleSocketFileIsReplaced() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        mkdir(SocketPaths.directory(tmp: tmp), 0o755)
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-2")) { _ in "fresh" }.start()
        #expect(SocketClient.send("version", to: path) == "fresh")
        #expect(mode(SocketPaths.directory(tmp: tmp)).perms == 0o700)
    }

    @Test func symlinkedFolderIsRefused() {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        symlink("/tmp", SocketPaths.directory(tmp: tmp))
        let server = SocketServer(path: SocketPaths.socket(tmp: tmp), queue: DispatchQueue(label: "socket-test-3")) { $0 }
        #expect(throws: SocketError.self) { try server.start() }
    }

    @Test func overlongPathIsRefusedBeforeAnythingIsCreated() {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let dir = tmp + "/" + String(repeating: "d", count: 120)
        let server = SocketServer(path: dir + "/.socket.sock", queue: DispatchQueue(label: "socket-test-3b")) { $0 }
        #expect(throws: SocketError.pathTooLong) { try server.start() }
        #expect(!FileManager.default.fileExists(atPath: dir))
    }

    @Test func largeReplyArrivesWhole() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        let big = String(repeating: "x", count: 1_000_000)
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-4")) { _ in big }.start()
        #expect(SocketClient.send("clients", to: path)?.count == 1_000_000)
    }

    @Test func missingServerGivesNil() {
        #expect(SocketClient.send("version", to: "/tmp/hyprosx-none-\(getpid())/.socket.sock") == nil)
    }

    @Test func silentClientOnlyDelaysOthersBriefly() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-5")) { _ in "fresh" }.start()
        let silent = rawConnect(path)
        defer { close(silent) }
        let start = ContinuousClock.now
        #expect(SocketClient.send("version", to: path) == "fresh")
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func trickleClientIsCutOffByAnOverallDeadline() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-6")) { "got \($0.count)" }.start()
        let trickle = rawConnect(path)
        DispatchQueue.global().async {
            for _ in 0..<12 {
                if write(trickle, "v", 1) != 1 { break }
                usleep(300_000)
            }
            close(trickle)
        }
        let start = ContinuousClock.now
        #expect(SocketClient.send("version", to: path) == "got 7")
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func clientThatNeverReadsDoesNotBlockTheNextOne() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        let big = String(repeating: "x", count: 4_000_000)
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-7")) { $0 == "big" ? big : "small" }.start()
        let stuck = rawConnect(path)
        defer { close(stuck) }
        write(stuck, "big", 3)
        shutdown(stuck, SHUT_WR)
        let start = ContinuousClock.now
        #expect(SocketClient.send("other", to: path) == "small")
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func oversizeRequestIsRefusedNotTruncated() throws {
        let tmp = freshTmp()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let path = SocketPaths.socket(tmp: tmp)
        try SocketServer(path: path, queue: DispatchQueue(label: "socket-test-8")) { _ in "handled" }.start()
        let fd = rawConnect(path)
        defer { close(fd) }
        let body = [UInt8](repeating: UInt8(ascii: "a"), count: 70_000)
        _ = SocketIO.writeAll(fd, body, deadline: SocketIO.deadline(seconds: 3))
        let reply = SocketIO.readAll(fd, limit: 1024, deadline: SocketIO.deadline(seconds: 3), partialOK: true).map { String(decoding: $0, as: UTF8.self) }
        #expect(reply == "request too large")
    }

    @Test func defaultPathIsInTheUserTempFolder() {
        #expect(SocketPaths.socket().hasSuffix("/hyprosx/.socket.sock"))
        #expect(SocketPaths.userTempDirectory().hasPrefix("/var/folders/") || SocketPaths.userTempDirectory().hasPrefix("/private/var/folders/"))
    }

    @Test func exitCodes() {
        #expect(!IPCExit.isError(command: "dispatch", batch: false, reply: "ok"))
        #expect(IPCExit.isError(command: "dispatch", batch: false, reply: "no window matches"))
        #expect(IPCExit.isError(command: "keyword", batch: false, reply: "exec over IPC is disabled (macos:ipc_exec)"))
        #expect(!IPCExit.isError(command: "clients", batch: false, reply: "Window 0x1a -> Notes:"))
        #expect(IPCExit.isError(command: "frob", batch: false, reply: "unknown request: frob"))
        #expect(!IPCExit.isError(command: "dispatch", batch: true, reply: "ok\n\nno window matches"))
    }

    @Test func exitCodesForRefusedAndBatchedErrors() {
        #expect(IPCExit.isError(command: "keyword", batch: false, reply: "option not settable over IPC"))
        #expect(IPCExit.isError(command: "keyword", batch: true, reply: "option not settable over IPC"))
        #expect(IPCExit.isError(command: "dispatch", batch: true, reply: "ok\n\nexec over IPC is disabled (macos:ipc_exec)"))
        #expect(IPCExit.isError(command: "", batch: true, reply: "ok\n\nunknown request: frob"))
        #expect(IPCExit.isError(command: "clients", batch: false, reply: "request too large"))
    }
}
