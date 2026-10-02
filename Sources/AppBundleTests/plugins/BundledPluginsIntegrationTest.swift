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
}
