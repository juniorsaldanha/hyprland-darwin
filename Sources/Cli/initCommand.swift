import AppKit
import Common

let initUsage = """
    USAGE: hypr init [-h|--help] [--undo] [--wallpaper <path>]

    Apply the macOS settings HyprDarwin needs (previous values are backed up first),
    write a starter config if none exists, and optionally set the wallpaper on every screen.
      --undo                Restore the settings saved by the first `hypr init`
      --wallpaper <path>    Set this image as the wallpaper on every screen (current Space)
    """

/// Runs in the CLI process: works whether or not HyprDarwin.app is running
func runInit(_ args: [String]) -> Int32 {
    var undo = false
    var wallpaper: String? = nil
    var index = 0
    while index < args.count {
        switch args[index] {
            case "-h", "--help": print(initUsage); return EXIT_CODE_ZERO
            case "--undo": undo = true
            case "--wallpaper":
                guard index + 1 < args.count else { eprint("--wallpaper needs a <path>"); return EXIT_CODE_TWO }
                index += 1
                wallpaper = args[index]
            default: eprint("Unknown option '\(args[index])'\n\(initUsage)"); return EXIT_CODE_TWO
        }
        index += 1
    }

    // Checked before anything changes: a typo in the path must not leave the settings half applied
    let wallpaperUrl = wallpaper.map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
    if let wallpaperUrl, !FileManager.default.fileExists(atPath: wallpaperUrl.path) {
        eprint("Wallpaper: no file at \(wallpaperUrl.path). Nothing was changed.")
        return EXIT_CODE_TWO
    }

    let testDomain = ProcessInfo.processInfo.environment["HYPR_INIT_TEST_DOMAIN"]
    if testDomain != nil, (ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "").isEmpty {
        eprint("HYPR_INIT_TEST_DOMAIN needs XDG_CONFIG_HOME too: otherwise the real config dir would be written")
        return EXIT_CODE_TWO
    }
    let tool = DefaultsTool(domainOverride: testDomain)
    let dir = hyprDarwinConfigDir()
    let backupUrl = dir.appending(path: "setup-backup.json")
    // Missing is fine; present but unreadable is not: it holds the only copy of the original settings
    let existingBackup: SetupBackup?
    if FileManager.default.fileExists(atPath: backupUrl.path) {
        guard let data = try? Data(contentsOf: backupUrl), let backup = try? JSONDecoder().decode(SetupBackup.self, from: data) else {
            eprint("Can't read the backup \(backupUrl.path). It holds your original settings: fix or move it away first. Nothing was changed.")
            return 1
        }
        existingBackup = backup
    } else {
        existingBackup = nil
    }

    if undo {
        guard let backup = existingBackup else { print("Nothing to undo: no \(backupUrl.path)"); return EXIT_CODE_ZERO }
        var ok = true
        for action in undoPlan(backup) { ok = tool.apply(action) && ok }
        if ok { try? FileManager.default.removeItem(at: backupUrl) }
        if testDomain == nil { refreshSystem() }
        print(ok ? "Restored the settings from before `hypr init`." : "Some settings could not be restored; the backup is kept at \(backupUrl.path)")
        return ok ? EXIT_CODE_ZERO : 1
    }

    let settings = setupSettings.filter { setting in
        guard tool.isNonBoolean(setting.domain, setting.key) else { return true }
        eprint("  ! left \(setting.domain) \(setting.key) alone: it holds a non-boolean value")
        return false
    }
    let plan = initPlan(current: tool.readBool, existingBackup: existingBackup, settings: settings)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plan.backup).write(to: backupUrl, options: .atomic)
    } catch {
        eprint("Can't write the backup \(backupUrl.path): \(error.localizedDescription). Nothing was changed.")
        return 1
    }

    var exitCode = EXIT_CODE_ZERO
    for setting in settings {
        let action = DefaultsAction.write(domain: setting.domain, key: setting.key, value: setting.value)
        if !plan.actions.contains(action) {
            print("  ✓ \(setting.note)")
        } else if tool.apply(action) {
            print("  ✓ \(setting.note) (changed)")
        } else {
            eprint("  ✗ \(setting.domain) \(setting.key): defaults write failed")
            exitCode = 1
        }
    }

    let configUrl = dir.appending(path: "config.toml")
    if FileManager.default.fileExists(atPath: configUrl.path) {
        print("  ✓ kept your config: \(configUrl.path)")
    } else if (try? starterConfigToml.write(to: configUrl, atomically: true, encoding: .utf8)) != nil {
        print("  ✓ wrote a starter config: \(configUrl.path)")
    } else {
        eprint("  ✗ can't write \(configUrl.path)")
        exitCode = 1
    }

    if let url = wallpaperUrl {
        if testDomain != nil {
            print("  ✓ wallpaper path ok (not applied in test mode)")
        } else if let error = setWallpaper(url) {
            eprint("  ✗ wallpaper: \(error)")
            exitCode = 1
        } else {
            print("  ✓ wallpaper set on \(NSScreen.screens.count) screen(s) (the current Space on each)")
        }
    }

    if testDomain == nil && !plan.actions.isEmpty { refreshSystem() } // no Dock restart when nothing changed
    print("Backup of the previous settings: \(backupUrl.path) (undo: hypr init --undo)")
    return exitCode
}

/// Dock picks up expose-group-apps on restart; apps pick up _HIHideMenuBar from this notification
private func refreshSystem() {
    let dock = Process()
    dock.executableURL = URL(filePath: "/usr/bin/killall")
    dock.arguments = ["Dock"]
    try? dock.run()
    dock.waitUntilExit()
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true,
    )
}

/// nil on success, the error message otherwise. macOS applies it to the current Space of each screen.
private func setWallpaper(_ url: URL) -> String? {
    do {
        for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
        return nil
    } catch {
        return error.localizedDescription
    }
}
