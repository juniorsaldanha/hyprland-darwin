@testable import AppBundle
import XCTest

final class BundledPluginsIntegrationTest: XCTestCase {
    func testExamplePluginResolvesFromRepoBundledDir() {
        let dir = bundledPluginsDir()
        assertNotNil(dir)
        let resolved = resolvePlugins(names: ["example"], userDirs: [], bundledDir: dir, readManifest: readPluginManifest, isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        guard case .ok(_, let manifest)? = resolved.first?.resolution else { return XCTFail("\(resolved)") }
        assertEquals(manifest.mode, .stream)
        assertEquals(manifest.events, [.workspace])
    }

    private func runOnce(_ name: String, env: [String: String] = [:]) throws -> [String: Any] {
        let dir = try XCTUnwrap(bundledPluginsDir())
        let process = Process()
        process.executableURL = URL(filePath: "\(dir)/\(name)/run.sh")
        process.currentDirectoryURL = URL(filePath: "\(dir)/\(name)")
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        process.waitUntilExit()
        let line = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], "\(name) printed: \(line)")
    }

    func testEveryBundledPluginResolvesAndPrintsAWidget() throws {
        let names = ["clock", "volume", "network", "cpu", "gpu", "ram", "disk"]
        let resolved = resolvePlugins(names: names + ["battery"], userDirs: [], bundledDir: bundledPluginsDir(), readManifest: readPluginManifest, isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        for plugin in resolved {
            guard case .ok = plugin.resolution else { return XCTFail("\(plugin)") }
        }
        for name in names {
            let json = try runOnce(name, env: name == "volume" ? ["HYPR_EVENT_JSON": #"{"event":"volume","level":42}"#] : [:])
            XCTAssertFalse(((json["label"] as? String) ?? "").isEmpty, name)
        }
        assertEquals(try runOnce("volume", env: ["HYPR_EVENT_JSON": #"{"event":"volume","level":42}"#])["label"] as? String, "42%")
        assertEquals(try runOnce("clock")["icon"] as? String, "\u{F43A}")
        assertEquals(try runOnce("gpu")["icon"] as? String, "\u{F08AE}")
    }

    func testBatteryHidesWithoutPercentage() throws {
        let json = try runOnce("battery", env: ["HYPR_PMSET_OUTPUT": "Now drawing from 'AC Power'"]) // test hook: desktop Mac
        assertEquals(json["hidden"] as? Bool, true)
        let charging = try runOnce("battery", env: ["HYPR_PMSET_OUTPUT": "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t95%; charging"])
        assertEquals(charging["label"] as? String, "95%")
        assertEquals(charging["icon"] as? String, "\u{F0084}")
        let low = try runOnce("battery", env: ["HYPR_PMSET_OUTPUT": "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t5%; discharging"])
        assertEquals(low["icon"] as? String, "\u{F244}")
        assertEquals(low["icon_color"] as? String, "0xffd20f39")
    }

    func testCpuPluginFinishesWellInsideItsTwoSecondInterval() throws {
        // interval 2 → timeout 2 s: `top -l 2 -s 1` took ~1.7 s under load and got killed exactly when CPU was high
        let start = Date()
        let json = try runOnce("cpu")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.4)
        assertTrue((json["label"] as? String)?.hasSuffix("%") == true)
    }
}
