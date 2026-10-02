import Common
import Foundation

enum BorderStyle: Equatable, Sendable {
    case solid(UInt32) // 0xAARRGGBB
    case gradient(UInt32, UInt32) // top-left -> bottom-right
}

struct BordersConfig: ConvenienceMutable, Equatable {
    var enabled: Bool = false
    var width: Int = 5
    var radius: Int = 10
    var active: BorderStyle = .gradient(0xFF7A_A2F7, 0xFFBB_9AF7)
    var inactive: BorderStyle = .solid(0x8041_4868)
}

private let bordersParserTable: [String: any ParserProtocol<BordersConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width, parseIntInRange(1 ... 50)),
    "radius": Parser(\.radius, parseIntInRange(0 ... 100)),
    "active": Parser(\.active, parseBorderStyleConfig),
    "inactive": Parser(\.inactive, parseSolidBorderStyleConfig),
]

func parseBorders(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BordersConfig {
    parseTable(raw, BordersConfig(), bordersParserTable, backtrace, &c)
}

func parseIntInRange(_ range: ClosedRange<Int>) -> @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    { raw, backtrace in
        parseInt(raw, backtrace).flatMap { value in
            range.contains(value)
                ? .success(value)
                : .failure(.init(backtrace, "Must be in [\(range.lowerBound), \(range.upperBound)] range"))
        }
    }
}

private func parseBorderStyleConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<BorderStyle> {
    parseString(raw, backtrace).flatMap { str in parseBorderStyle(str).mapError { .init(backtrace, $0) } }
}

private func parseSolidBorderStyleConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<BorderStyle> {
    parseBorderStyleConfig(raw, backtrace).flatMap { style in
        if case .solid = style { .success(style) } else { .failure(.init(backtrace, "Must be a single color")) }
    }
}

func parseBorderStyle(_ str: String) -> ResOrStr<BorderStyle> {
    let s = str.trimmingCharacters(in: .whitespaces)
    let prefix = "gradient("
    guard s.hasPrefix(prefix), s.hasSuffix(")") else { return parseArgb(s).map(BorderStyle.solid) }
    let parts = s.dropFirst(prefix.count).dropLast()
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2 else { return .failure("gradient() takes exactly 2 colors, got \(parts.count)") }
    return parseArgb(parts[0]).flatMap { a in parseArgb(parts[1]).map { b in .gradient(a, b) } }
}

func parseArgb(_ s: String) -> ResOrStr<UInt32> {
    let digits = s.dropFirst(2)
    // UInt32(_:radix:) alone would accept a sign ('0x+1234567')
    guard s.hasPrefix("0x") || s.hasPrefix("0X"), s.count == 10, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
        return .failure("Invalid color '\(s)'. Expected 0xAARRGGBB, e.g. 0xff7aa2f7")
    }
    return .success(value)
}

func parseArgbConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<UInt32> {
    parseString(raw, backtrace).flatMap { str in parseArgb(str).mapError { .init(backtrace, $0) } }
}
