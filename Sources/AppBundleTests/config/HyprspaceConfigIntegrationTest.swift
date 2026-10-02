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

    /// After migrating: the user's config plus a [borders] section replacing JankyBorders
    func testUserConfigWithBordersSectionParses() {
        let toml = try! String(contentsOf: projectRoot.appending(component: "docs/config-examples/hyprspace-migrated-config.toml"), encoding: .utf8)
        let result = parseConfig(toml + """

            [borders]
                enabled = true
                width = 5
                radius = 10
                active = 'gradient(0xff7aa2f7,0xffbb9af7)'
                inactive = '0x80414868'
            """)
        assertEquals(result.errors, [])
        assertTrue(result.config.borders.enabled)
    }

    func testUserConfigWithBarAndPluginsSectionsParses() {
        let toml = try! String(contentsOf: projectRoot.appending(component: "docs/config-examples/hyprspace-migrated-config.toml"), encoding: .utf8)
        let result = parseConfig(toml + """

            [bar]
                left = ['workspaces', 'front-app']
                right = ['clock', 'battery', 'cpu', 'ram', 'disk']
            [plugins]
                dirs = ['~/.config/hyprland-darwin/plugins']
            """)
        assertEquals(result.errors, [])
        assertEquals(result.config.placedPluginNames, ["clock", "battery", "cpu", "ram", "disk"])
    }

    func testUserConfigWithFullBarSectionParses() {
        let toml = try! String(contentsOf: projectRoot.appending(component: "docs/config-examples/hyprspace-migrated-config.toml"), encoding: .utf8)
        let result = parseConfig(toml + """

            [bar]
                enabled = true
                left = ['workspaces', 'chevron', 'front-app']
                right = ['disk', 'ram', 'gpu', 'cpu', 'network', 'volume', 'battery', 'clock']
            """)
        assertEquals(result.errors, [])
        assertEquals(result.config.placedPluginNames, ["disk", "ram", "gpu", "cpu", "network", "volume", "battery", "clock"])
    }
}
