import AppKit
import Common

struct ListPluginsCommand: Command {
    let args: ListPluginsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let snapshot = PluginHost.shared.snapshot()
        if args.json {
            return JSONEncoder.aeroSpaceDefault.encodeToString(snapshot).map { .succ(io.out($0)) }
                ?? .fail(io.err("Failed to encode JSON"))
        }
        return .succ(io.out(snapshot.map(formatPluginLine)))
    }
}
