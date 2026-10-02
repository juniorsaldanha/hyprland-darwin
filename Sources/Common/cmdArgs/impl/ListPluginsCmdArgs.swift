public struct ListPluginsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listPlugins,
        help: list_plugins_help_generated,
        flags: [
            "--json": trueBoolFlag(\.json),
        ],
        posArgs: [],
    )

    public var json: Bool = false
}
