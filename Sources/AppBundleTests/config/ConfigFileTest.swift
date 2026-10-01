@testable import AppBundle
import XCTest

final class ConfigFileTest: XCTestCase {
    func testDefaultsToDotConfig() {
        let url = hyprDarwinConfigUrl(env: [:], home: URL(filePath: "/Users/u"))
        assertEquals(url.path, "/Users/u/.config/hyprland-darwin/config.toml")
    }

    func testHonorsXdgConfigHome() {
        let url = hyprDarwinConfigUrl(env: ["XDG_CONFIG_HOME": "/tmp/xdg"], home: URL(filePath: "/Users/u"))
        assertEquals(url.path, "/tmp/xdg/hyprland-darwin/config.toml")
    }
}
