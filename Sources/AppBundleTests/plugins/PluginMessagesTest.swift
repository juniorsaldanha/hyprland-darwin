@testable import AppBundle
import XCTest

final class PluginMessagesTest: XCTestCase {
    private func decode(_ s: String) -> PluginLine { decodePluginLine(Data(s.utf8)) }

    func testWidgetUpdate() {
        assertEquals(decode(#"{"icon":"X","label":"42%","color":"0xffe1e1e1","icon_color":"0xff000000","background":"0x40ffffff"}"#),
                     .update(WidgetPatch(strings: ["icon": "X", "label": "42%", "color": "0xffe1e1e1", "icon_color": "0xff000000", "background": "0x40ffffff"]), ignored: []))
    }

    func testHiddenMustBeBool() {
        assertEquals(decode(#"{"hidden":true}"#), .update(WidgetPatch(hidden: true), ignored: []))
        assertEquals(decode(#"{"hidden":1}"#), .update(WidgetPatch(), ignored: ["hidden"]))
    }

    func testWrongTypeFieldIgnoredOthersKept() {
        assertEquals(decode(#"{"label":42,"icon":"ok"}"#), .update(WidgetPatch(strings: ["icon": "ok"]), ignored: ["label"]))
    }

    func testUnknownFieldsIgnoredSilently() {
        assertEquals(decode(#"{"label":"a","future":1}"#), .update(WidgetPatch(strings: ["label": "a"]), ignored: []))
    }

    func testRunCommand() {
        assertEquals(decode(#"{"run":"workspace 2","label":"x"}"#), .run("workspace 2"))
        assertEquals(decode(#"{"run":5}"#), .invalid("'run' must be a string"))
    }

    func testInvalidJsonAndNonObject() {
        assertEquals(decode("not json"), .invalid("not a JSON object"))
        assertEquals(decode("[1,2]"), .invalid("not a JSON object"))
        assertEquals(decodePluginLine(Data([0x7B, 0xFF, 0xFE, 0x7D])), .invalid("not a JSON object"))
    }

    func testPatchMergeKeepsEarlierFields() {
        var state = WidgetState()
        state.apply(WidgetPatch(strings: ["icon": "A", "label": "1"]))
        state.apply(WidgetPatch(strings: ["label": "2"], hidden: true))
        assertEquals(state, WidgetState(icon: "A", label: "2", hidden: true))
        state.apply(WidgetPatch(hidden: false))
        assertFalse(state.hidden)
    }
}

final class LineSplitterTest: XCTestCase {
    private func lines(_ pieces: [LineSplitter.Piece]) -> [String] {
        pieces.map {
            switch $0 {
                case .line(let d): String(decoding: d, as: UTF8.self)
                case .tooLong: "<tooLong>"
            }
        }
    }

    func testSplitAcrossReads() {
        var s = LineSplitter()
        assertEquals(lines(s.feed(Data("{\"a\":".utf8))), [])
        assertEquals(lines(s.feed(Data("1}\n{\"b\":2}\n{\"c\"".utf8))), ["{\"a\":1}", "{\"b\":2}"])
        assertEquals(lines(s.finish()), ["{\"c\""])
    }

    func testEmptyLinesSkipped() {
        var s = LineSplitter()
        assertEquals(lines(s.feed(Data("\n\nx\n".utf8))), ["x"])
    }

    func testGiantLineThenGoodLine() {
        var s = LineSplitter()
        let giant = Data(repeating: 0x61, count: LineSplitter.maxLine + 10)
        var out = lines(s.feed(giant))
        out += lines(s.feed(Data("aaa\nok\n".utf8))) // tail of the giant line, then a good one
        assertEquals(out, ["<tooLong>", "ok"])
    }

    func testGiantLineInOneChunkWithNewline() {
        var s = LineSplitter()
        var chunk = Data(repeating: 0x61, count: LineSplitter.maxLine + 1)
        chunk.append(Data("\nok\n".utf8))
        assertEquals(lines(s.feed(chunk)), ["<tooLong>", "ok"])
    }
}
