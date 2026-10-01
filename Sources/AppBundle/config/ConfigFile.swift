import Common
import Foundation

func hyprDarwinConfigUrl(
    env: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
) -> URL {
    let xdgConfigHome = env["XDG_CONFIG_HOME"].map { URL(filePath: $0) } ?? home.appending(path: ".config/")
    return xdgConfigHome.appending(path: "hyprland-darwin").appending(path: "config.toml")
}

func findCustomConfigUrl() -> ConfigFile {
    let candidate = serverArgs.configLocation.map { URL(filePath: $0) } ?? hyprDarwinConfigUrl()
    return FileManager.default.fileExists(atPath: candidate.path) ? .file(candidate) : .noCustomConfigExists
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
