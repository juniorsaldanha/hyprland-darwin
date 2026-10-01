import Common
import CoreGraphics

struct MouseDrag: ConvenienceMutable, Equatable {
    var enabled: Bool = false
    var modifier: CGEventFlags = .maskAlternate
}

private let mouseDragParserTable: [String: any ParserProtocol<MouseDrag>] = [
    "enabled": Parser(\.enabled, parseBool),
    "modifier": Parser(\.modifier, parseMouseDragModifier),
]

func parseMouseDrag(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> MouseDrag {
    parseTable(raw, MouseDrag(), mouseDragParserTable, backtrace, &c)
}

private let modifierFlagsByName: [String: CGEventFlags] = [
    "alt": .maskAlternate,
    "cmd": .maskCommand,
    "ctrl": .maskControl,
    "shift": .maskShift,
]

private func parseMouseDragModifier(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<CGEventFlags> {
    guard let str = raw.asStringOrNil else {
        return .failure(.init(backtrace, expectedActualTypeError(expected: .string, actual: raw.tomlType)))
    }
    var flags: CGEventFlags = []
    for part in str.split(separator: "-") {
        guard let flag = modifierFlagsByName[String(part)] else {
            return .failure(.init(backtrace, "Unknown modifier '\(part)'. Possible values: alt, cmd, ctrl, shift (combine with '-', e.g. 'cmd-alt')"))
        }
        flags.insert(flag)
    }
    if flags.isEmpty {
        return .failure(.init(backtrace, "Modifier must not be empty"))
    }
    return .success(flags)
}
