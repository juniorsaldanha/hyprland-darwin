@testable import AppBundle
import XCTest

@MainActor
final class BordersConfigTest: XCTestCase {
    func testDefaultsAndNoSectionMeansDisabled() {
        let result = parseConfig("")
        assertEquals(result.config.borders, BordersConfig())
        assertFalse(result.config.borders.enabled)
        assertEquals(BordersConfig().width, 5)
        assertEquals(BordersConfig().radius, 10)
        assertEquals(BordersConfig().active, .gradient(0xFF7A_A2F7, 0xFFBB_9AF7))
        assertEquals(BordersConfig().inactive, .solid(0x8041_4868))
    }

    func testFullSection() {
        let result = parseConfig(
            """
            [borders]
                enabled = true
                width = 3
                radius = 12
                active = '0xffff0000'
                inactive = '0x40000000'
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.borders, BordersConfig(enabled: true, width: 3, radius: 12, active: .solid(0xFFFF_0000), inactive: .solid(0x4000_0000)))
    }

    func testGradient() {
        assertEquals(parseBorderStyle("gradient(0xff7aa2f7,0xffbb9af7)"), .success(.gradient(0xFF7A_A2F7, 0xFFBB_9AF7)))
    }

    func testUppercaseAndSpacesAccepted() {
        assertEquals(parseBorderStyle("  gradient( 0xFF7AA2F7 , 0xffbb9af7 ) "), .success(.gradient(0xFF7A_A2F7, 0xFFBB_9AF7)))
        assertEquals(parseArgb("0xFF414868"), .success(0xFF41_4868))
    }

    func testBadColor() {
        let result = parseConfig("borders.active = 'blue'")
        assertEquals(result.strErrors, ["[ERROR] borders.active: Invalid color 'blue'. Expected 0xAARRGGBB, e.g. 0xff7aa2f7"])
    }

    func testRgbWithoutAlphaRejected() {
        assertEquals(parseArgb("0x7aa2f7"), .failure("Invalid color '0x7aa2f7'. Expected 0xAARRGGBB, e.g. 0xff7aa2f7"))
    }

    func testGradientNeedsExactlyTwoColors() {
        assertEquals(parseBorderStyle("gradient(0xff7aa2f7)"), .failure("gradient() takes exactly 2 colors, got 1"))
        assertEquals(parseBorderStyle("gradient(0xff7aa2f7,0xffbb9af7,0xff000000)"), .failure("gradient() takes exactly 2 colors, got 3"))
    }

    func testInactiveMustBeSolid() {
        let result = parseConfig("borders.inactive = 'gradient(0xff7aa2f7,0xffbb9af7)'")
        assertEquals(result.strErrors, ["[ERROR] borders.inactive: Must be a single color"])
    }

    func testWidthRange() {
        assertEquals(parseConfig("borders.width = 0").strErrors, ["[ERROR] borders.width: Must be in [1, 50] range"])
        assertEquals(parseConfig("borders.width = 51").strErrors, ["[ERROR] borders.width: Must be in [1, 50] range"])
        assertEquals(parseConfig("borders.width = 50").errors, [])
    }

    func testRadiusRange() {
        assertEquals(parseConfig("borders.radius = -1").strErrors, ["[ERROR] borders.radius: Must be in [0, 100] range"])
        assertEquals(parseConfig("borders.radius = 101").strErrors, ["[ERROR] borders.radius: Must be in [0, 100] range"])
        assertEquals(parseConfig("borders.radius = 0").errors, [])
    }
}
