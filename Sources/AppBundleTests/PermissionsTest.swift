@testable import AppBundle
import XCTest

final class PermissionWatcherTest: XCTestCase {
    func testTrustedAtStartDoesNothing() {
        var watcher = PermissionWatcher()
        assertEquals(watcher.update(isTrusted: true, isServerEnabled: true), .none)
    }

    func testRevokePausesOnceAndDisablesServer() {
        var watcher = PermissionWatcher()
        assertEquals(watcher.update(isTrusted: false, isServerEnabled: true), .pause(disableServer: true))
        assertEquals(watcher.update(isTrusted: false, isServerEnabled: false), .none) // no notification spam per poll
    }

    func testRegrantResumesAndReEnables() {
        var watcher = PermissionWatcher()
        _ = watcher.update(isTrusted: false, isServerEnabled: true)
        assertEquals(watcher.update(isTrusted: true, isServerEnabled: false), .resume(enableServer: true))
        assertEquals(watcher.update(isTrusted: true, isServerEnabled: true), .none)
    }

    func testUserDisabledTilingStaysDisabled() {
        var watcher = PermissionWatcher()
        assertEquals(watcher.update(isTrusted: false, isServerEnabled: false), .pause(disableServer: false))
        assertEquals(watcher.update(isTrusted: true, isServerEnabled: false), .resume(enableServer: false))
    }

    func testFlappingNotifiesOncePerRevoke() {
        var watcher = PermissionWatcher()
        assertEquals(watcher.update(isTrusted: false, isServerEnabled: true), .pause(disableServer: true))
        assertEquals(watcher.update(isTrusted: true, isServerEnabled: false), .resume(enableServer: true))
        assertEquals(watcher.update(isTrusted: false, isServerEnabled: true), .pause(disableServer: true))
        assertEquals(watcher.update(isTrusted: false, isServerEnabled: false), .none)
    }
}

@MainActor
final class PermissionsModelTest: XCTestCase {
    func testOnlyAccessibilityIsRequired() {
        assertEquals(PermissionKind.allCases.filter(\.isRequired), [.accessibility])
        let model = PermissionsModel()
        model.accessibility = true
        model.notifications = false
        assertTrue(model.allRequiredGranted)
        model.accessibility = false
        model.notifications = true
        assertFalse(model.allRequiredGranted)
    }
}
