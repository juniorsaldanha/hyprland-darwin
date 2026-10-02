import Foundation

public struct SetupSetting: Equatable, Sendable {
    public let domain: String
    public let key: String
    public let value: Bool
    public let note: String

    public init(domain: String, key: String, value: Bool, note: String) {
        self.domain = domain
        self.key = key
        self.value = value
        self.note = note
    }
}

/// Same settings `hyprspace init` applied
public let setupSettings: [SetupSetting] = [
    .init(domain: "com.apple.spaces", key: "spans-displays", value: true, note: "displays share one Space (takes effect after logout)"),
    .init(domain: "com.apple.dock", key: "expose-group-apps", value: true, note: "Mission Control groups windows by app"),
    .init(domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled", value: false, note: "no window-open animation"),
    .init(domain: "NSGlobalDomain", key: "_HIHideMenuBar", value: true, note: "macOS menu bar hidden (the HyprDarwin bar replaces it)"),
]

public struct SetupBackup: Equatable, Codable, Sendable {
    public var entries: [Entry]

    public struct Entry: Equatable, Codable, Sendable {
        public let domain: String
        public let key: String
        public let previous: Bool? // nil: the key was unset

        public init(domain: String, key: String, previous: Bool?) {
            self.domain = domain
            self.key = key
            self.previous = previous
        }
    }

    public init(entries: [Entry]) { self.entries = entries }
}

public enum DefaultsAction: Equatable, Sendable {
    case write(domain: String, key: String, value: Bool)
    case delete(domain: String, key: String)
}

/// Pure. Writes only what differs. The backup keeps the values from the FIRST init;
/// settings added in later versions are appended with their current value.
public func initPlan(
    current: (String, String) -> Bool?,
    existingBackup: SetupBackup?,
    settings: [SetupSetting] = setupSettings,
) -> (actions: [DefaultsAction], backup: SetupBackup) {
    var backup = existingBackup ?? SetupBackup(entries: [])
    var actions: [DefaultsAction] = []
    for setting in settings {
        let now = current(setting.domain, setting.key)
        if !backup.entries.contains(where: { $0.domain == setting.domain && $0.key == setting.key }) {
            backup.entries.append(.init(domain: setting.domain, key: setting.key, previous: now))
        }
        if now != setting.value {
            actions.append(.write(domain: setting.domain, key: setting.key, value: setting.value))
        }
    }
    return (actions, backup)
}

/// Pure. Restore each recorded value; delete keys that were unset before init.
public func undoPlan(_ backup: SetupBackup) -> [DefaultsAction] {
    backup.entries.map { entry in
        entry.previous.map { .write(domain: entry.domain, key: entry.key, value: $0) } ?? .delete(domain: entry.domain, key: entry.key)
    }
}

/// `/usr/bin/defaults`. `domainOverride` (tests) redirects every domain to a throwaway one.
public struct DefaultsTool: Sendable {
    public let domainOverride: String?

    public init(domainOverride: String?) { self.domainOverride = domainOverride }

    public func readBool(_ domain: String, _ key: String) -> Bool? {
        let (status, out) = run(["read", domainOverride ?? domain, key])
        guard status == 0 else { return nil }
        switch out.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1", "true", "YES": return true
            case "0", "false", "NO": return false
            default: return nil
        }
    }

    @discardableResult
    public func apply(_ action: DefaultsAction) -> Bool {
        switch action {
            case .write(let domain, let key, let value):
                run(["write", domainOverride ?? domain, key, "-bool", value ? "true" : "false"]).status == 0
            case .delete(let domain, let key):
                run(["delete", domainOverride ?? domain, key]).status == 0
        }
    }

    private func run(_ arguments: [String]) -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/defaults")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

public func hyprDarwinConfigDir(
    env: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
) -> URL {
    let xdgConfigHome = env["XDG_CONFIG_HOME"].map { URL(filePath: $0) } ?? home.appending(path: ".config/")
    return xdgConfigHome.appending(path: "hyprland-darwin")
}
