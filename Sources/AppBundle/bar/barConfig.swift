import Common

struct BarConfig: ConvenienceMutable, Equatable {
    var enabled: Bool = false
    var height: Int = 40
    var color: UInt32 = 0x4000_0000 // tint over the blur
    var blur: Bool = true
    var font: String = "Hack Nerd Font"
    var iconSize: Int = 17
    var labelSize: Int = 14
    var foreground: UInt32 = 0xE1E1_E1E1
    var autoHide: Bool = true
    var left: [String] = []
    var center: [String] = []
    var right: [String] = [] // displayed left → right
}

private let barParserTable: [String: any ParserProtocol<BarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "height": Parser(\.height, parseIntInRange(16 ... 100)),
    "color": Parser(\.color, parseArgbConfig),
    "blur": Parser(\.blur, parseBool),
    "font": Parser(\.font, parseString),
    "icon-size": Parser(\.iconSize, parseIntInRange(6 ... 48)),
    "label-size": Parser(\.labelSize, parseIntInRange(6 ... 48)),
    "foreground": Parser(\.foreground, parseArgbConfig),
    "auto-hide": Parser(\.autoHide, parseBool),
    "left": Parser(\.left, parseArrayOfStrings),
    "center": Parser(\.center, parseArrayOfStrings),
    "right": Parser(\.right, parseArrayOfStrings),
]

func parseBar(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BarConfig {
    parseTable(raw, BarConfig(), barParserTable, backtrace, &c)
}
