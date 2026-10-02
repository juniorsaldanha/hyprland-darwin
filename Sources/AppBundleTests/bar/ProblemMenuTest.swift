@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class ProblemMenuTest: XCTestCase {
    /// The ⚠ menu: readable (not greyed out), not screen-wide for long manifest errors, and it leads to the log
    func testItemsAreEnabledWrappedAndComplete() {
        let reason = "invalid: plugin.toml: 'exec' must exist and be executable: /Users/me/.config/hyprland-darwin/plugins/gpu/run.sh is missing"
        let items = problemMenuItems(name: "gpu", reason: reason)
        assertEquals(items.count, 2)
        assertEquals(items[0].representedObject as? String, "gpu: " + reason) // what a click copies
        assertEquals(items[1].title, "Open log")
        for item in items {
            XCTAssertNotNil(item.action)
            XCTAssertNotNil(item.target)
        }
        let shown = items[0].attributedTitle!.string
        XCTAssertTrue(shown.split(separator: "\n").allSatisfy { $0.count <= 60 }, shown)
        assertEquals(shown.replacingOccurrences(of: "\n", with: " "), "gpu: " + reason) // wrapped, nothing dropped
    }
}
