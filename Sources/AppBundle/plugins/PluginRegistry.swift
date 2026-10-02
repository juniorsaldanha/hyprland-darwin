import Foundation

enum PluginResolution: Equatable, Sendable {
    case ok(dir: String, manifest: PluginManifest)
    case missing(searched: [String])
    case invalid(String)
}

struct ResolvedPlugin: Equatable, Sendable {
    let name: String
    let resolution: PluginResolution
}

/// Pure. Searches user dirs in order, then the bundled dir. The first folder with a plugin.toml wins.
func resolvePlugins(
    names: [String],
    userDirs: [String],
    bundledDir: String?,
    readManifest: (String) -> String?,
    isExecutable: (String) -> Bool,
) -> [ResolvedPlugin] {
    let searchDirs = userDirs.map(expandTilde) + (bundledDir.map { [$0] } ?? [])
    return names.map { name in
        for dir in searchDirs {
            let pluginDir = (dir as NSString).appendingPathComponent(name)
            guard let toml = readManifest(pluginDir) else { continue }
            return switch parsePluginManifest(toml, pluginDir: pluginDir, isExecutable: isExecutable) {
                case .success(let manifest): ResolvedPlugin(name: name, resolution: .ok(dir: pluginDir, manifest: manifest))
                case .failure(let reason): ResolvedPlugin(name: name, resolution: .invalid(reason))
            }
        }
        return ResolvedPlugin(name: name, resolution: .missing(searched: searchDirs))
    }
}

func readPluginManifest(_ pluginDir: String) -> String? {
    try? String(contentsOfFile: (pluginDir as NSString).appendingPathComponent("plugin.toml"), encoding: .utf8)
}

/// `Contents/Resources/bundled-plugins` in the app; the repo copy for debug builds that run outside an app bundle
func bundledPluginsDir() -> String? {
    if let url = Bundle.main.resourceURL?.appending(path: "bundled-plugins"), FileManager.default.fileExists(atPath: url.path) {
        return url.path
    }
    var url = URL(filePath: #filePath)
    while url.path != "/" {
        url.deleteLastPathComponent()
        let candidate = url.appending(path: "bundled-plugins")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
    }
    return nil
}
