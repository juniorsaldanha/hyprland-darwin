@testable import AppBundle
import XCTest

@MainActor
final class BarConfigTest: XCTestCase {
    func testDefaultsMatchSketchybar() {
        let bar = parseConfig("").config.bar
        assertEquals(bar, BarConfig())
        assertFalse(bar.enabled)
        assertEquals(bar.height, 40)
        assertEquals(bar.color, 0x4000_0000)
        assertTrue(bar.blur)
        assertEquals(bar.font, "Hack Nerd Font")
        assertEquals(bar.iconSize, 17)
        assertEquals(bar.labelSize, 14)
        assertEquals(bar.foreground, 0xE1E1_E1E1)
        assertTrue(bar.autoHide)
    }

    func testFullSection() {
        let result = parseConfig(
            """
            [bar]
                enabled = true
                height = 32
                color = '0x80000000'
                blur = false
                font = 'Menlo'
                icon-size = 15
                label-size = 12
                foreground = '0xffffffff'
                auto-hide = false
                left = ['workspaces', 'chevron', 'front-app']
                right = ['clock']
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.bar, BarConfig(
            enabled: true, height: 32, color: 0x8000_0000, blur: false, font: "Menlo", iconSize: 15, labelSize: 12,
            foreground: 0xFFFF_FFFF, autoHide: false, left: ["workspaces", "chevron", "front-app"], center: [], right: ["clock"],
        ))
        assertEquals(result.config.placedPluginNames, ["clock"])
    }

    func testErrorsNameTheKey() {
        assertEquals(parseConfig("bar.height = 10").strErrors, ["[ERROR] bar.height: Must be in [16, 100] range"])
        assertEquals(parseConfig("bar.icon-size = 60").strErrors, ["[ERROR] bar.icon-size: Must be in [6, 48] range"])
        assertEquals(parseConfig("bar.color = 'red'").strErrors, ["[ERROR] bar.color: Invalid color 'red'. Expected 0xAARRGGBB, e.g. 0xff7aa2f7"])
    }
}
