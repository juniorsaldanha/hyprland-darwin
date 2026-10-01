@testable import AppBundle
import Common
import XCTest

@MainActor
final class NewWindowOrOpenCommandTest: XCTestCase {
    func testParse() {
        assertNil(parseCommand("new-window-or-open rio").errorOrNil)
        assertEquals(parseCommand("new-window-or-open").errorOrNil, "ERROR: Argument '<app-name>' is mandatory")
    }

    func testAppNameMatchIsCaseInsensitive() {
        assertTrue(appNameMatches("rio", "Rio"))
        assertTrue(appNameMatches("Arc", "Arc"))
        assertFalse(appNameMatches("Arc", "Archive Utility"))
        assertFalse(appNameMatches("rio", nil))
    }
}
