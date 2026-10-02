@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListPluginsCommandTest: XCTestCase {
    func testParse() {
        assertNil(parseCommand("list-plugins").errorOrNil)
        assertNil(parseCommand("list-plugins --json").errorOrNil)
        assertNotNil(parseCommand("list-plugins --nope").errorOrNil)
    }
}
