@testable import AppBundle
import Foundation
import XCTest

@MainActor
final class TerminationSignalTest: XCTestCase {
    /// SIGUSR1/2 stand in for SIGTERM: same path, but the test process survives
    func testSignalRunsTheShutdownOnTheMainThread() async {
        let shutdown = expectation(description: "shutdown")
        interceptTermination(SIGUSR1, fallbackAfter: .seconds(60), fallback: {}) {
            XCTAssertTrue(Thread.isMainThread)
            shutdown.fulfill()
        }
        kill(getpid(), SIGUSR1) // process-directed, like killall
        await fulfillment(of: [shutdown], timeout: 2)
    }

    /// `killall HyprDarwin` on a hung app: the main thread never gets to the shutdown, the fallback still exits
    func testFallbackFiresWhileTheMainThreadIsStuck() {
        let fallback = expectation(description: "fallback")
        interceptTermination(SIGUSR2, fallbackAfter: .milliseconds(100), fallback: { fallback.fulfill() }) {}
        kill(getpid(), SIGUSR2)
        Thread.sleep(forTimeInterval: 0.5) // main thread stuck
        wait(for: [fallback], timeout: 0)
    }
}
