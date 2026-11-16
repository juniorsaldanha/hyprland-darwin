@testable import AppBundle
import Common
import XCTest

@MainActor
final class PinAppCommandTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        pinnedApps = [:]
    }

    override func tearDown() async throws { pinnedApps = [:] }

    func testPinToggleAndNewWindowsFollowThePin() async {
        let workspaceA = Workspace.get(byName: "a")
        _ = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer).focusWindow()

        await parseCommand("pin-app").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(pinnedApps, ["bobko.AeroSpace.test-app": "a"])

        // A new window of the pinned app, opened elsewhere, lands in workspace a
        let detected = TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        await tryOnWindowDetected(detected)
        assertEquals(detected.nodeWorkspace?.name, "a")

        // Running it again in the same workspace unpins
        await parseCommand("pin-app").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(pinnedApps, [:])
    }
}
