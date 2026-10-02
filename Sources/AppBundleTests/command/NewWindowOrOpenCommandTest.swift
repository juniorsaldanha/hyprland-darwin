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

    func testUnknownAppFailsWithAMessage() {
        let io = CmdIoImpl(stdin: .emptyStdin)
        let args = NewWindowOrOpenCmdArgs(rawArgs: []).copy(\.appName, .initialized("HyprDarwinNoSuchApp"))
        let result = NewWindowOrOpenCommand(args: args).run(.defaultEnv, io)
        assertEquals(result, .fail)
        assertEquals(io.stderr, ["App 'HyprDarwinNoSuchApp' not found"])
    }
}
