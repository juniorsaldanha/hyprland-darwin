import Foundation

func encodePluginEvent(_ kind: PluginEventKind, _ fields: [String: Any] = [:]) -> String {
    var object = fields
    object["event"] = kind.rawValue
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

@MainActor func pluginEvent(for event: ServerEvent) -> (kind: PluginEventKind, line: String)? {
    switch event.eventType {
        case .workspaceChanged:
            return (.workspace, encodePluginEvent(.workspace, ["focused": event.workspace ?? "", "prev": event.prevWorkspace ?? ""]))
        case .focusChanged:
            let app = event.windowId.flatMap { Window.get(byId: $0) }?.app
            return (.focus, encodePluginEvent(.focus, ["app": app?.name ?? "", "bundle": app?.rawAppBundleId ?? "", "workspace": event.workspace ?? ""]))
        case .focusedMonitorChanged:
            return (.monitor, encodePluginEvent(.monitor, ["workspace": event.workspace ?? "", "monitor": event.monitorId ?? 0]))
        case .modeChanged, .windowDetected, .bindingTriggered:
            return nil
    }
}
