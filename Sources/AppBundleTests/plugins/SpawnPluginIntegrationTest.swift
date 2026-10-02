@testable import AppBundle
import XCTest

final class SpawnPluginIntegrationTest: XCTestCase {
    func testNewProcessGroupCwdEnvAndOnlyStdFdsInherited() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appending(path: "p.sh")
        // pgid, cwd, env var, number of open fds (0,1,2 + the one ls itself opens)
        try "#!/bin/sh\necho \"$(ps -o pgid= -p $$ | tr -d ' ') $$ $(pwd -P) $FOO $(ls /dev/fd | wc -l | tr -d ' ')\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        var out: [Int32] = [0, 0]
        XCTAssertEqual(unsafe pipe(&out), 0)
        let devNull = unsafe open("/dev/null", O_RDWR)
        let pid = try spawnPlugin(path: script.path, environment: ["FOO": "bar", "PATH": "/usr/bin:/bin"], directory: dir.path, stdin: devNull, stdout: out[1], stderr: devNull).get()
        close(out[1])
        close(devNull)
        let output = String(decoding: FileHandle(fileDescriptor: out[0], closeOnDealloc: true).readDataToEndOfFile(), as: UTF8.self)
        var status: Int32 = 0
        _ = unsafe waitpid(pid, &status, 0)

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        assertEquals(parts[0], parts[1]) // pgid == pid: its own process group
        assertTrue(parts[2].hasSuffix(dir.path)) // /var is a symlink to /private/var
        assertEquals(parts[3], "bar")
        XCTAssertLessThanOrEqual(Int(parts[4]) ?? 99, 5) // no leaked parent fds
    }

    func testMissingExecutableIsAFailureNotACrash() {
        let devNull = unsafe open("/dev/null", O_RDWR)
        defer { close(devNull) }
        let result = spawnPlugin(path: "/nonexistent/x", environment: [:], directory: "/", stdin: devNull, stdout: devNull, stderr: devNull)
        assertNotNil(result.failureOrNil)
    }

    func testPluginLogWritesAndTrims() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "logs-\(UUID().uuidString)")
        let log = PluginLog(name: "gpu", dir: dir, limit: 200, keep: 100)
        for i in 0 ..< 50 { log.write("message \(i)") }
        log.flushForTests()
        let text = try String(contentsOf: log.url, encoding: .utf8)
        assertTrue(text.contains("message 49"))
        XCTAssertLessThanOrEqual(text.utf8.count, 200)
    }
}
