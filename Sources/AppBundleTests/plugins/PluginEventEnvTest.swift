@testable import AppBundle
import XCTest

final class PluginEventEnvTest: XCTestCase {
    func testEventEnvironment() {
        assertEquals(eventEnvironment(.wake, line: #"{"event":"wake"}"#, button: nil), ["HYPR_EVENT": "wake", "HYPR_EVENT_JSON": #"{"event":"wake"}"#])
        assertEquals(eventEnvironment(.click, line: "{}", button: "left"), ["HYPR_EVENT": "click", "HYPR_EVENT_JSON": "{}", "HYPR_BUTTON": "left"])
    }
}
