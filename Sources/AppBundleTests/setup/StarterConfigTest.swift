@testable import AppBundle
import Common
import XCTest

@MainActor
final class StarterConfigTest: XCTestCase {
    func testStarterConfigParsesCleanly() {
        let result = parseConfig(starterConfigToml)
        assertEquals(result.errors, [])
        assertEquals(result.warnings, [])
        assertTrue(result.config.bar.enabled)
        assertTrue(result.config.borders.enabled)
        assertTrue(result.config.mouseDrag.enabled)
        assertEquals(result.config.placedPluginNames, ["disk", "ram", "gpu", "cpu", "network", "volume", "battery", "clock"])
    }
}
