@testable import AppBundle
import XCTest

@MainActor
final class PluginConfigTest: XCTestCase {
    func testDefaults() {
        let config = parseConfig("").config
        assertEquals(config.bar, BarConfig())
        assertEquals(config.notch.items, [])
        assertEquals(config.plugins.dirs, ["~/.config/hyprland-darwin/plugins"])
        assertEquals(config.placedPluginNames, [])
    }

    func testPlacementListsParse() {
        let result = parseConfig(
            """
            [bar]
                enabled = true
                left = ['workspaces', 'front-app']
                center = ['music']
                right = ['clock', 'gpu']
            [notch]
                items = ['music', 'timer']
            [plugins]
                dirs = ['~/my-plugins']
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.bar, BarConfig(enabled: true, left: ["workspaces", "front-app"], center: ["music"], right: ["clock", "gpu"]))
        assertEquals(result.config.notch.items, ["music", "timer"])
        assertEquals(result.config.plugins.dirs, ["~/my-plugins"])
    }

    func testPlacedPluginNamesDedupesKeepsOrderSkipsBuiltins() {
        let result = parseConfig(
            """
            bar.enabled = true
            bar.left = ['workspaces', 'gpu']
            bar.right = ['clock', 'front-app', 'gpu']
            notch.items = ['music', 'clock']
            """,
        )
        assertEquals(result.config.placedPluginNames, ["gpu", "clock", "music"])
    }

    func testWrongTypeNamesTheKey() {
        let result = parseConfig("bar.left = 'clock'")
        assertTrue(result.strErrors.first?.hasPrefix("[ERROR] bar.left:") == true)
    }

    func testExpandTilde() {
        assertEquals(expandTilde("~/x"), NSHomeDirectory() + "/x")
        assertEquals(expandTilde("/abs"), "/abs")
    }

    func testNoPluginsRunWhileTheBarIsDisabled() {
        // the shipped default config lists bar widgets with bar.enabled = false: nothing may run hidden
        let result = parseConfig("bar.right = ['cpu', 'gpu']\nnotch.items = ['music']")
        assertEquals(result.config.placedPluginNames, [])
    }
}
