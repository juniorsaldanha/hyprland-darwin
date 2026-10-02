@testable import AppBundle
import XCTest

final class ConfigLogTest: XCTestCase {
    /// The app log is what you `tail` when a reload "did nothing": it must say which file, and every problem
    func testReloadLinesNameTheFileAndEveryProblem() {
        let url = URL(filePath: "/Users/me/.config/hyprland-darwin/config.toml")
        assertEquals(configLogLines(url: url, errors: [], warnings: [], applied: true), [
            "config: loaded /Users/me/.config/hyprland-darwin/config.toml",
        ])
        assertEquals(configLogLines(url: url, errors: ["[ERROR] bar.height: Must be in [16, 100] range"], warnings: ["[WARNING] x"], applied: true), [
            "config: loaded /Users/me/.config/hyprland-darwin/config.toml with 1 error(s), 1 warning(s)",
            "config:   [ERROR] bar.height: Must be in [16, 100] range",
            "config:   [WARNING] x",
        ])
        assertEquals(configLogLines(url: url, errors: ["[ERROR] broken"], warnings: [], applied: false), [
            "config: NOT applied (kept the previous config): /Users/me/.config/hyprland-darwin/config.toml with 1 error(s), 0 warning(s)",
            "config:   [ERROR] broken",
        ])
    }
}
