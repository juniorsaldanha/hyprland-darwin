@testable import AppBundle
import XCTest

final class PluginSupervisorTest: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testBackoffThenStopAfterFiveQuickExits() {
        var s = StreamSupervisor()
        let decisions = (0 ..< 5).map { i in s.onExit(at: t0 + Double(i), startedAt: t0 + Double(i) - 0.1) }
        assertEquals(decisions, [.restart(after: 1), .restart(after: 2), .restart(after: 4), .restart(after: 8), .stop])
    }

    func testSlidingWindowKeepsRestartingWhenExitsAreSpreadOut() {
        var s = StreamSupervisor(maxDelay: 1)
        let decisions = [0.0, 20, 40, 60, 80].map { s.onExit(at: t0 + $0, startedAt: t0 + $0 - 1) }
        assertEquals(decisions.last, .restart(after: 1))
        assertFalse(decisions.contains(.stop))
    }

    func testDelayCappedAt60() {
        var s = StreamSupervisor(maxExits: 100)
        var last: SupervisorDecision = .stop
        for i in 0 ..< 10 { last = s.onExit(at: t0 + Double(i) * 0.01, startedAt: t0) }
        assertEquals(last, .restart(after: 60))
    }

    func testLongRunResetsBackoff() {
        var s = StreamSupervisor()
        _ = s.onExit(at: t0, startedAt: t0 - 1)
        _ = s.onExit(at: t0 + 2, startedAt: t0 + 1)
        assertEquals(s.onExit(at: t0 + 200, startedAt: t0 + 100), .restart(after: 1))
    }

    func testScaledTiming() {
        var s = StreamSupervisor(baseDelay: 0.05, maxDelay: 3, window: 3)
        assertEquals(s.onExit(at: t0, startedAt: t0), .restart(after: 0.05))
        assertEquals(s.onExit(at: t0, startedAt: t0), .restart(after: 0.1))
    }

    func testIntervalHealth() {
        var h = IntervalHealth()
        h.record(success: false)
        h.record(success: false)
        assertFalse(h.isFailing)
        h.record(success: false)
        assertTrue(h.isFailing)
        assertEquals(h.consecutiveFailures, 3)
        h.record(success: true)
        assertEquals(h.consecutiveFailures, 0)
    }

    func testBoundedQueueDropsOldest() {
        var q = BoundedQueue<Int>(capacity: 64)
        for i in 0 ..< 1000 { q.append(i) }
        assertEquals(q.count, 64)
        assertEquals(q.dropped, 936)
        assertEquals(q.popFirst(), 936)
    }

    func testTrimmedLog() {
        assertNil(trimmedLog(Data(repeating: 0x61, count: 10), limit: 100, keep: 50))
        var data = Data()
        for i in 0 ..< 30 { data.append(Data("line \(i)\n".utf8)) } // 30 lines, ~230 bytes
        let trimmed = trimmedLog(data, limit: 100, keep: 50)!
        assertTrue(trimmed.count <= 50)
        assertTrue(String(decoding: trimmed, as: UTF8.self).hasSuffix("line 29\n"))
        assertTrue(String(decoding: trimmed, as: UTF8.self).hasPrefix("line ")) // starts at a line boundary
    }
}

@MainActor
final class PluginEventsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEncodeIsSortedJson() {
        assertEquals(encodePluginEvent(.workspace, ["focused": "2", "prev": "1"]), #"{"event":"workspace","focused":"2","prev":"1"}"#)
        assertEquals(encodePluginEvent(.wake), #"{"event":"wake"}"#)
    }

    func testServerEventMapping() {
        assertEquals(pluginEvent(for: .workspaceChanged(workspace: "2", prevWorkspace: "1"))?.line, #"{"event":"workspace","focused":"2","prev":"1"}"#)
        assertEquals(pluginEvent(for: .focusedMonitorChanged(workspace: "3", monitorId_oneBased: 2))?.line, #"{"event":"monitor","monitor":2,"workspace":"3"}"#)
        assertEquals(pluginEvent(for: .focusChanged(windowId: nil, workspace: "2"))?.line, #"{"app":"","bundle":"","event":"focus","workspace":"2"}"#)
        assertNil(pluginEvent(for: .modeChanged(mode: "main")))
    }
}
