import Common
import Foundation

/// Placement lists only; the Bar sub-project adds the bar's look (height, colors, ...)
struct BarConfig: ConvenienceMutable, Equatable {
    var left: [String] = []
    var center: [String] = []
    var right: [String] = []
}

struct NotchConfig: ConvenienceMutable, Equatable {
    var items: [String] = []
}

struct PluginsConfig: ConvenienceMutable, Equatable {
    var dirs: [String] = ["~/.config/hyprland-darwin/plugins"]
}

/// Native widgets, drawn by the bar itself, never started as plugins
let builtinWidgetNames: Set<String> = ["workspaces", "front-app"]

private let barParserTable: [String: any ParserProtocol<BarConfig>] = [
    "left": Parser(\.left, parseArrayOfStrings),
    "center": Parser(\.center, parseArrayOfStrings),
    "right": Parser(\.right, parseArrayOfStrings),
]
private let notchParserTable: [String: any ParserProtocol<NotchConfig>] = [
    "items": Parser(\.items, parseArrayOfStrings),
]
private let pluginsParserTable: [String: any ParserProtocol<PluginsConfig>] = [
    "dirs": Parser(\.dirs, parseArrayOfStrings),
]

func parseBar(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BarConfig {
    parseTable(raw, BarConfig(), barParserTable, backtrace, &c)
}

func parseNotch(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> NotchConfig {
    parseTable(raw, NotchConfig(), notchParserTable, backtrace, &c)
}

func parsePluginsConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> PluginsConfig {
    parseTable(raw, PluginsConfig(), pluginsParserTable, backtrace, &c)
}

extension Config {
    /// Plugins to run: everything placed in the bar or notch, deduplicated, in order, minus built-in widgets
    var placedPluginNames: [String] {
        var seen = Set<String>()
        return (bar.left + bar.center + bar.right + notch.items)
            .filter { !builtinWidgetNames.contains($0) && seen.insert($0).inserted }
    }
}

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }
