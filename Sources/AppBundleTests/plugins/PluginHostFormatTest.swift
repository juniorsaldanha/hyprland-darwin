@testable import AppBundle
import XCTest

final class PluginHostFormatTest: XCTestCase {
    func testStatusDescriptions() {
        assertEquals(PluginStatus.running.description, "running")
        assertEquals(PluginStatus.failing(3).description, "failing (3)")
        assertEquals(PluginStatus.restarting(in: 1.2).description, "restarting in 2s")
        assertEquals(PluginStatus.stopped("crashed 5 times within 60 s").description, "stopped: crashed 5 times within 60 s")
        assertEquals(PluginStatus.missing("no plugin folder in /a").description, "missing: no plugin folder in /a")
        assertEquals(PluginStatus.invalid("missing 'api'").description, "invalid: missing 'api'")
    }

    func testFormatLine() {
        let s = PluginSnapshot(name: "gpu", mode: "stream", status: "running", restarts: 2, widget: WidgetState(label: "42%"))
        assertEquals(formatPluginLine(s), "gpu | stream | running | 2 | 42%")
    }
}
