@testable import AppBundle
import XCTest

/// Real plugin processes from tiny shell scripts written into a temp dir. Timing scaled ×0.05.
@MainActor
final class PluginHostIntegrationTest: XCTestCase {
    private var root: URL!
    private var host: PluginHost!
    private var ran: [(String, String)] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "plugins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ran = []
        host = PluginHost(timing: PluginTiming(scale: 0.05), bundledDir: nil, logsDir: root.appending(path: "logs"), runCommand: { [unowned self] in ran.append(($0, $1)) })
    }

    override func tearDown() async throws {
        host.stopAll(immediately: true)
    }

    private func plugin(_ name: String, manifest: String, script: String) throws {
        let dir = root.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appending(path: "plugin.toml"), atomically: true, encoding: .utf8)
        let exec = dir.appending(path: "run.sh")
        try ("#!/bin/sh\n" + script).write(to: exec, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)
    }

    private func sync(_ names: [String]) {
        host.sync(names: names, userDirs: [root.path], environment: ["PATH": "/usr/bin:/bin"])
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func status(_ name: String) -> String? { host.snapshot().first { $0.name == name }?.status }
    private func label(_ name: String) -> String? { host.store.widgets[name]?.label }
    private func pid(_ name: String) -> pid_t? {
        (try? String(contentsOf: root.appending(path: "\(name)/pid"), encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    private let stream = "api = 1\nexec = 'run.sh'\nmode = 'stream'\n"

    func testIntervalRunGetsEnvAndCwd() throws {
        // Own host with a 0.5 s timeout: at the shared ×0.05 scale a cold `sh` + `basename` can exceed 50 ms on CI
        host.stopAll(immediately: true)
        host = PluginHost(timing: PluginTiming(scale: 0.5), bundledDir: nil, logsDir: root.appending(path: "logs"), runCommand: { _, _ in })
        try plugin("ok", manifest: "api = 1\nexec = 'run.sh'\nmode = 'interval'\ninterval = 1", script: "echo \"{\\\"label\\\":\\\"$HYPR_PLUGIN_NAME:$(basename \"$PWD\")\\\"}\"\n")
        sync(["ok"])
        assertTrue(waitUntil { label("ok") == "ok:ok" })
        assertTrue(waitUntil { status("ok") == "running" }) // status arrives after the line it reports on
    }

    func testIntervalTimeoutKillsTreeAndGoesFailing() throws {
        // `sleep` is a child of sh: unless the whole group dies, stdout never closes and no further run starts
        try plugin("slow", manifest: "api = 1\nexec = 'run.sh'\nmode = 'interval'\ninterval = 1", script: "sleep 10\necho '{\"label\":\"never\"}'\n")
        sync(["slow"])
        assertTrue(waitUntil { status("slow") == "failing (3)" })
        assertNil(label("slow"))
    }

    func testStreamEchoOnlySubscribedEvents() throws {
        try plugin("echo", manifest: stream + "events = ['workspace']", script: """
            while IFS= read -r line; do
              case "$line" in *workspace*) echo '{"label":"workspace"}' ;; *wake*) echo '{"label":"wake"}' ;; esac
            done
            """)
        sync(["echo"])
        assertTrue(waitUntil { status("echo") == "running" })
        host.send(.workspace, encodePluginEvent(.workspace, ["focused": "2", "prev": "1"]))
        assertTrue(waitUntil { label("echo") == "workspace" })
        host.send(.wake, encodePluginEvent(.wake)) // not subscribed
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        assertEquals(label("echo"), "workspace")
    }

    func testCrashLoopBacksOffThenStops() throws {
        try plugin("crash", manifest: stream, script: "exit 1\n")
        sync(["crash"])
        assertTrue(waitUntil { status("crash")?.hasPrefix("stopped") == true })
        assertEquals(host.snapshot().first?.restarts, 4)
    }

    func testDeafPluginQueueStaysBounded() throws {
        try plugin("deaf", manifest: stream + "events = ['workspace']", script: "exec sleep 30\n")
        sync(["deaf"])
        assertTrue(waitUntil { status("deaf") == "running" })
        let big = encodePluginEvent(.workspace, ["focused": String(repeating: "x", count: 500), "prev": "1"])
        for _ in 0 ..< 1000 { host.send(.workspace, big) } // ~500 KB, far beyond the 64 KB pipe buffer
        assertTrue(waitUntil { host.pendingEventCount("deaf") == 64 })
    }

    func testGarbageLinesDroppedGoodLinesApplied() throws {
        try plugin("garbage", manifest: stream, script: """
            echo 'not json'
            head -c 70000 /dev/zero | tr '\\0' 'a'; echo
            echo '{"label":42,"icon":"ok"}'
            echo '{"label":"good"}'
            exec sleep 30
            """)
        sync(["garbage"])
        assertTrue(waitUntil { label("garbage") == "good" })
        assertEquals(host.store.widgets["garbage"]?.icon, "ok")
        let log = { (try? String(contentsOf: self.root.appending(path: "logs/garbage.log"), encoding: .utf8)) ?? "" }
        assertTrue(waitUntil { log().contains("dropped line: not a JSON object") && log().contains("line longer than 64 KB") && log().contains("ignored field 'label'") })
    }

    func testRunCommandReachesRunner() throws {
        try plugin("runner", manifest: stream, script: "echo '{\"run\":\"workspace 2\"}'\nexec sleep 30\n")
        sync(["runner"])
        assertTrue(waitUntil { ran.count == 1 })
        assertEquals(ran.first?.0, "runner")
        assertEquals(ran.first?.1, "workspace 2")
    }

    func testStopAllImmediatelyKillsProcess() throws {
        try plugin("p", manifest: stream, script: "echo $$ > pid\nexec sleep 30\n")
        sync(["p"])
        assertTrue(waitUntil { pid("p") != nil })
        let p = pid("p")!
        assertTrue(isAlive(p))
        host.stopAll(immediately: true)
        assertTrue(waitUntil(2) { !isAlive(p) })
    }

    func testReloadKeepsUnchangedRestartsChangedStopsRemoved() throws {
        for name in ["keep", "change", "remove"] {
            try plugin(name, manifest: stream, script: "echo $$ > pid\nexec sleep 30\n")
        }
        sync(["keep", "change", "remove"])
        assertTrue(waitUntil { ["keep", "change", "remove"].allSatisfy { pid($0) != nil } })
        let keep = pid("keep")!, change = pid("change")!, remove = pid("remove")!

        try (stream + "events = ['wake']").write(to: root.appending(path: "change/plugin.toml"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appending(path: "change/pid"))
        sync(["keep", "change"])

        assertTrue(waitUntil { !isAlive(remove) })
        assertTrue(waitUntil { pid("change").map { $0 != change } == true })
        assertTrue(waitUntil(2) { !isAlive(change) })
        assertTrue(isAlive(keep))
        assertEquals(host.snapshot().map(\.name), ["keep", "change"])
    }

    func testIntervalRunWithBackgroundChildDoesNotFreeze() throws {
        // The background `sleep` keeps stdout open after the script exits: the run must still end at the timeout
        try plugin("bg", manifest: "api = 1\nexec = 'run.sh'\nmode = 'interval'\ninterval = 1", script: "sleep 3 &\nexit 1\n")
        sync(["bg"])
        assertTrue(waitUntil(2) { status("bg") == "failing (3)" })
    }

    func testStreamExitKillsLeftoverChildren() throws {
        try plugin("orphans", manifest: stream, script: "sleep 30 &\necho $! >> children\nexit 1\n")
        sync(["orphans"])
        assertTrue(waitUntil { status("orphans")?.hasPrefix("stopped") == true })
        let children = ((try? String(contentsOf: root.appending(path: "orphans/children"), encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { pid_t($0) }
        assertEquals(children.count, 5)
        assertTrue(waitUntil(2) { children.allSatisfy { !isAlive($0) } })
    }

    func testReloadRevivesStoppedPlugin() throws {
        try plugin("crash", manifest: stream, script: "exit 1\n")
        sync(["crash"])
        assertTrue(waitUntil { status("crash")?.hasPrefix("stopped") == true })
        sync(["crash"]) // "stopped until reload"
        assertEquals(status("crash"), "starting")
    }

    func testEventTriggersIntervalRunWithEnv() throws {
        // interval 100 × 0.05 = 5 s: after the first run, only events trigger more runs during the test
        try plugin("trig", manifest: "api = 1\nexec = 'run.sh'\nmode = 'interval'\ninterval = 100\nevents = ['wake', 'click']",
                   script: "printf '{\"label\":\"%s:%s:%s\"}\\n' \"$HYPR_EVENT\" \"$HYPR_BUTTON\" \"$(printf '%s' \"$HYPR_EVENT_JSON\" | tr -d '{}\\\"')\"\n")
        sync(["trig"])
        assertTrue(waitUntil { label("trig") == "::" })
        host.send(.wake, encodePluginEvent(.wake))
        assertTrue(waitUntil { label("trig") == "wake::event:wake" })
        host.click("trig", button: "right")
        assertTrue(waitUntil { label("trig") == "click:right:button:right,event:click" })
        host.send(.power, encodePluginEvent(.power, ["source": "ac"])) // not subscribed
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        assertEquals(label("trig"), "click:right:button:right,event:click")
    }

    func testClickReachesSubscribedStreamPlugin() throws {
        try plugin("clicky", manifest: stream + "events = ['click']", script: """
            while IFS= read -r line; do
              case "$line" in *'"button":"left"'*) echo '{"label":"clicked"}' ;; esac
            done
            """)
        sync(["clicky"])
        assertTrue(waitUntil { status("clicky") == "running" })
        host.click("clicky", button: "left")
        assertTrue(waitUntil { label("clicky") == "clicked" })
    }

    func testPopupReachesStoreAndStatusesArePublished() throws {
        try plugin("menu", manifest: stream, script: "echo '{\"label\":\"m\",\"popup\":[{\"label\":\"Go\",\"run\":\"workspace 3\"}]}'\nexec sleep 30\n")
        sync(["menu", "ghost"])
        assertTrue(waitUntil { host.store.widgets["menu"]?.popup == [PopupItem(label: "Go", run: "workspace 3")] })
        assertTrue(waitUntil { host.store.statuses["menu"] == .running })
        assertEquals(host.store.statuses["ghost"], .missing("no plugin folder in \(root.path)"))
    }

    func testPluginTurningMissingDropsItsOldWidget() throws {
        try plugin("gone", manifest: stream, script: "echo '{\"label\":\"old\"}'\nexec sleep 30\n")
        sync(["gone"])
        assertTrue(waitUntil { label("gone") == "old" })
        try FileManager.default.removeItem(at: root.appending(path: "gone"))
        sync(["gone"])
        assertNil(host.store.widgets["gone"]) // the bar must not keep showing stale data
        assertTrue(status("gone")?.hasPrefix("missing") == true)
    }

    func testExecEnvironmentChangeRestartsPlugins() throws {
        try plugin("env", manifest: stream, script: "echo $$ > pid\nexec sleep 30\n")
        host.sync(names: ["env"], userDirs: [root.path], environment: ["PATH": "/usr/bin:/bin", "FOO": "1"])
        assertTrue(waitUntil { pid("env") != nil })
        let first = pid("env")!
        try FileManager.default.removeItem(at: root.appending(path: "env/pid"))
        host.sync(names: ["env"], userDirs: [root.path], environment: ["PATH": "/usr/bin:/bin", "FOO": "2"])
        assertTrue(waitUntil { pid("env").map { $0 != first } == true })
    }

    func testStreamPluginGetsInitialStateOnStart() throws {
        // without it, a workspace widget shows nothing until the first workspace switch
        let host = PluginHost(timing: PluginTiming(scale: 0.05), bundledDir: nil, logsDir: root.appending(path: "logs"),
                              runCommand: { _, _ in }, initialEvents: { [(.workspace, encodePluginEvent(.workspace, ["focused": "3", "prev": "3"]))] })
        defer { host.stopAll(immediately: true) }
        try plugin("initial", manifest: stream + "events = ['workspace']", script: """
            while IFS= read -r line; do
              case "$line" in *'"focused":"3"'*) echo '{"label":"ws 3"}' ;; esac
            done
            """)
        host.sync(names: ["initial"], userDirs: [root.path], environment: ["PATH": "/usr/bin:/bin"])
        assertTrue(waitUntil { host.store.widgets["initial"]?.label == "ws 3" })
    }

    func testMissingAndInvalidStatuses() throws {
        try plugin("bad", manifest: "api = 7", script: "")
        sync(["bad", "ghost"])
        assertEquals(status("bad"), "invalid: unsupported api 7, expected 1")
        assertEquals(status("ghost"), "missing: no plugin folder in \(root.path)")
    }
}
