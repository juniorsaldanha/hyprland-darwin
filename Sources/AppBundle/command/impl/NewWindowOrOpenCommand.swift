import AppKit
import Common

struct NewWindowOrOpenCommand: Command {
    let args: NewWindowOrOpenCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let name = args.appName.val
        if let app = NSWorkspace.shared.runningApplications.first(where: { appNameMatches(name, $0.localizedName) }) {
            app.activate(options: .activateIgnoringOtherApps)
            postCmdN(to: app.processIdentifier)
            return .succ
        }
        // `open -a` exits within ~0.1 s once Launch Services resolves the name: non-zero means no such app
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-a", name]
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return .fail(io.err("Can't run /usr/bin/open")) }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? .succ : .fail(io.err("App '\(name)' not found"))
    }
}

func appNameMatches(_ query: String, _ appName: String?) -> Bool {
    appName?.caseInsensitiveCompare(query) == .orderedSame
}

private let keyCodeN: CGKeyCode = 0x2D // kVK_ANSI_N

/// Sent straight to the app's process, so it lands there even if activation hasn't finished yet.
private func postCmdN(to pid: pid_t) {
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeN, keyDown: keyDown)
        event?.flags = .maskCommand
        event?.postToPid(pid)
    }
}
