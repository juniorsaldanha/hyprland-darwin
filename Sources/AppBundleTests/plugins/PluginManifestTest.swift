@testable import AppBundle
import Common
import XCTest

final class PluginManifestTest: XCTestCase {
    private func parse(_ toml: String, executable: Bool = true) -> ResOrStr<PluginManifest> {
        parsePluginManifest(toml, pluginDir: "/p/gpu", isExecutable: { _ in executable })
    }

    func testIntervalManifest() {
        assertEquals(
            parse("api = 1\nexec = './gpu.sh'\nmode = 'interval'\ninterval = 2"),
            .success(PluginManifest(execPath: "/p/gpu/gpu.sh", mode: .interval(seconds: 2), events: [])),
        )
    }

    func testStreamManifestWithEventsAndAbsoluteExec() {
        assertEquals(
            parse("api = 1\nexec = '/usr/local/bin/x'\nmode = 'stream'\nevents = ['workspace', 'focus']"),
            .success(PluginManifest(execPath: "/usr/local/bin/x", mode: .stream, events: [.workspace, .focus])),
        )
    }

    func testInvalidCases() {
        assertEquals(parse("api = 2\nexec = 'x'\nmode = 'stream'"), .failure("unsupported api 2, expected 1"))
        assertEquals(parse("exec = 'x'\nmode = 'stream'"), .failure("missing 'api'"))
        assertEquals(parse("api = 1\nmode = 'stream'"), .failure("missing 'exec'"))
        assertEquals(parse("api = 1\nexec = './gone.sh'\nmode = 'stream'", executable: false), .failure("exec './gone.sh' not found or not executable"))
        assertEquals(parse("api = 1\nexec = 'x'\nmode = 'poll'"), .failure("mode must be 'interval' or 'stream'"))
        assertEquals(parse("api = 1\nexec = 'x'\nmode = 'interval'"), .failure("interval mode needs 'interval' >= 1"))
        assertEquals(parse("api = 1\nexec = 'x'\nmode = 'interval'\ninterval = 0"), .failure("interval mode needs 'interval' >= 1"))
        assertEquals(parse("api = 1\nexec = 'x'\nmode = 'stream'\nevents = ['hover']"), .failure("unknown event 'hover'"))
        assertEquals(parse("api = 1\nexec = 'x'\nmode = 'stream'\nevents = 'focus'"), .failure("'events' must be an array"))
        assertTrue(parse("api = = 1").failureOrNil?.hasPrefix("plugin.toml: ") == true)
    }

    func testResolveUserDirBeatsBundledAndFirstUserDirWins() {
        let toml = "api = 1\nexec = 'x'\nmode = 'stream'"
        let files = ["/u1/gpu": toml, "/u2/gpu": toml, "/u2/clock": toml, "/b/clock": toml, "/b/cpu": toml]
        let resolved = resolvePlugins(
            names: ["gpu", "clock", "cpu", "nope"],
            userDirs: ["/u1", "/u2"],
            bundledDir: "/b",
            readManifest: { files[$0] },
            isExecutable: { _ in true },
        )
        assertEquals(resolved.map(\.name), ["gpu", "clock", "cpu", "nope"])
        assertEquals(resolved[0].resolution, .ok(dir: "/u1/gpu", manifest: PluginManifest(execPath: "/u1/gpu/x", mode: .stream, events: [])))
        assertEquals(resolved[1].resolution, .ok(dir: "/u2/clock", manifest: PluginManifest(execPath: "/u2/clock/x", mode: .stream, events: [])))
        assertEquals(resolved[2].resolution, .ok(dir: "/b/cpu", manifest: PluginManifest(execPath: "/b/cpu/x", mode: .stream, events: [])))
        assertEquals(resolved[3].resolution, .missing(searched: ["/u1", "/u2", "/b"]))
    }

    func testResolveInvalidManifest() {
        let resolved = resolvePlugins(names: ["bad"], userDirs: ["/u"], bundledDir: nil, readManifest: { $0 == "/u/bad" ? "api = 9" : nil }, isExecutable: { _ in true })
        assertEquals(resolved.first?.resolution, .invalid("unsupported api 9, expected 1"))
    }

    func testBarEventsAccepted() {
        assertEquals(
            parse("api = 1\nexec = 'x'\nmode = 'interval'\ninterval = 5\nevents = ['click', 'power', 'volume', 'wake']"),
            .success(PluginManifest(execPath: "/p/gpu/x", mode: .interval(seconds: 5), events: [.click, .power, .volume, .wake])),
        )
    }
}
