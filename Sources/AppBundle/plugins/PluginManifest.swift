import Common
import Foundation
import TOMLDecoder

enum PluginMode: Equatable, Sendable {
    case interval(seconds: Int)
    case stream

    var name: String {
        switch self {
            case .interval: "interval"
            case .stream: "stream"
        }
    }
}

/// Events a plugin can subscribe to. 'click' and 'power' arrive with the bar.
enum PluginEventKind: String, CaseIterable, Sendable {
    case workspace, focus, monitor, wake
}

struct PluginManifest: Equatable, Sendable {
    let execPath: String // absolute, standardized
    let mode: PluginMode
    let events: Set<PluginEventKind>
}

func parsePluginManifest(_ toml: String, pluginDir: String, isExecutable: (String) -> Bool) -> ResOrStr<PluginManifest> {
    let dict: [String: Any]
    do {
        dict = try .init(try TOMLTable(source: toml))
    } catch {
        return .failure("plugin.toml: \(error)")
    }
    guard let api = tomlInt(dict["api"]) else { return .failure("missing 'api'") }
    guard api == 1 else { return .failure("unsupported api \(api), expected 1") }
    guard let exec = dict["exec"] as? String, !exec.isEmpty else { return .failure("missing 'exec'") }
    let execPath = ((exec.hasPrefix("/") ? exec : (pluginDir as NSString).appendingPathComponent(exec)) as NSString).standardizingPath
    guard isExecutable(execPath) else { return .failure("exec '\(exec)' not found or not executable") }

    let mode: PluginMode
    switch dict["mode"] as? String {
        case "stream":
            mode = .stream
        case "interval":
            guard let seconds = tomlInt(dict["interval"]), seconds >= 1 else { return .failure("interval mode needs 'interval' >= 1") }
            mode = .interval(seconds: seconds)
        default:
            return .failure("mode must be 'interval' or 'stream'")
    }

    var events = Set<PluginEventKind>()
    if let raw = dict["events"] {
        guard let array = raw as? [Any] else { return .failure("'events' must be an array") }
        for element in array {
            guard let name = element as? String, let kind = PluginEventKind(rawValue: name) else { return .failure("unknown event '\(element)'") }
            events.insert(kind)
        }
    }
    return .success(PluginManifest(execPath: execPath, mode: mode, events: events))
}

private func tomlInt(_ value: Any?) -> Int? {
    switch value {
        case let v as Int: v
        case let v as Int64: Int(v)
        default: nil
    }
}
