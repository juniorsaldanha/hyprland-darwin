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

    func testUnknownAppFailsWithAMessage() async {
        let io = CmdIoImpl(stdin: .emptyStdin)
        let args = NewWindowOrOpenCmdArgs(rawArgs: []).copy(\.appName, .initialized("HyprDarwinNoSuchApp"))
        let result = await NewWindowOrOpenCommand(args: args).run(.defaultEnv, io)
        assertEquals(result, .fail)
        assertEquals(io.stderr, ["App 'HyprDarwinNoSuchApp' not found"])
    }

    /// `open -a` waits for the app to launch: the main actor (keys, tiling, bar) must keep running meanwhile
    func testWaitingForAProcessDoesNotBlockTheMainActor() async {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["0.5"]
        var ticks = 0
        let ticker = Task.startUnstructured { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let status = await runAndWait(process)
        ticker.cancel()
        assertEquals(status, 0)
        XCTAssertGreaterThanOrEqual(ticks, 3, "the main actor stalled while waiting")
        let missing = Process()
        missing.executableURL = URL(filePath: "/nonexistent/hypr-test")
        assertEquals(await runAndWait(missing), nil) // can't start: nil, no hang
    }
}
