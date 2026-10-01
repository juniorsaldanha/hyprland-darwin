@testable import AppBundle
import Common
import XCTest

@MainActor
private final class Received {
    var events: [ServerEvent] = []
}

@MainActor
final class EventBusTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        _prevFocusedWorkspaceName = nil
    }

    func testListenerReceivesBroadcastEvent() {
        let received = Received()
        let token = addEventListener { received.events.append($0) }
        defer { removeEventListener(token) }

        broadcastEvent(.workspaceChanged(workspace: "2", prevWorkspace: "1"))

        assertEquals(received.events.map(\.eventType), [.workspaceChanged])
        assertEquals(received.events.first?.workspace, "2")
        assertEquals(received.events.first?.prevWorkspace, "1")
    }

    func testRemovedListenerReceivesNothing() {
        let received = Received()
        let token = addEventListener { received.events.append($0) }
        removeEventListener(token)

        broadcastEvent(.modeChanged(mode: "resize"))

        assertEquals(received.events.count, 0)
    }

    func testWorkspaceSwitchEmitsWorkspaceChanged() async {
        await checkOnFocusChangedCallbacks_nonCancellable() // sync baseline with the test setup state
        let received = Received()
        let token = addEventListener { received.events.append($0) }
        defer { removeEventListener(token) }

        assertTrue(Workspace.get(byName: "b").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()

        let changes = received.events.filter { $0.eventType == .workspaceChanged }
        assertEquals(changes.map(\.workspace), ["b"])
        assertEquals(changes.map(\.prevWorkspace), ["setUpWorkspacesForTests"])
    }
}
