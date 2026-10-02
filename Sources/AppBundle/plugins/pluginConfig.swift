import Common
import Foundation

struct NotchConfig: ConvenienceMutable, Equatable {
    var items: [String] = []
}

struct PluginsConfig: ConvenienceMutable, Equatable {
    var dirs: [String] = ["~/.config/hyprland-darwin/plugins"]
}

/// Native widgets, drawn by the bar itself, never started as plugins
let builtinWidgetNames: Set<String> = ["workspaces", "front-app", "chevron"]

private let notchParserTable: [String: any ParserProtocol<NotchConfig>] = [
    "items": Parser(\.items, parseArrayOfStrings),
]
private let pluginsParserTable: [String: any ParserProtocol<PluginsConfig>] = [
    "dirs": Parser(\.dirs, parseArrayOfStrings),
]

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
