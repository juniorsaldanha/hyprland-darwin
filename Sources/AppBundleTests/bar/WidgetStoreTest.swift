@testable import AppBundle
import Combine
import XCTest

@MainActor
final class WidgetStoreTest: XCTestCase {
    /// Interval plugins report `.running` after every run (gpu: every second); re-publishing an unchanged status
    /// re-renders every bar for nothing
    func testUnchangedStatusDoesNotPublish() {
        let store = WidgetStore()
        var changes = 0
        let subscription = store.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        store.setStatus(.running, for: "gpu")
        store.setStatus(.running, for: "gpu")
        store.setStatus(.running, for: "gpu")
        assertEquals(changes, 1)
        store.setStatus(.failing(1), for: "gpu")
        assertEquals(changes, 2)
    }
}
