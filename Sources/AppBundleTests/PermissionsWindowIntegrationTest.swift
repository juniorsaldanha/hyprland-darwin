@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class PermissionsWindowIntegrationTest: XCTestCase {
    private func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Hidden (Cmd-H, ordered out) isn't closed: the ✓/✗ rows must still be current when the window comes back
    func testKeepsRefreshingWhileHiddenAndStopsWhenClosed() {
        _ = NSApplication.shared
        showPermissionsWindow()
        defer { permissionsWindow?.close() }
        permissionsWindow?.orderOut(nil) // what Cmd-H does to it
        let before = permissionsRefreshCount
        spin(2.5)
        XCTAssertGreaterThan(permissionsRefreshCount, before, "stopped refreshing while hidden")

        permissionsWindow?.close()
        spin(1.2)
        let afterClose = permissionsRefreshCount
        spin(2.2)
        assertEquals(permissionsRefreshCount, afterClose) // closed: no more polling
    }
}
