@testable import AppBundle
import XCTest

@MainActor
final class HyprspaceConfigIntegrationTest: XCTestCase {
    /// The user's real Hyprspace config must load unchanged (spec success criterion).
    func testUserHyprspaceConfigParses() {
        let toml = try! String(contentsOf: projectRoot.appending(component: "docs/config-examples/hyprspace-migrated-config.toml"), encoding: .utf8)
        let result = parseConfig(toml)
        assertEquals(result.errors, [])
        assertEquals(result.config.mouseDrag, MouseDrag(enabled: true, modifier: .maskAlternate))
    }
}
