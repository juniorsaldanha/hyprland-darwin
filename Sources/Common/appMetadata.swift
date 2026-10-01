public let stableAeroSpaceAppId: String = "dev.hyprdarwin"
#if DEBUG
    public let aeroSpaceAppId: String = "dev.hyprdarwin.debug"
    public let aeroSpaceAppName: String = "HyprDarwin-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "HyprDarwin"
#endif
