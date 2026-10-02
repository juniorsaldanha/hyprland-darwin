import AppKit
import Common

let initUsage = """
    USAGE: hypr init [-h|--help] [--undo] [--wallpaper <path>]

    Apply the macOS settings HyprDarwin needs (previous values are backed up first),
    write a starter config if none exists, and optionally set the wallpaper on every screen.
      --undo                Restore the settings saved by the first `hypr init`
      --wallpaper <path>    Set this image as the wallpaper on every screen
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

    let testDomain = ProcessInfo.processInfo.environment["HYPR_INIT_TEST_DOMAIN"]
    let tool = DefaultsTool(domainOverride: testDomain)
    let dir = hyprDarwinConfigDir()
    let backupUrl = dir.appending(path: "setup-backup.json")
    let existingBackup = (try? Data(contentsOf: backupUrl)).flatMap { try? JSONDecoder().decode(SetupBackup.self, from: $0) }

    if undo {
        guard let backup = existingBackup else { print("Nothing to undo: no \(backupUrl.path)"); return EXIT_CODE_ZERO }
        var ok = true
        for action in undoPlan(backup) { ok = tool.apply(action) && ok }
        if ok { try? FileManager.default.removeItem(at: backupUrl) }
        if testDomain == nil { refreshSystem() }
        print(ok ? "Restored the settings from before `hypr init`." : "Some settings could not be restored; the backup is kept at \(backupUrl.path)")
        return ok ? EXIT_CODE_ZERO : 1
    }

    let plan = initPlan(current: tool.readBool, existingBackup: existingBackup)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plan.backup).write(to: backupUrl)
    } catch {
        eprint("Can't write the backup \(backupUrl.path): \(error.localizedDescription). Nothing was changed.")
        return 1
    }

    var exitCode = EXIT_CODE_ZERO
    for setting in setupSettings {
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

    if let wallpaper {
        let url = URL(filePath: (wallpaper as NSString).expandingTildeInPath)
        do {
            for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
            print("  ✓ wallpaper set on \(NSScreen.screens.count) screen(s)")
        } catch {
            eprint("  ✗ wallpaper: \(error.localizedDescription)")
            exitCode = 1
        }
    }

    if testDomain == nil { refreshSystem() }
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
