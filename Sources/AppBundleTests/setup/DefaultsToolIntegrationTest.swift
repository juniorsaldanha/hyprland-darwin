import Common
import XCTest

/// Real /usr/bin/defaults on a throwaway domain: never the user's settings
final class DefaultsToolIntegrationTest: XCTestCase {
    private let domain = "dev.hyprdarwin.test-\(UUID().uuidString)"

    override func tearDown() {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/defaults")
        p.arguments = ["delete", domain]
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        // `defaults delete` leaves an empty plist behind
        try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences/\(domain).plist"))
    }

    func testWriteReadDeleteRoundTrip() {
        let tool = DefaultsTool(domainOverride: domain)
        assertNil(tool.readBool("com.apple.dock", "k"))
        assertTrue(tool.apply(.write(domain: "com.apple.dock", key: "k", value: true)))
        assertEquals(tool.readBool("com.apple.dock", "k"), true)
        assertTrue(tool.apply(.write(domain: "NSGlobalDomain", key: "k", value: false))) // same throwaway domain
        assertEquals(tool.readBool("NSGlobalDomain", "k"), false)
        assertTrue(tool.apply(.delete(domain: "com.apple.dock", key: "k")))
        assertNil(tool.readBool("com.apple.dock", "k"))
    }
}
