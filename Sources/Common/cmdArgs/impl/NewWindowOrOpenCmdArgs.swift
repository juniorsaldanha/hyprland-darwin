public struct NewWindowOrOpenCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .newWindowOrOpen,
        help: new_window_or_open_help_generated,
        flags: [:],
        posArgs: [
            newMandatoryPosArgParser(\.appName, parseAppName, placeholder: "<app-name>"),
        ],
    )

    public var appName: Lateinit<String> = .uninitialized
}

private func parseAppName(i: PosArgParserInput) -> ParsedCliArgs<String> {
    .init(.success(i.arg), advanceBy: 1)
}
