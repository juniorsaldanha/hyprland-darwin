import Foundation

struct PopupItem: Equatable, Sendable, Encodable {
    let label: String
    let run: String?
}

struct WidgetState: Equatable, Sendable, Encodable {
    var icon: String? = nil
    var label: String? = nil
    // periphery:ignore - read by the bar (sub-project 4); encoded by `list-plugins --json`
    var color: String? = nil
    // periphery:ignore - read by the bar (sub-project 4); encoded by `list-plugins --json`
    var iconColor: String? = nil
    // periphery:ignore - read by the bar (sub-project 4); encoded by `list-plugins --json`
    var background: String? = nil
    var hidden: Bool = false
    var popup: [PopupItem] = []

    enum CodingKeys: String, CodingKey {
        case icon, label, color, iconColor = "icon_color", background, hidden, popup
    }

    mutating func apply(_ patch: WidgetPatch) {
        for (key, value) in patch.strings {
            switch key {
                case "icon": icon = value
                case "label": label = value
                case "color": color = value
                case "icon_color": iconColor = value
                case "background": background = value
                default: break
            }
        }
        if let hidden = patch.hidden { self.hidden = hidden }
        if let popup = patch.popup { self.popup = popup }
    }
}

/// A partial update: only the fields the plugin sent
struct WidgetPatch: Equatable, Sendable {
    var strings: [String: String] = [:] // wire names: icon, label, color, icon_color, background
    var hidden: Bool? = nil
    var popup: [PopupItem]? = nil
}

enum PluginLine: Equatable, Sendable {
    case update(WidgetPatch, ignored: [String])
    case run(String)
    case invalid(String)
}

private let stringFields = ["icon", "label", "color", "icon_color", "background"]

func decodePluginLine(_ line: Data) -> PluginLine {
    guard let dict = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return .invalid("not a JSON object") }
    if let run = dict["run"] {
        return (run as? String).map(PluginLine.run) ?? .invalid("'run' must be a string")
    }
    var patch = WidgetPatch()
    var ignored: [String] = []
    for key in stringFields {
        guard let value = dict[key] else { continue }
        if let string = value as? String { patch.strings[key] = string } else { ignored.append(key) }
    }
    if let value = dict["hidden"] {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            patch.hidden = number.boolValue
        } else {
            ignored.append("hidden")
        }
    }
    if let value = dict["popup"] {
        if let popup = decodePopup(value) { patch.popup = popup } else { ignored.append("popup") }
    }
    return .update(patch, ignored: ignored)
}

private func decodePopup(_ value: Any) -> [PopupItem]? {
    guard let array = value as? [Any] else { return nil }
    var items: [PopupItem] = []
    for element in array {
        guard let dict = element as? [String: Any], let label = dict["label"] as? String else { return nil }
        let run = dict["run"]
        if run != nil && !(run is String) { return nil }
        items.append(PopupItem(label: label, run: run as? String))
    }
    return items
}

/// Frames stdout bytes into lines; drops (and reports) lines longer than 64 KB without buffering them
struct LineSplitter {
    static let maxLine = 64 * 1024

    enum Piece: Equatable {
        case line(Data)
        case tooLong
    }

    private var buffer = Data()
    private var discarding = false // inside the rest of an over-long line

    mutating func feed(_ data: Data) -> [Piece] {
        var out: [Piece] = []
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex ..< newline])
            buffer.removeSubrange(buffer.startIndex ... newline)
            if discarding {
                discarding = false
                continue
            }
            if line.count > Self.maxLine {
                out.append(.tooLong)
            } else if !line.isEmpty {
                out.append(.line(line))
            }
        }
        if buffer.count > Self.maxLine {
            if !discarding { out.append(.tooLong) }
            discarding = true
            buffer.removeAll()
        }
        return out
    }

    /// Partial line left at EOF
    mutating func finish() -> [Piece] {
        defer {
            buffer = Data()
            discarding = false
        }
        return discarding || buffer.isEmpty ? [] : [.line(buffer)]
    }
}
