import AppKit
import Common

struct ReloadConfigCommand: Command {
    let args: ReloadConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let result = await reloadConfig_nonCancellable(args: args)
        if !result.stdout.isEmpty {
            io.out(result.stdout)
        }
        if !result.stderr.isEmpty {
            io.err(result.stderr)
        }
        return .from(bool: result.isOk)
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
    let stderr: String
}

@MainActor func reloadConfig_nonCancellable(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
) async -> ReloadConfigResult {
    let result = readConfig(forceConfigUrl: forceConfigUrl)
    let parseResult = result.parseConfigResult
    let warningsAsErrors = args.warningsAsErrors

    var errors = parseResult.errors.map { $0.description(.error) }
    var warnings = parseResult.warnings.map { $0.description(.warning) }
    let containsWarnings = !parseResult.warnings.isEmpty

    if !args.noGui {
        let lines = errors + warnings
        switch true {
            case !errors.isEmpty:
                let msg = failedToParseMsg(configUrl: result.configUrl, errorsCount: parseResult.errors.count, warningsCount: parseResult.warnings.count, lines: lines)
                MessageModel.shared.message = Message(body: msg, containsWarnings: containsWarnings)
            case warningsAsErrors && !warnings.isEmpty:
                let msg = parsedWithWarningsMsg(configUrl: result.configUrl, warningsCount: parseResult.warnings.count, lines: lines)
                MessageModel.shared.message = Message(body: msg, containsWarnings: containsWarnings)
            default:
                MessageModel.shared.message = nil
        }
    }
    if !args.dryRun {
        for line in configLogLines(url: result.configUrl, errors: errors, warnings: warnings, applied: parseResult.allowReloadConfig) {
            appLog.write(line)
        }
    }
    if parseResult.allowReloadConfig && !args.dryRun {
        TrayMenuModel.shared.lastReloadConfigContainedWarnings = containsWarnings
        resetHotKeys()
        config = parseResult.config
        configUrl = result.configUrl
        await activateMode_nonCancellable(activeMode)
        syncStartAtLogin()
        syncFocusFollowsMouse(config)
        syncModifierDrag(config)
        syncPlugins(config)
        syncBar(config)
        syncConfigFileWatcher()
    }

    if warningsAsErrors {
        errors += warnings
        warnings = []
    }

    return ReloadConfigResult(
        isOk: errors.isEmpty,
        stdout: errors.joined(separator: "\n\n"),
        stderr: warnings.joined(separator: "\n\n"),
    )
}

private func failedToParseMsg(configUrl: URL, errorsCount: Int, warningsCount: Int, lines: [String]) -> String {
    let path = configUrl.absoluteURL.path.singleQuoted
    let header = "Failed to parse \(path). \(errorsCount) error(s). \(warningsCount) warning(s)"
    return "\(header)\n\n\(lines.joined(separator: "\n\n"))"
}

private func parsedWithWarningsMsg(configUrl: URL, warningsCount: Int, lines: [String]) -> String {
    let path = configUrl.absoluteURL.path.singleQuoted
    let header = "Parsed \(path) with \(warningsCount) warning(s). Feel free to close this window."
    return "\(header)\n\n\(lines.joined(separator: "\n\n"))"
}

/// Pure. What a reload writes to ~/Library/Logs/hyprland-darwin/hyprdarwin.log: the file, then every problem.
func configLogLines(url: URL, errors: [String], warnings: [String], applied: Bool) -> [String] {
    let counts = errors.isEmpty && warnings.isEmpty ? "" : " with \(errors.count) error(s), \(warnings.count) warning(s)"
    let head = applied ? "config: loaded \(url.path)\(counts)" : "config: NOT applied (kept the previous config): \(url.path)\(counts)"
    return [head] + (errors + warnings).map { "config:   \($0)" }
}
