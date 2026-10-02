@testable import AppBundle
import XCTest

final class SystemEventsIntegrationTest: XCTestCase {
    func testPowerSourceIsAcOrBatteryWhenKnown() {
        if let source = currentPowerSource() { assertTrue(["ac", "battery"].contains(source)) }
    }

    func testVolumeLevelInRangeWhenThereIsAnOutputDevice() {
        if let level = currentVolumeLevel() { assertTrue((0 ... 100).contains(level)) }
    }
}
