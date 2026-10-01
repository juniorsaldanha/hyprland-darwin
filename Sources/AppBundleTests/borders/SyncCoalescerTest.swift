@testable import AppBundle
import XCTest

@MainActor
final class SyncCoalescerTest: XCTestCase {
    func testManyRequestsInOneTurnRunOnce() {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        var runs = 0
        let coalescer = SyncCoalescer(schedule: { scheduled.append($0) }, action: { runs += 1 })

        coalescer.request()
        coalescer.request()
        coalescer.request()
        assertEquals(scheduled.count, 1)
        assertEquals(runs, 0)

        scheduled.removeFirst()()
        assertEquals(runs, 1)
    }

    func testRequestAfterRunSchedulesAgain() {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        var runs = 0
        let coalescer = SyncCoalescer(schedule: { scheduled.append($0) }, action: { runs += 1 })

        coalescer.request()
        scheduled.removeFirst()()
        coalescer.request()
        assertEquals(scheduled.count, 1)
        scheduled.removeFirst()()
        assertEquals(runs, 2)
    }
}
