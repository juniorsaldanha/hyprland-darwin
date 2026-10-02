@testable import AppBundle
import XCTest

@MainActor
final class BarWorkspacesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// Switching to a workspace that isn't in persistent-workspaces (and has no windows) must still show its pill
    func testFocusedNonPersistentWorkspaceIsListed() {
        config.persistentWorkspaces = ["1", "2"]
        Workspace.garbageCollectUnusedWorkspaces()
        assertTrue(Workspace.get(byName: "7").focusWorkspace())
        Workspace.garbageCollectUnusedWorkspaces()
        updateTrayText()
        let names = TrayMenuModel.shared.workspaces.map(\.name)
        XCTAssertTrue(names.contains("7"), "\(names)")
        assertEquals(TrayMenuModel.shared.workspaces.first { $0.name == "7" }?.isFocused, true)
    }
}
