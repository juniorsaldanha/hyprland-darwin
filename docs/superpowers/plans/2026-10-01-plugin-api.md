# Plugin API (sub-project 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A plugin host that runs plugins listed in `[bar]`/`[notch]` as separate processes, speaks JSON lines over stdin/stdout, keeps widget state for the coming bar, runs `{"run": ...}` commands, and exposes `hypr list-plugins`.

**Architecture:**
- **Pure units (unit-tested):** config lists, manifest, registry, line splitter and decoder, widget merge, event encoding, supervisor, bounded queue, log trimming.
- **`PluginProcess`:** one per plugin, with all state on its own serial queue. It spawns the plugin with `posix_spawn` in a new process group, so timeouts and stops kill the whole process tree. Pipes are non-blocking for stdin, and each process gets a `waitpid` watcher.
- **`PluginHost` (`@MainActor`):** resolves plugins, keeps them in step with config reloads, routes EventBus events and owns the `WidgetStore`.

**Tech Stack:** Swift 6.4, Foundation, Darwin (`posix_spawn`, `pipe`, `waitpid`, `kill`), TOMLDecoder (already a dependency), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-01-plugin-api-design.md` (parent: `docs/superpowers/specs/2026-10-01-hyprland-darwin-design.md`, sections 3–4)

## Global Constraints

- Branch `plugins` (the spec is committed on it).
- Warning-free build: `./build-debug.sh -Xswiftc -warnings-as-errors`. Upstream uses `strictMemorySafety()`, so mark C-interop expressions `unsafe` where the compiler asks.
- `./lint.sh` passes at the branch tip: no bare `Task {` (use `Task.startUnstructured`), and periphery clean.
- Unit tests are XCTest classes; integration tests are XCTest classes named `*IntegrationTest`.
- **The main thread never waits on a plugin.** All process I/O runs on per-plugin serial queues, and results hop to main with `DispatchQueue.main.async { MainActor.assumeIsolated { … } }`.
- Protocol limits: line max 64 KB; event queue 64, oldest dropped; interval timeout `min(interval, 5 s)`; 3 interval failures in a row → `failing`; stream backoff 1, 2, 4 … 60 s; 5 exits within 60 s → `stopped`; logs trimmed to the newest 512 KB once over 1 MB.
- Built-in widget names `workspaces` and `front-app` are never started as plugins.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A plugin whose script starts child processes** (`sleep 10` inside an interval script): on timeout the whole tree must die. Otherwise stdout never reaches EOF and that plugin never runs again. Covered in Task 6 (`testIntervalTimeoutKillsTreeAndGoesFailing`, which reaches `failing (3)` only if every run ends).
2. **A deaf plugin flooded with events**: nothing blocks, and memory stays bounded. Covered in Task 6 (`testDeafPluginQueueStaysBounded`).
3. **Output arriving split across reads, or a giant line followed by a good one**: line framing must hold. Covered in Task 3 (`LineSplitterTest`).
4. **A config reload that doesn't change a plugin**: it must not restart, or a stream plugin would lose its state on every config save. Covered in Task 6 (`testReloadKeepsUnchangedRestartsChangedStopsRemoved`).
5. **App quit**: no plugin process may survive. Covered in Task 6 (`testStopAllImmediatelyKillsProcess`) plus the Task 8 wiring into the termination handler.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/AppBundle/plugins/pluginConfig.swift` | create | `BarConfig`, `NotchConfig`, `PluginsConfig` parsers; `placedPluginNames`; `expandTilde` |
| `Sources/AppBundle/config/Config.swift`, `parseConfig.swift` | modify | Fields and keys; `parseArrayOfStrings` loses `private` |
| `Sources/AppBundle/plugins/PluginManifest.swift` | create | `PluginMode`, `PluginEventKind`, `PluginManifest`, `parsePluginManifest` |
| `Sources/AppBundle/plugins/PluginRegistry.swift` | create | `PluginResolution`, `ResolvedPlugin`, `resolvePlugins`, `readPluginManifest`, `bundledPluginsDir` |
| `Sources/AppBundle/plugins/pluginMessages.swift` | create | `WidgetState`, `WidgetPatch`, `PluginLine`, `decodePluginLine`, `LineSplitter` |
| `Sources/AppBundle/plugins/pluginEvents.swift` | create | `encodePluginEvent`, `pluginEvent(for:)` |
| `Sources/AppBundle/plugins/PluginSupervisor.swift` | create | `StreamSupervisor`, `IntervalHealth`, `BoundedQueue`, `trimmedLog` |
| `Sources/AppBundle/plugins/spawnPlugin.swift` | create | `posix_spawn` wrapper (new process group, only fds 0–2 inherited) |
| `Sources/AppBundle/plugins/PluginLog.swift` | create | Per-plugin log file |
| `Sources/AppBundle/plugins/PluginProcess.swift` | create | `PluginTiming`, `PluginStatus`, `PluginProcess` |
| `Sources/AppBundle/plugins/PluginHost.swift` | create | `WidgetStore`, `PluginSnapshot`, `PluginHost`, `formatPluginLine` |
| `Sources/AppBundle/plugins/startPlugins.swift` | create | `startPlugins`, `syncPlugins`, `runPluginCommand` |
| `list-plugins` command (docs, args, manifests, impl) | create/modify | `hypr list-plugins [--json]` |
| `bundled-plugins/example/` | create | Bundled example stream plugin |
| `.gitignore`, `xcode/project.yml` (+ regenerated project), `script/test-integration.sh` | modify | Ship and check `bundled-plugins` |
| `Sources/Common/util/commonUtil.swift` | modify | `RefreshSessionEvent.plugin(String)` |
| `ReloadConfigCommand.swift`, `initAppBundle.swift`, `util/appBundleUtil.swift` | modify | Reload sync, startup, kill plugins on quit |
| `Sources/AppBundleTests/plugins/*` | create | Unit and integration tests |

---

### Task 1: Placement config

**Files:**
- Create: `Sources/AppBundle/plugins/pluginConfig.swift`
- Modify:
  - `Sources/AppBundle/config/Config.swift`: after `var borders: BordersConfig = BordersConfig()`
  - `Sources/AppBundle/config/parseConfig.swift`: after `"borders"`; also `private func parseArrayOfStrings` → `func parseArrayOfStrings`
- Test: `Sources/AppBundleTests/plugins/PluginConfigTest.swift`; add a case to `Sources/AppBundleTests/config/HyprspaceConfigIntegrationTest.swift`

**Interfaces:**
- Produces:
  - `struct BarConfig { var left, center, right: [String] }`
  - `struct NotchConfig { var items: [String] }`
  - `struct PluginsConfig { var dirs: [String] = ["~/.config/hyprland-darwin/plugins"] }`
  - `config.bar`, `config.notch`, `config.plugins`
  - `extension Config { var placedPluginNames: [String] }`
  - `let builtinWidgetNames: Set<String>`
  - `func expandTilde(_:) -> String`

- [ ] **Step 1: Failing tests.** Create `Sources/AppBundleTests/plugins/PluginConfigTest.swift`:

```swift
@testable import AppBundle
import XCTest

@MainActor
final class PluginConfigTest: XCTestCase {
    func testDefaults() {
        let config = parseConfig("").config
        assertEquals(config.bar, BarConfig())
        assertEquals(config.notch.items, [])
        assertEquals(config.plugins.dirs, ["~/.config/hyprland-darwin/plugins"])
        assertEquals(config.placedPluginNames, [])
    }

    func testPlacementListsParse() {
        let result = parseConfig(
            """
            [bar]
                left = ['workspaces', 'front-app']
                center = ['music']
                right = ['clock', 'gpu']
            [notch]
                items = ['music', 'timer']
            [plugins]
                dirs = ['~/my-plugins']
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.bar, BarConfig(left: ["workspaces", "front-app"], center: ["music"], right: ["clock", "gpu"]))
        assertEquals(result.config.notch.items, ["music", "timer"])
        assertEquals(result.config.plugins.dirs, ["~/my-plugins"])
    }

    func testPlacedPluginNamesDedupesKeepsOrderSkipsBuiltins() {
        let result = parseConfig(
            """
            bar.left = ['workspaces', 'gpu']
            bar.right = ['clock', 'front-app', 'gpu']
            notch.items = ['music', 'clock']
            """,
        )
        assertEquals(result.config.placedPluginNames, ["gpu", "clock", "music"])
    }

    func testWrongTypeNamesTheKey() {
        let result = parseConfig("bar.left = 'clock'")
        assertTrue(result.strErrors.first?.hasPrefix("[ERROR] bar.left:") == true)
    }

    func testExpandTilde() {
        assertEquals(expandTilde("~/x"), NSHomeDirectory() + "/x")
        assertEquals(expandTilde("/abs"), "/abs")
    }
}
```

Add to `HyprspaceConfigIntegrationTest`:

```swift
    func testUserConfigWithBarAndPluginsSectionsParses() {
        let toml = try! String(contentsOf: projectRoot.appending(component: "docs/config-examples/hyprspace-migrated-config.toml"), encoding: .utf8)
        let result = parseConfig(toml + """

            [bar]
                left = ['workspaces', 'front-app']
                right = ['clock', 'battery', 'cpu', 'ram', 'disk']
            [plugins]
                dirs = ['~/.config/hyprland-darwin/plugins']
            """)
        assertEquals(result.errors, [])
        assertEquals(result.config.placedPluginNames, ["clock", "battery", "cpu", "ram", "disk"])
    }
```

- [ ] **Step 2: Run** `swift test --filter 'PluginConfigTest|HyprspaceConfigIntegrationTest'`. Expected: compile error `cannot find 'BarConfig' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/AppBundle/plugins/pluginConfig.swift`:

```swift
import Common
import Foundation

/// Placement lists only; the Bar sub-project adds the bar's look (height, colors, ...)
struct BarConfig: ConvenienceMutable, Equatable {
    var left: [String] = []
    var center: [String] = []
    var right: [String] = []
}

struct NotchConfig: ConvenienceMutable, Equatable {
    var items: [String] = []
}

struct PluginsConfig: ConvenienceMutable, Equatable {
    var dirs: [String] = ["~/.config/hyprland-darwin/plugins"]
}

/// Native widgets, drawn by the bar itself, never started as plugins
let builtinWidgetNames: Set<String> = ["workspaces", "front-app"]

private let barParserTable: [String: any ParserProtocol<BarConfig>] = [
    "left": Parser(\.left, parseArrayOfStrings),
    "center": Parser(\.center, parseArrayOfStrings),
    "right": Parser(\.right, parseArrayOfStrings),
]
private let notchParserTable: [String: any ParserProtocol<NotchConfig>] = [
    "items": Parser(\.items, parseArrayOfStrings),
]
private let pluginsParserTable: [String: any ParserProtocol<PluginsConfig>] = [
    "dirs": Parser(\.dirs, parseArrayOfStrings),
]

func parseBar(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BarConfig {
    parseTable(raw, BarConfig(), barParserTable, backtrace, &c)
}

func parseNotch(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> NotchConfig {
    parseTable(raw, NotchConfig(), notchParserTable, backtrace, &c)
}

func parsePluginsConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> PluginsConfig {
    parseTable(raw, PluginsConfig(), pluginsParserTable, backtrace, &c)
}

extension Config {
    /// Plugins to run: everything placed in the bar or notch, deduplicated, in order, minus built-in widgets
    var placedPluginNames: [String] {
        var seen = Set<String>()
        return (bar.left + bar.center + bar.right + notch.items)
            .filter { !builtinWidgetNames.contains($0) && seen.insert($0).inserted }
    }
}

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }
```

In `Config.swift`, after `var borders: BordersConfig = BordersConfig()`:

```swift
    var bar: BarConfig = BarConfig()
    var notch: NotchConfig = NotchConfig()
    var plugins: PluginsConfig = PluginsConfig()
```

In `parseConfig.swift`, after the `"borders"` entry:

```swift
    "bar": Parser(\.bar, parseBar),
    "notch": Parser(\.notch, parseNotch),
    "plugins": Parser(\.plugins, parsePluginsConfig),
```

Change `private func parseArrayOfStrings(` to `func parseArrayOfStrings(`.

- [ ] **Step 4: Run** the same filter. Expected: PASS (6 tests).
- [ ] **Step 5: Commit**: `git add Sources/AppBundle/plugins Sources/AppBundle/config Sources/AppBundleTests && git commit -m "Parse [bar]/[notch] placement lists and [plugins] dirs"` (+ Co-Authored-By).

---

### Task 2: Manifest and registry (pure)

**Files:**
- Create: `Sources/AppBundle/plugins/PluginManifest.swift`, `Sources/AppBundle/plugins/PluginRegistry.swift`
- Test: `Sources/AppBundleTests/plugins/PluginManifestTest.swift`

**Interfaces:**
- Consumes: `expandTilde` (Task 1).
- Produces:
  - `enum PluginMode { case interval(seconds: Int), stream; var name: String }`
  - `enum PluginEventKind: String, CaseIterable { case workspace, focus, monitor, wake }`
  - `struct PluginManifest { execPath: String; mode: PluginMode; events: Set<PluginEventKind> }`
  - `func parsePluginManifest(_ toml: String, pluginDir: String, isExecutable: (String) -> Bool) -> ResOrStr<PluginManifest>`
  - `enum PluginResolution { case ok(dir:manifest:), missing(searched:), invalid(String) }`
  - `struct ResolvedPlugin { name; resolution }`
  - `func resolvePlugins(names:userDirs:bundledDir:readManifest:isExecutable:) -> [ResolvedPlugin]`
  - `func readPluginManifest(_ pluginDir: String) -> String?`
  - `func bundledPluginsDir() -> String?`

- [ ] **Step 1: Failing tests.** Create `Sources/AppBundleTests/plugins/PluginManifestTest.swift`:

```swift
@testable import AppBundle
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
        assertEquals(parse("api = 1\nexec = 'x'\nmode = 'stream'\nevents = ['click']"), .failure("unknown event 'click'"))
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
}
```

- [ ] **Step 2: Run** `swift test --filter PluginManifestTest`. Expected: compile error `cannot find 'parsePluginManifest' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/AppBundle/plugins/PluginManifest.swift`:

```swift
import Common
import Foundation
import TOMLDecoder

enum PluginMode: Equatable, Sendable {
    case interval(seconds: Int)
    case stream

    var name: String {
        switch self {
            case .interval: "interval"
            case .stream: "stream"
        }
    }
}

/// Events a plugin can subscribe to. 'click' and 'power' arrive with the bar.
enum PluginEventKind: String, CaseIterable, Sendable {
    case workspace, focus, monitor, wake
}

struct PluginManifest: Equatable, Sendable {
    let execPath: String // absolute, standardized
    let mode: PluginMode
    let events: Set<PluginEventKind>
}

func parsePluginManifest(_ toml: String, pluginDir: String, isExecutable: (String) -> Bool) -> ResOrStr<PluginManifest> {
    let dict: [String: Any]
    do {
        dict = try .init(try TOMLTable(source: toml))
    } catch {
        return .failure("plugin.toml: \(error)")
    }
    guard let api = tomlInt(dict["api"]) else { return .failure("missing 'api'") }
    guard api == 1 else { return .failure("unsupported api \(api), expected 1") }
    guard let exec = dict["exec"] as? String, !exec.isEmpty else { return .failure("missing 'exec'") }
    let execPath = ((exec.hasPrefix("/") ? exec : (pluginDir as NSString).appendingPathComponent(exec)) as NSString).standardizingPath
    guard isExecutable(execPath) else { return .failure("exec '\(exec)' not found or not executable") }

    let mode: PluginMode
    switch dict["mode"] as? String {
        case "stream":
            mode = .stream
        case "interval":
            guard let seconds = tomlInt(dict["interval"]), seconds >= 1 else { return .failure("interval mode needs 'interval' >= 1") }
            mode = .interval(seconds: seconds)
        default:
            return .failure("mode must be 'interval' or 'stream'")
    }

    var events = Set<PluginEventKind>()
    if let raw = dict["events"] {
        guard let array = raw as? [Any] else { return .failure("'events' must be an array") }
        for element in array {
            guard let name = element as? String, let kind = PluginEventKind(rawValue: name) else { return .failure("unknown event '\(element)'") }
            events.insert(kind)
        }
    }
    return .success(PluginManifest(execPath: execPath, mode: mode, events: events))
}

private func tomlInt(_ value: Any?) -> Int? {
    switch value {
        case let v as Int: v
        case let v as Int64: Int(v)
        default: nil
    }
}
```

Create `Sources/AppBundle/plugins/PluginRegistry.swift`:

```swift
import Foundation

enum PluginResolution: Equatable, Sendable {
    case ok(dir: String, manifest: PluginManifest)
    case missing(searched: [String])
    case invalid(String)
}

struct ResolvedPlugin: Equatable, Sendable {
    let name: String
    let resolution: PluginResolution
}

/// Pure. Searches user dirs in order, then the bundled dir. The first folder with a plugin.toml wins.
func resolvePlugins(
    names: [String],
    userDirs: [String],
    bundledDir: String?,
    readManifest: (String) -> String?,
    isExecutable: (String) -> Bool,
) -> [ResolvedPlugin] {
    let searchDirs = userDirs.map(expandTilde) + (bundledDir.map { [$0] } ?? [])
    return names.map { name in
        for dir in searchDirs {
            let pluginDir = (dir as NSString).appendingPathComponent(name)
            guard let toml = readManifest(pluginDir) else { continue }
            return switch parsePluginManifest(toml, pluginDir: pluginDir, isExecutable: isExecutable) {
                case .success(let manifest): ResolvedPlugin(name: name, resolution: .ok(dir: pluginDir, manifest: manifest))
                case .failure(let reason): ResolvedPlugin(name: name, resolution: .invalid(reason))
            }
        }
        return ResolvedPlugin(name: name, resolution: .missing(searched: searchDirs))
    }
}

func readPluginManifest(_ pluginDir: String) -> String? {
    try? String(contentsOfFile: (pluginDir as NSString).appendingPathComponent("plugin.toml"), encoding: .utf8)
}

/// `Contents/Resources/bundled-plugins` in the app; the repo copy for debug builds that run outside an app bundle
func bundledPluginsDir() -> String? {
    if let url = Bundle.main.resourceURL?.appending(path: "bundled-plugins"), FileManager.default.fileExists(atPath: url.path) {
        return url.path
    }
    var url = URL(filePath: #filePath)
    while url.path != "/" {
        url.deleteLastPathComponent()
        let candidate = url.appending(path: "bundled-plugins")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
    }
    return nil
}
```

- [ ] **Step 4: Run** the filter. Expected: PASS (5 tests). If the TOML parse error text doesn't start with `plugin.toml: `, fix the code, not the test.
- [ ] **Step 5: Commit**: "Add plugin manifest parsing and registry".

---

### Task 3: Messages, widget state, line framing (pure)

**Files:**
- Create: `Sources/AppBundle/plugins/pluginMessages.swift`
- Test: `Sources/AppBundleTests/plugins/PluginMessagesTest.swift`

**Interfaces:**
- Produces:
  - `struct WidgetState: Equatable, Sendable, Encodable { icon, label, color, iconColor, background: String?; hidden: Bool; mutating func apply(_ patch: WidgetPatch) }`
  - `struct WidgetPatch { var strings: [String: String]; var hidden: Bool? }`
  - `enum PluginLine { case update(WidgetPatch, ignored: [String]); run(String); invalid(String) }`
  - `func decodePluginLine(_ line: Data) -> PluginLine`
  - `struct LineSplitter { static let maxLine = 65536; enum Piece { case line(Data), tooLong }; mutating func feed(_:) -> [Piece]; mutating func finish() -> [Piece] }`

- [ ] **Step 1: Failing tests.** Create `Sources/AppBundleTests/plugins/PluginMessagesTest.swift`:

```swift
@testable import AppBundle
import XCTest

final class PluginMessagesTest: XCTestCase {
    private func decode(_ s: String) -> PluginLine { decodePluginLine(Data(s.utf8)) }

    func testWidgetUpdate() {
        assertEquals(decode(#"{"icon":"X","label":"42%","color":"0xffe1e1e1","icon_color":"0xff000000","background":"0x40ffffff"}"#),
                     .update(WidgetPatch(strings: ["icon": "X", "label": "42%", "color": "0xffe1e1e1", "icon_color": "0xff000000", "background": "0x40ffffff"]), ignored: []))
    }

    func testHiddenMustBeBool() {
        assertEquals(decode(#"{"hidden":true}"#), .update(WidgetPatch(hidden: true), ignored: []))
        assertEquals(decode(#"{"hidden":1}"#), .update(WidgetPatch(), ignored: ["hidden"]))
    }

    func testWrongTypeFieldIgnoredOthersKept() {
        assertEquals(decode(#"{"label":42,"icon":"ok"}"#), .update(WidgetPatch(strings: ["icon": "ok"]), ignored: ["label"]))
    }

    func testUnknownFieldsIgnoredSilently() {
        assertEquals(decode(#"{"label":"a","future":1}"#), .update(WidgetPatch(strings: ["label": "a"]), ignored: []))
    }

    func testRunCommand() {
        assertEquals(decode(#"{"run":"workspace 2","label":"x"}"#), .run("workspace 2"))
        assertEquals(decode(#"{"run":5}"#), .invalid("'run' must be a string"))
    }

    func testInvalidJsonAndNonObject() {
        assertEquals(decode("not json"), .invalid("not a JSON object"))
        assertEquals(decode("[1,2]"), .invalid("not a JSON object"))
        assertEquals(decodePluginLine(Data([0x7B, 0xFF, 0xFE, 0x7D])), .invalid("not a JSON object"))
    }

    func testPatchMergeKeepsEarlierFields() {
        var state = WidgetState()
        state.apply(WidgetPatch(strings: ["icon": "A", "label": "1"]))
        state.apply(WidgetPatch(strings: ["label": "2"], hidden: true))
        assertEquals(state, WidgetState(icon: "A", label: "2", hidden: true))
        state.apply(WidgetPatch(hidden: false))
        assertFalse(state.hidden)
    }
}

final class LineSplitterTest: XCTestCase {
    private func lines(_ pieces: [LineSplitter.Piece]) -> [String] {
        pieces.map {
            switch $0 {
                case .line(let d): String(decoding: d, as: UTF8.self)
                case .tooLong: "<tooLong>"
            }
        }
    }

    func testSplitAcrossReads() {
        var s = LineSplitter()
        assertEquals(lines(s.feed(Data("{\"a\":".utf8))), [])
        assertEquals(lines(s.feed(Data("1}\n{\"b\":2}\n{\"c\"".utf8))), ["{\"a\":1}", "{\"b\":2}"])
        assertEquals(lines(s.finish()), ["{\"c\""])
    }

    func testEmptyLinesSkipped() {
        var s = LineSplitter()
        assertEquals(lines(s.feed(Data("\n\nx\n".utf8))), ["x"])
    }

    func testGiantLineThenGoodLine() {
        var s = LineSplitter()
        let giant = Data(repeating: 0x61, count: LineSplitter.maxLine + 10)
        var out = lines(s.feed(giant))
        out += lines(s.feed(Data("aaa\nok\n".utf8))) // tail of the giant line, then a good one
        assertEquals(out, ["<tooLong>", "ok"])
    }

    func testGiantLineInOneChunkWithNewline() {
        var s = LineSplitter()
        var chunk = Data(repeating: 0x61, count: LineSplitter.maxLine + 1)
        chunk.append(Data("\nok\n".utf8))
        assertEquals(lines(s.feed(chunk)), ["<tooLong>", "ok"])
    }
}
```

- [ ] **Step 2: Run** `swift test --filter 'PluginMessagesTest|LineSplitterTest'`. Expected: compile error `cannot find 'decodePluginLine' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/AppBundle/plugins/pluginMessages.swift`:

```swift
import Foundation

struct WidgetState: Equatable, Sendable, Encodable {
    var icon: String? = nil
    var label: String? = nil
    var color: String? = nil
    var iconColor: String? = nil
    var background: String? = nil
    var hidden: Bool = false

    enum CodingKeys: String, CodingKey {
        case icon, label, color, iconColor = "icon_color", background, hidden
    }

    mutating func apply(_ patch: WidgetPatch) {
        for (key, value) in patch.strings {
            switch key {
                case "icon": icon = value
                case "label": label = value
                case "color": color = value
                case "icon_color": iconColor = value
                case "background": background = value
                default: break
            }
        }
        if let hidden = patch.hidden { self.hidden = hidden }
    }
}

/// A partial update: only the fields the plugin sent
struct WidgetPatch: Equatable, Sendable {
    var strings: [String: String] = [:] // wire names: icon, label, color, icon_color, background
    var hidden: Bool? = nil
}

enum PluginLine: Equatable, Sendable {
    case update(WidgetPatch, ignored: [String])
    case run(String)
    case invalid(String)
}

private let stringFields = ["icon", "label", "color", "icon_color", "background"]

func decodePluginLine(_ line: Data) -> PluginLine {
    guard let dict = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return .invalid("not a JSON object") }
    if let run = dict["run"] {
        return (run as? String).map(PluginLine.run) ?? .invalid("'run' must be a string")
    }
    var patch = WidgetPatch()
    var ignored: [String] = []
    for key in stringFields {
        guard let value = dict[key] else { continue }
        if let string = value as? String { patch.strings[key] = string } else { ignored.append(key) }
    }
    if let value = dict["hidden"] {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            patch.hidden = number.boolValue
        } else {
            ignored.append("hidden")
        }
    }
    return .update(patch, ignored: ignored)
}

/// Frames stdout bytes into lines; drops (and reports) lines longer than 64 KB without buffering them
struct LineSplitter {
    static let maxLine = 64 * 1024

    enum Piece: Equatable {
        case line(Data)
        case tooLong
    }

    private var buffer = Data()
    private var discarding = false // inside the rest of an over-long line

    mutating func feed(_ data: Data) -> [Piece] {
        var out: [Piece] = []
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex ..< newline])
            buffer.removeSubrange(buffer.startIndex ... newline)
            if discarding {
                discarding = false
                continue
            }
            if line.count > Self.maxLine {
                out.append(.tooLong)
            } else if !line.isEmpty {
                out.append(.line(line))
            }
        }
        if buffer.count > Self.maxLine {
            if !discarding { out.append(.tooLong) }
            discarding = true
            buffer.removeAll()
        }
        return out
    }

    /// Partial line left at EOF
    mutating func finish() -> [Piece] {
        defer {
            buffer = Data()
            discarding = false
        }
        return discarding || buffer.isEmpty ? [] : [.line(buffer)]
    }
}
```

- [ ] **Step 4: Run** the filter. Expected: PASS (11 tests).
- [ ] **Step 5: Commit**: "Add plugin line decoding, widget state merge, line framing".

---

### Task 4: Events, supervisor, queue, log trimming (pure)

**Files:**
- Create: `Sources/AppBundle/plugins/pluginEvents.swift`, `Sources/AppBundle/plugins/PluginSupervisor.swift`
- Test: `Sources/AppBundleTests/plugins/PluginSupervisorTest.swift`

**Interfaces:**
- Consumes: `PluginEventKind` (Task 2); `ServerEvent` readable fields (Core).
- Produces:
  - `func encodePluginEvent(_ kind: PluginEventKind, _ fields: [String: Any] = [:]) -> String`
  - `@MainActor func pluginEvent(for: ServerEvent) -> (kind: PluginEventKind, line: String)?`
  - `struct StreamSupervisor { init(baseDelay:maxDelay:window:maxExits:); mutating func onExit(at:startedAt:) -> SupervisorDecision }`
  - `enum SupervisorDecision { case restart(after: TimeInterval), stop }`
  - `struct IntervalHealth { mutating func record(success:); var consecutiveFailures; var isFailing }`
  - `struct BoundedQueue<Element> { init(capacity:); append; popFirst; count; dropped }`
  - `func trimmedLog(_:limit:keep:) -> Data?`

- [ ] **Step 1: Failing tests.** Create `Sources/AppBundleTests/plugins/PluginSupervisorTest.swift`:

```swift
@testable import AppBundle
import XCTest

final class PluginSupervisorTest: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testBackoffThenStopAfterFiveQuickExits() {
        var s = StreamSupervisor()
        let decisions = (0 ..< 5).map { i in s.onExit(at: t0 + Double(i), startedAt: t0 + Double(i) - 0.1) }
        assertEquals(decisions, [.restart(after: 1), .restart(after: 2), .restart(after: 4), .restart(after: 8), .stop])
    }

    func testSlidingWindowKeepsRestartingWhenExitsAreSpreadOut() {
        var s = StreamSupervisor(maxDelay: 1)
        let decisions = [0.0, 20, 40, 60, 80].map { s.onExit(at: t0 + $0, startedAt: t0 + $0 - 1) }
        assertEquals(decisions.last, .restart(after: 1))
        assertFalse(decisions.contains(.stop))
    }

    func testDelayCappedAt60() {
        var s = StreamSupervisor(maxExits: 100)
        var last: SupervisorDecision = .stop
        for i in 0 ..< 10 { last = s.onExit(at: t0 + Double(i) * 0.01, startedAt: t0) }
        assertEquals(last, .restart(after: 60))
    }

    func testLongRunResetsBackoff() {
        var s = StreamSupervisor()
        _ = s.onExit(at: t0, startedAt: t0 - 1)
        _ = s.onExit(at: t0 + 2, startedAt: t0 + 1)
        assertEquals(s.onExit(at: t0 + 200, startedAt: t0 + 100), .restart(after: 1))
    }

    func testScaledTiming() {
        var s = StreamSupervisor(baseDelay: 0.05, maxDelay: 3, window: 3)
        assertEquals(s.onExit(at: t0, startedAt: t0), .restart(after: 0.05))
        assertEquals(s.onExit(at: t0, startedAt: t0), .restart(after: 0.1))
    }

    func testIntervalHealth() {
        var h = IntervalHealth()
        h.record(success: false)
        h.record(success: false)
        assertFalse(h.isFailing)
        h.record(success: false)
        assertTrue(h.isFailing)
        assertEquals(h.consecutiveFailures, 3)
        h.record(success: true)
        assertEquals(h.consecutiveFailures, 0)
    }

    func testBoundedQueueDropsOldest() {
        var q = BoundedQueue<Int>(capacity: 64)
        for i in 0 ..< 1000 { q.append(i) }
        assertEquals(q.count, 64)
        assertEquals(q.dropped, 936)
        assertEquals(q.popFirst(), 936)
    }

    func testTrimmedLog() {
        assertNil(trimmedLog(Data(repeating: 0x61, count: 10), limit: 100, keep: 50))
        var data = Data()
        for i in 0 ..< 30 { data.append(Data("line \(i)\n".utf8)) } // 30 lines, ~230 bytes
        let trimmed = trimmedLog(data, limit: 100, keep: 50)!
        assertTrue(trimmed.count <= 50)
        assertTrue(String(decoding: trimmed, as: UTF8.self).hasSuffix("line 29\n"))
        assertTrue(String(decoding: trimmed, as: UTF8.self).hasPrefix("line ")) // starts at a line boundary
    }
}

@MainActor
final class PluginEventsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEncodeIsSortedJson() {
        assertEquals(encodePluginEvent(.workspace, ["focused": "2", "prev": "1"]), #"{"event":"workspace","focused":"2","prev":"1"}"#)
        assertEquals(encodePluginEvent(.wake), #"{"event":"wake"}"#)
    }

    func testServerEventMapping() {
        assertEquals(pluginEvent(for: .workspaceChanged(workspace: "2", prevWorkspace: "1"))?.line, #"{"event":"workspace","focused":"2","prev":"1"}"#)
        assertEquals(pluginEvent(for: .focusedMonitorChanged(workspace: "3", monitorId_oneBased: 2))?.line, #"{"event":"monitor","monitor":2,"workspace":"3"}"#)
        assertEquals(pluginEvent(for: .focusChanged(windowId: nil, workspace: "2"))?.line, #"{"app":"","bundle":"","event":"focus","workspace":"2"}"#)
        assertNil(pluginEvent(for: .modeChanged(mode: "main")))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter 'PluginSupervisorTest|PluginEventsTest'`. Expected: compile error `cannot find 'StreamSupervisor' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/AppBundle/plugins/pluginEvents.swift`:

```swift
import Foundation

func encodePluginEvent(_ kind: PluginEventKind, _ fields: [String: Any] = [:]) -> String {
    var object = fields
    object["event"] = kind.rawValue
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

@MainActor func pluginEvent(for event: ServerEvent) -> (kind: PluginEventKind, line: String)? {
    switch event.eventType {
        case .workspaceChanged:
            return (.workspace, encodePluginEvent(.workspace, ["focused": event.workspace ?? "", "prev": event.prevWorkspace ?? ""]))
        case .focusChanged:
            let app = event.windowId.flatMap { Window.get(byId: $0) }?.app
            return (.focus, encodePluginEvent(.focus, ["app": app?.name ?? "", "bundle": app?.rawAppBundleId ?? "", "workspace": event.workspace ?? ""]))
        case .focusedMonitorChanged:
            return (.monitor, encodePluginEvent(.monitor, ["workspace": event.workspace ?? "", "monitor": event.monitorId ?? 0]))
        case .modeChanged, .windowDetected, .bindingTriggered:
            return nil
    }
}
```

Create `Sources/AppBundle/plugins/PluginSupervisor.swift`:

```swift
import Foundation

enum SupervisorDecision: Equatable {
    case restart(after: TimeInterval)
    case stop
}

/// Stream plugin restart policy: backoff baseDelay·2ⁿ capped at maxDelay; maxExits within `window` → stop.
struct StreamSupervisor {
    var baseDelay: TimeInterval = 1
    var maxDelay: TimeInterval = 60
    var window: TimeInterval = 60
    var maxExits = 5
    private var exits: [Date] = []
    private var consecutive = 0

    init(baseDelay: TimeInterval = 1, maxDelay: TimeInterval = 60, window: TimeInterval = 60, maxExits: Int = 5) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.window = window
        self.maxExits = maxExits
    }

    mutating func onExit(at now: Date, startedAt: Date) -> SupervisorDecision {
        if now.timeIntervalSince(startedAt) >= window { consecutive = 0 } // it ran fine for a while: fresh backoff
        exits = exits.filter { now.timeIntervalSince($0) < window } + [now]
        if exits.count >= maxExits { return .stop }
        let delay = min(baseDelay * pow(2, Double(consecutive)), maxDelay)
        consecutive += 1
        return .restart(after: delay)
    }
}

struct IntervalHealth {
    private(set) var consecutiveFailures = 0
    var isFailing: Bool { consecutiveFailures >= 3 }

    mutating func record(success: Bool) {
        consecutiveFailures = success ? 0 : consecutiveFailures + 1
    }
}

struct BoundedQueue<Element> {
    let capacity: Int
    private var items: [Element] = []
    private(set) var dropped = 0

    init(capacity: Int) { self.capacity = capacity }

    var count: Int { items.count }

    mutating func append(_ element: Element) {
        items.append(element)
        if items.count > capacity {
            items.removeFirst()
            dropped += 1
        }
    }

    mutating func popFirst() -> Element? { items.isEmpty ? nil : items.removeFirst() }
}

/// Over `limit`: the newest `keep` bytes, starting at a line boundary. Under: nil (leave the file alone).
func trimmedLog(_ data: Data, limit: Int = 1_048_576, keep: Int = 524_288) -> Data? {
    guard data.count > limit else { return nil }
    let tail = data.suffix(keep)
    guard let newline = tail.firstIndex(of: 0x0A) else { return Data(tail) }
    return Data(tail[tail.index(after: newline)...])
}
```

- [ ] **Step 4: Run** the filter. Expected: PASS (10 tests).
- [ ] **Step 5: Commit**: "Add plugin event encoding, supervisor, bounded queue, log trimming".

---

### Task 5: Spawning and logs

**Files:**
- Create: `Sources/AppBundle/plugins/spawnPlugin.swift`, `Sources/AppBundle/plugins/PluginLog.swift`
- Test: `Sources/AppBundleTests/plugins/SpawnPluginIntegrationTest.swift`

**Interfaces:**
- Produces:
  - `func spawnPlugin(path: String, environment: [String: String], directory: String, stdin: Int32, stdout: Int32, stderr: Int32) -> ResOrStr<pid_t>`
  - `final class PluginLog { init(name: String, dir: URL); func write(_ message: String); func append(raw: Data); var url: URL }`
  - `let defaultPluginLogsDir: URL`

- [ ] **Step 1: Failing test.** Create `Sources/AppBundleTests/plugins/SpawnPluginIntegrationTest.swift`:

```swift
@testable import AppBundle
import XCTest

final class SpawnPluginIntegrationTest: XCTestCase {
    func testNewProcessGroupCwdEnvAndOnlyStdFdsInherited() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appending(path: "p.sh")
        // pgid, cwd, env var, number of open fds (0,1,2 + the one ls itself opens)
        try "#!/bin/sh\necho \"$(ps -o pgid= -p $$ | tr -d ' ') $$ $(pwd -P) $FOO $(ls /dev/fd | wc -l | tr -d ' ')\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        var out: [Int32] = [0, 0]
        XCTAssertEqual(unsafe pipe(&out), 0)
        let devNull = open("/dev/null", O_RDWR)
        let pid = try spawnPlugin(path: script.path, environment: ["FOO": "bar", "PATH": "/usr/bin:/bin"], directory: dir.path, stdin: devNull, stdout: out[1], stderr: devNull).get()
        close(out[1])
        close(devNull)
        let output = String(decoding: FileHandle(fileDescriptor: out[0], closeOnDealloc: true).readDataToEndOfFile(), as: UTF8.self)
        var status: Int32 = 0
        _ = unsafe waitpid(pid, &status, 0)

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        assertEquals(parts[0], parts[1]) // pgid == pid: its own process group
        assertTrue(parts[2].hasSuffix(dir.path)) // /var is a symlink to /private/var
        assertEquals(parts[3], "bar")
        XCTAssertLessThanOrEqual(Int(parts[4]) ?? 99, 5) // no leaked parent fds
    }

    func testMissingExecutableIsAFailureNotACrash() {
        let devNull = open("/dev/null", O_RDWR)
        defer { close(devNull) }
        let result = spawnPlugin(path: "/nonexistent/x", environment: [:], directory: "/", stdin: devNull, stdout: devNull, stderr: devNull)
        assertNotNil(result.failureOrNil)
    }

    func testPluginLogWritesAndTrims() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "logs-\(UUID().uuidString)")
        let log = PluginLog(name: "gpu", dir: dir, limit: 200, keep: 100)
        for i in 0 ..< 50 { log.write("message \(i)") }
        log.flushForTests()
        let text = try String(contentsOf: log.url, encoding: .utf8)
        assertTrue(text.contains("message 49"))
        XCTAssertLessThanOrEqual(text.utf8.count, 200)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter SpawnPluginIntegrationTest`. Expected: compile error `cannot find 'spawnPlugin' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/AppBundle/plugins/spawnPlugin.swift`:

```swift
import Common
import Darwin

/// posix_spawn into a new process group, so a timeout or stop can kill the plugin's whole process tree
/// (kill(-pid)). POSIX_SPAWN_CLOEXEC_DEFAULT: the child inherits only fds 0-2, so other plugins' pipe ends
/// never leak into it (a leaked write end would keep their stdout from ever reaching EOF).
func spawnPlugin(path: String, environment: [String: String], directory: String, stdin: Int32, stdout: Int32, stderr: Int32) -> ResOrStr<pid_t> {
    var actions: posix_spawn_file_actions_t? = nil
    unsafe posix_spawn_file_actions_init(&actions)
    defer { unsafe posix_spawn_file_actions_destroy(&actions) }
    unsafe posix_spawn_file_actions_adddup2(&actions, stdin, 0)
    unsafe posix_spawn_file_actions_adddup2(&actions, stdout, 1)
    unsafe posix_spawn_file_actions_adddup2(&actions, stderr, 2)
    unsafe posix_spawn_file_actions_addchdir_np(&actions, directory)

    var attributes: posix_spawnattr_t? = nil
    unsafe posix_spawnattr_init(&attributes)
    defer { unsafe posix_spawnattr_destroy(&attributes) }
    unsafe posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    unsafe posix_spawnattr_setpgroup(&attributes, 0)

    let argv: [UnsafeMutablePointer<CChar>?] = unsafe [strdup(path), nil]
    let envp: [UnsafeMutablePointer<CChar>?] = unsafe environment.map { unsafe strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
        unsafe argv.forEach { unsafe free($0) }
        unsafe envp.forEach { unsafe free($0) }
    }
    var pid: pid_t = 0
    let rc = unsafe posix_spawn(&pid, path, &actions, &attributes, argv, envp)
    return rc == 0 ? .success(pid) : .failure("spawn failed: \(String(cString: strerror(rc)))")
}
```

Add or remove `unsafe` markers exactly where the compiler reports them. The ones shown are a best guess.

Create `Sources/AppBundle/plugins/PluginLog.swift`:

```swift
import Foundation

let defaultPluginLogsDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/hyprland-darwin")

/// One log file per plugin: the plugin's stderr plus host messages. Writes on its own serial queue.
final class PluginLog: @unchecked Sendable { // mutable state only touched on `queue`
    let url: URL
    private let queue: DispatchQueue
    private let limit: Int
    private let keep: Int
    private var writes = 0

    init(name: String, dir: URL = defaultPluginLogsDir, limit: Int = 1_048_576, keep: Int = 524_288) {
        url = dir.appending(path: "\(name).log")
        queue = DispatchQueue(label: "hyprdarwin.plugin-log.\(name)")
        self.limit = limit
        self.keep = keep
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        append(raw: Data(line.utf8))
    }

    func append(raw: Data) {
        queue.async { [self] in
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: raw)
            try? handle.close()
            writes += 1
            if writes % 20 == 0, let data = try? Data(contentsOf: url), let trimmed = trimmedLog(data, limit: limit, keep: keep) {
                try? trimmed.write(to: url)
            }
        }
    }

    /// Test hook: wait for queued writes, then trim once more
    func flushForTests() {
        queue.sync {
            if let data = try? Data(contentsOf: url), let trimmed = trimmedLog(data, limit: limit, keep: keep) {
                try? trimmed.write(to: url)
            }
        }
    }
}
```

- [ ] **Step 4: Run** the filter. Expected: PASS (3 tests).
- [ ] **Step 5: Commit**: "Add posix_spawn plugin launcher (own process group, no fd leaks) and plugin logs".

---

### Task 6: PluginProcess and PluginHost

**Files:**
- Create: `Sources/AppBundle/plugins/PluginProcess.swift`, `Sources/AppBundle/plugins/PluginHost.swift`
- Test: `Sources/AppBundleTests/plugins/PluginHostIntegrationTest.swift`, `Sources/AppBundleTests/plugins/PluginHostFormatTest.swift`

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces:
  - `struct PluginTiming { var scale: Double = 1 }`
  - `enum PluginStatus { starting, running, failing(Int), restarting(in:), stopped(String), missing(String), invalid(String); var description }`
  - `final class PluginProcess { init(name:dir:manifest:environment:timing:log:onLine:onStatus:); start(); stop(); stopImmediately(); send(_:); pendingEventCount() }`
  - `@MainActor final class WidgetStore: ObservableObject { @Published private(set) var widgets: [String: WidgetState] }`
  - `struct PluginSnapshot: Equatable, Encodable { name, mode, status: String; restarts: Int; widget: WidgetState }`
  - `func formatPluginLine(_:) -> String`
  - `@MainActor final class PluginHost`:
    - `static let shared`
    - `init(timing:bundledDir:logsDir:runCommand:)`
    - `store`
    - `sync(names:userDirs:environment:)`
    - `send(_:_:)`
    - `stopAll(immediately:)`
    - `snapshot()`
    - `pendingEventCount(_:)`

- [ ] **Step 1: Failing tests.** Create `Sources/AppBundleTests/plugins/PluginHostFormatTest.swift`:

```swift
@testable import AppBundle
import XCTest

final class PluginHostFormatTest: XCTestCase {
    func testStatusDescriptions() {
        assertEquals(PluginStatus.running.description, "running")
        assertEquals(PluginStatus.failing(3).description, "failing (3)")
        assertEquals(PluginStatus.restarting(in: 1.2).description, "restarting in 2s")
        assertEquals(PluginStatus.stopped("crashed 5 times within 60 s").description, "stopped: crashed 5 times within 60 s")
        assertEquals(PluginStatus.missing("no plugin folder in /a").description, "missing: no plugin folder in /a")
        assertEquals(PluginStatus.invalid("missing 'api'").description, "invalid: missing 'api'")
    }

    func testFormatLine() {
        let s = PluginSnapshot(name: "gpu", mode: "stream", status: "running", restarts: 2, widget: WidgetState(label: "42%"))
        assertEquals(formatPluginLine(s), "gpu | stream | running | 2 | 42%")
    }
}
```

Create `Sources/AppBundleTests/plugins/PluginHostIntegrationTest.swift`:

```swift
@testable import AppBundle
import XCTest

/// Real plugin processes from tiny shell scripts written into a temp dir. Timing scaled ×0.05.
@MainActor
final class PluginHostIntegrationTest: XCTestCase {
    private var root: URL!
    private var host: PluginHost!
    private var ran: [(String, String)] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "plugins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ran = []
        host = PluginHost(timing: PluginTiming(scale: 0.05), bundledDir: nil, logsDir: root.appending(path: "logs")) { [unowned self] in ran.append(($0, $1)) }
    }

    override func tearDown() async throws {
        host.stopAll(immediately: true)
    }

    private func plugin(_ name: String, manifest: String, script: String) throws {
        let dir = root.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appending(path: "plugin.toml"), atomically: true, encoding: .utf8)
        let exec = dir.appending(path: "run.sh")
        try ("#!/bin/sh\n" + script).write(to: exec, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)
    }

    private func sync(_ names: [String]) {
        host.sync(names: names, userDirs: [root.path], environment: ["PATH": "/usr/bin:/bin"])
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func status(_ name: String) -> String? { host.snapshot().first { $0.name == name }?.status }
    private func label(_ name: String) -> String? { host.store.widgets[name]?.label }
    private func pid(_ name: String) -> pid_t? {
        (try? String(contentsOf: root.appending(path: "\(name)/pid"), encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    private let stream = "api = 1\nexec = 'run.sh'\nmode = 'stream'\n"

    func testIntervalRunGetsEnvAndCwd() throws {
        try plugin("ok", manifest: "api = 1\nexec = 'run.sh'\nmode = 'interval'\ninterval = 1", script: "echo \"{\\\"label\\\":\\\"$HYPR_PLUGIN_NAME:$(basename \"$PWD\")\\\"}\"\n")
        sync(["ok"])
        assertTrue(waitUntil { label("ok") == "ok:ok" })
        assertEquals(status("ok"), "running")
    }

    func testIntervalTimeoutKillsTreeAndGoesFailing() throws {
        // `sleep` is a child of sh: unless the whole group dies, stdout never closes and no further run starts
        try plugin("slow", manifest: "api = 1\nexec = 'run.sh'\nmode = 'interval'\ninterval = 1", script: "sleep 10\necho '{\"label\":\"never\"}'\n")
        sync(["slow"])
        assertTrue(waitUntil { status("slow") == "failing (3)" })
        assertNil(label("slow"))
    }

    func testStreamEchoOnlySubscribedEvents() throws {
        try plugin("echo", manifest: stream + "events = ['workspace']", script: """
            while IFS= read -r line; do
              case "$line" in *workspace*) echo '{"label":"workspace"}' ;; *wake*) echo '{"label":"wake"}' ;; esac
            done
            """)
        sync(["echo"])
        assertTrue(waitUntil { status("echo") == "running" })
        host.send(.workspace, encodePluginEvent(.workspace, ["focused": "2", "prev": "1"]))
        assertTrue(waitUntil { label("echo") == "workspace" })
        host.send(.wake, encodePluginEvent(.wake)) // not subscribed
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        assertEquals(label("echo"), "workspace")
    }

    func testCrashLoopBacksOffThenStops() throws {
        try plugin("crash", manifest: stream, script: "exit 1\n")
        sync(["crash"])
        assertTrue(waitUntil { status("crash")?.hasPrefix("stopped") == true })
        assertEquals(host.snapshot().first?.restarts, 4)
    }

    func testDeafPluginQueueStaysBounded() throws {
        try plugin("deaf", manifest: stream + "events = ['workspace']", script: "exec sleep 30\n")
        sync(["deaf"])
        assertTrue(waitUntil { status("deaf") == "running" })
        let big = encodePluginEvent(.workspace, ["focused": String(repeating: "x", count: 500), "prev": "1"])
        for _ in 0 ..< 1000 { host.send(.workspace, big) } // ~500 KB, far beyond the 64 KB pipe buffer
        assertTrue(waitUntil { host.pendingEventCount("deaf") == 64 })
    }

    func testGarbageLinesDroppedGoodLinesApplied() throws {
        try plugin("garbage", manifest: stream, script: """
            echo 'not json'
            head -c 70000 /dev/zero | tr '\\0' 'a'; echo
            echo '{"label":42,"icon":"ok"}'
            echo '{"label":"good"}'
            exec sleep 30
            """)
        sync(["garbage"])
        assertTrue(waitUntil { label("garbage") == "good" })
        assertEquals(host.store.widgets["garbage"]?.icon, "ok")
        let log = { (try? String(contentsOf: self.root.appending(path: "logs/garbage.log"), encoding: .utf8)) ?? "" }
        assertTrue(waitUntil { log().contains("dropped line: not a JSON object") && log().contains("line longer than 64 KB") && log().contains("ignored field 'label'") })
    }

    func testRunCommandReachesRunner() throws {
        try plugin("runner", manifest: stream, script: "echo '{\"run\":\"workspace 2\"}'\nexec sleep 30\n")
        sync(["runner"])
        assertTrue(waitUntil { ran.count == 1 })
        assertEquals(ran.first?.0, "runner")
        assertEquals(ran.first?.1, "workspace 2")
    }

    func testStopAllImmediatelyKillsProcess() throws {
        try plugin("p", manifest: stream, script: "echo $$ > pid\nexec sleep 30\n")
        sync(["p"])
        assertTrue(waitUntil { pid("p") != nil })
        let p = pid("p")!
        assertTrue(isAlive(p))
        host.stopAll(immediately: true)
        assertTrue(waitUntil(2) { !isAlive(p) })
    }

    func testReloadKeepsUnchangedRestartsChangedStopsRemoved() throws {
        for name in ["keep", "change", "remove"] {
            try plugin(name, manifest: stream, script: "echo $$ > pid\nexec sleep 30\n")
        }
        sync(["keep", "change", "remove"])
        assertTrue(waitUntil { ["keep", "change", "remove"].allSatisfy { pid($0) != nil } })
        let keep = pid("keep")!, change = pid("change")!, remove = pid("remove")!

        try (stream + "events = ['wake']").write(to: root.appending(path: "change/plugin.toml"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appending(path: "change/pid"))
        sync(["keep", "change"])

        assertTrue(waitUntil { !isAlive(remove) })
        assertTrue(waitUntil { pid("change").map { $0 != change } == true })
        assertTrue(waitUntil(2) { !isAlive(change) })
        assertTrue(isAlive(keep))
        assertEquals(host.snapshot().map(\.name), ["keep", "change"])
    }

    func testMissingAndInvalidStatuses() throws {
        try plugin("bad", manifest: "api = 7", script: "")
        sync(["bad", "ghost"])
        assertEquals(status("bad"), "invalid: unsupported api 7, expected 1")
        assertEquals(status("ghost"), "missing: no plugin folder in \(root.path)")
    }
}
```

- [ ] **Step 2: Run** `swift test --filter 'PluginHostFormatTest|PluginHostIntegrationTest'`. Expected: compile error `cannot find 'PluginHost' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/AppBundle/plugins/PluginProcess.swift`:

```swift
import Darwin
import Foundation

struct PluginTiming: Sendable {
    var scale: Double = 1 // tests shrink every duration
    var timeoutCap: TimeInterval { 5 * scale }
    func interval(_ seconds: Int) -> TimeInterval { Double(seconds) * scale }
}

enum PluginStatus: Equatable, Sendable, CustomStringConvertible {
    case starting
    case running
    case failing(Int)
    case restarting(in: TimeInterval)
    case stopped(String)
    case missing(String)
    case invalid(String)

    var description: String {
        switch self {
            case .starting: "starting"
            case .running: "running"
            case .failing(let n): "failing (\(n))"
            case .restarting(let delay): "restarting in \(Int(delay.rounded(.up)))s"
            case .stopped(let reason): "stopped: \(reason)"
            case .missing(let reason): "missing: \(reason)"
            case .invalid(let reason): "invalid: \(reason)"
        }
    }
}

private final class RunState: @unchecked Sendable { // touched only on the process queue
    var splitter = LineSplitter()
    var gotLine = false
    var exited = false
    var eof = false
}

/// Runs one plugin. Every mutable field is touched only on `queue`; results hop to the main actor.
final class PluginProcess: @unchecked Sendable {
    let name: String
    private let dir: String
    private let manifest: PluginManifest
    private let environment: [String: String]
    private let timing: PluginTiming
    private let log: PluginLog
    private let onLine: @MainActor @Sendable (PluginLine) -> Void
    private let onStatus: @MainActor @Sendable (PluginStatus) -> Void
    private let queue: DispatchQueue

    private var isStopped = false
    private var currentPid: pid_t? = nil
    private var startedAt = Date()
    private var supervisor: StreamSupervisor
    private var health = IntervalHealth()
    private var intervalTimer: DispatchSourceTimer? = nil
    private var intervalRunning = false
    private var stdinFd: Int32 = -1
    private var pending = BoundedQueue<Data>(capacity: 64)
    private var partial = Data()
    private var retryScheduled = false

    init(
        name: String,
        dir: String,
        manifest: PluginManifest,
        environment: [String: String],
        timing: PluginTiming,
        log: PluginLog,
        onLine: @escaping @MainActor @Sendable (PluginLine) -> Void,
        onStatus: @escaping @MainActor @Sendable (PluginStatus) -> Void,
    ) {
        self.name = name
        self.dir = dir
        self.manifest = manifest
        self.environment = environment
        self.timing = timing
        self.log = log
        self.onLine = onLine
        self.onStatus = onStatus
        queue = DispatchQueue(label: "hyprdarwin.plugin.\(name)")
        supervisor = StreamSupervisor(baseDelay: 1 * timing.scale, maxDelay: 60 * timing.scale, window: 60 * timing.scale)
    }

    func start() {
        queue.async { [self] in
            switch manifest.mode {
                case .stream: startStream()
                case .interval(let seconds): startIntervalTimer(seconds)
            }
        }
    }

    /// Graceful: close stdin (protocol: stream plugins exit on EOF), SIGTERM the group, SIGKILL after 1 s
    func stop() {
        queue.async { [self] in
            shutDown(signal: SIGTERM)
            if let pid = currentPid {
                queue.asyncAfter(deadline: .now() + 1) { [self] in
                    if currentPid == pid { kill(-pid, SIGKILL) }
                }
            }
        }
    }

    /// For app termination: kill the group now, synchronously
    func stopImmediately() {
        queue.sync { shutDown(signal: SIGKILL) }
    }

    func send(_ line: String) {
        queue.async { [self] in
            guard !isStopped, stdinFd >= 0 else { return }
            pending.append(Data((line + "\n").utf8))
            flush()
        }
    }

    func pendingEventCount() -> Int { queue.sync { pending.count } }

    // MARK: queue-only

    private func shutDown(signal: Int32) {
        isStopped = true
        intervalTimer?.cancel()
        intervalTimer = nil
        closeStdin()
        if let pid = currentPid { kill(-pid, signal) }
    }

    private func report(_ status: PluginStatus) {
        let onStatus = onStatus
        DispatchQueue.main.async { MainActor.assumeIsolated { onStatus(status) } }
    }

    private func deliver(_ piece: LineSplitter.Piece) {
        let line: PluginLine = switch piece {
            case .line(let data): decodePluginLine(data)
            case .tooLong: .invalid("line longer than 64 KB")
        }
        let onLine = onLine
        DispatchQueue.main.async { MainActor.assumeIsolated { onLine(line) } }
    }

    /// Spawns with stdout/stderr pipes. Returns the read ends; the child's ends are closed here.
    private func spawn(stdin childStdin: Int32) -> (pid: pid_t, stdout: Int32, stderr: Int32)? {
        var out: [Int32] = [0, 0]
        var err: [Int32] = [0, 0]
        guard unsafe pipe(&out) == 0 else { return nil }
        guard unsafe pipe(&err) == 0 else {
            close(out[0])
            close(out[1])
            return nil
        }
        switch spawnPlugin(path: manifest.execPath, environment: environment, directory: dir, stdin: childStdin, stdout: out[1], stderr: err[1]) {
            case .success(let pid):
                close(out[1])
                close(err[1])
                currentPid = pid
                return (pid, out[0], err[0])
            case .failure(let message):
                [out[0], out[1], err[0], err[1]].forEach { close($0) }
                log.write(message)
                return nil
        }
    }

    private func readLines(_ fd: Int32, _ state: RunState, onPiece: @escaping @Sendable (LineSplitter.Piece) -> Void, onEOF: @escaping @Sendable () -> Void) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.readabilityHandler = { [self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            queue.async {
                if data.isEmpty {
                    state.splitter.finish().forEach(onPiece)
                    onEOF()
                } else {
                    state.splitter.feed(data).forEach(onPiece)
                }
            }
        }
    }

    private func readStderr(_ fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.readabilityHandler = { [log] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil } else { log.append(raw: data) }
        }
    }

    private func watchExit(_ pid: pid_t, then: @escaping @Sendable (Int32) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            var status: Int32 = 0
            while unsafe waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            queue.async {
                if currentPid == pid { currentPid = nil }
                then(status)
            }
        }
    }

    // MARK: stream

    private func startStream() {
        guard !isStopped else { return }
        var input: [Int32] = [0, 0]
        guard unsafe pipe(&input) == 0 else { return handleStreamExit() }
        guard let child = spawn(stdin: input[0]) else {
            close(input[0])
            close(input[1])
            return handleStreamExit()
        }
        close(input[0])
        stdinFd = input[1]
        _ = fcntl(stdinFd, F_SETFL, O_NONBLOCK)
        _ = fcntl(stdinFd, F_SETNOSIGPIPE, 1)
        pending = BoundedQueue(capacity: 64)
        partial = Data()
        startedAt = Date()
        report(.running)
        let state = RunState()
        readLines(child.stdout, state, onPiece: { [self] in deliver($0) }, onEOF: {})
        readStderr(child.stderr)
        watchExit(child.pid) { [self] status in
            closeStdin()
            log.write("exited with status \(status)")
            handleStreamExit()
        }
    }

    private func handleStreamExit() {
        guard !isStopped else { return }
        switch supervisor.onExit(at: Date(), startedAt: startedAt) {
            case .stop:
                report(.stopped("crashed 5 times within 60 s"))
            case .restart(let delay):
                report(.restarting(in: delay))
                queue.asyncAfter(deadline: .now() + delay) { [self] in startStream() }
        }
    }

    private func closeStdin() {
        if stdinFd >= 0 { close(stdinFd) }
        stdinFd = -1
    }

    /// Non-blocking: on a full pipe keep the bytes and retry shortly; the bounded queue drops the oldest events
    private func flush() {
        while stdinFd >= 0 {
            if partial.isEmpty {
                guard let next = pending.popFirst() else { return }
                partial = next
            }
            let written = unsafe partial.withUnsafeBytes { unsafe write(stdinFd, $0.baseAddress, $0.count) }
            if written > 0 {
                partial.removeFirst(written)
                continue
            }
            if written < 0 && errno == EAGAIN {
                scheduleRetry()
                return
            }
            partial = Data() // EPIPE or similar: the plugin is gone; the exit watcher takes over
            return
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 0.05) { [self] in
            retryScheduled = false
            flush()
        }
    }

    // MARK: interval

    private func startIntervalTimer(_ seconds: Int) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: timing.interval(seconds))
        timer.setEventHandler { [self] in runOnce(seconds) }
        timer.resume()
        intervalTimer = timer
    }

    private func runOnce(_ seconds: Int) {
        guard !isStopped, !intervalRunning else { return }
        let devNull = unsafe open("/dev/null", O_RDONLY)
        defer { close(devNull) }
        guard let child = spawn(stdin: devNull) else { return finishInterval(success: false) }
        intervalRunning = true
        let state = RunState()
        let finishIfDone: @Sendable () -> Void = { [self] in
            if state.exited && state.eof { finishInterval(success: state.gotLine) }
        }
        readLines(child.stdout, state, onPiece: { [self] piece in
            guard !state.gotLine else { return }
            deliver(piece)
            if case .line = piece {
                state.gotLine = true
                kill(-child.pid, SIGKILL) // one line per run is all we take
            }
        }, onEOF: {
            state.eof = true
            finishIfDone()
        })
        readStderr(child.stderr)
        let timeout = min(timing.interval(seconds), timing.timeoutCap)
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            guard !state.exited, !state.gotLine else { return }
            log.write("timed out after \(timeout) s")
            kill(-child.pid, SIGKILL)
        }
        watchExit(child.pid) { _ in
            state.exited = true
            finishIfDone()
        }
    }

    private func finishInterval(success: Bool) {
        intervalRunning = false
        health.record(success: success)
        report(health.isFailing ? .failing(health.consecutiveFailures) : .running)
    }
}
```

Create `Sources/AppBundle/plugins/PluginHost.swift`:

```swift
import Combine
import Foundation

@MainActor final class WidgetStore: ObservableObject {
    @Published private(set) var widgets: [String: WidgetState] = [:]

    func apply(_ patch: WidgetPatch, to name: String) { widgets[name, default: WidgetState()].apply(patch) }
    func remove(_ name: String) { widgets[name] = nil }
}

struct PluginSnapshot: Equatable, Encodable {
    let name: String
    let mode: String
    let status: String
    let restarts: Int
    let widget: WidgetState
}

func formatPluginLine(_ s: PluginSnapshot) -> String {
    "\(s.name) | \(s.mode) | \(s.status) | \(s.restarts) | \(s.widget.label ?? "")"
}

@MainActor final class PluginHost {
    static let shared = PluginHost()

    let store = WidgetStore()
    private let timing: PluginTiming
    private let bundledDir: String?
    private let logsDir: URL
    private let runCommand: @MainActor (String, String) -> Void
    private var order: [String] = []
    private var plugins: [String: Hosted] = [:]

    @MainActor private final class Hosted {
        let resolution: PluginResolution
        var process: PluginProcess? = nil
        var status: PluginStatus
        var restarts = 0

        init(_ resolution: PluginResolution, status: PluginStatus) {
            self.resolution = resolution
            self.status = status
        }

        var modeName: String {
            if case .ok(_, let manifest) = resolution { return manifest.mode.name }
            return "-"
        }
    }

    init(
        timing: PluginTiming = PluginTiming(),
        bundledDir: String? = bundledPluginsDir(),
        logsDir: URL = defaultPluginLogsDir,
        runCommand: @escaping @MainActor (String, String) -> Void = runPluginCommand,
    ) {
        self.timing = timing
        self.bundledDir = bundledDir
        self.logsDir = logsDir
        self.runCommand = runCommand
    }

    /// Removed → stopped; changed resolution (dir or manifest) → restarted; unchanged → left running
    func sync(names: [String], userDirs: [String], environment: [String: String]) {
        let resolved = resolvePlugins(
            names: names,
            userDirs: userDirs,
            bundledDir: bundledDir,
            readManifest: readPluginManifest,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        )
        let wanted = Set(resolved.map(\.name))
        for (name, hosted) in plugins where !wanted.contains(name) {
            hosted.process?.stop()
            plugins[name] = nil
            store.remove(name)
        }
        for plugin in resolved {
            if let existing = plugins[plugin.name], existing.resolution == plugin.resolution { continue }
            plugins[plugin.name]?.process?.stop()
            plugins[plugin.name] = makeHosted(plugin, environment)
        }
        order = resolved.map(\.name)
    }

    func send(_ kind: PluginEventKind, _ line: String) {
        for name in order {
            guard let hosted = plugins[name], case .ok(_, let manifest) = hosted.resolution,
                  manifest.mode == .stream, manifest.events.contains(kind) else { continue }
            hosted.process?.send(line)
        }
    }

    func stopAll(immediately: Bool = false) {
        for hosted in plugins.values {
            if immediately { hosted.process?.stopImmediately() } else { hosted.process?.stop() }
        }
        plugins = [:]
        order = []
    }

    func snapshot() -> [PluginSnapshot] {
        order.compactMap { name in
            plugins[name].map {
                PluginSnapshot(name: name, mode: $0.modeName, status: $0.status.description, restarts: $0.restarts, widget: store.widgets[name] ?? WidgetState())
            }
        }
    }

    func pendingEventCount(_ name: String) -> Int? { plugins[name]?.process?.pendingEventCount() }

    private func makeHosted(_ plugin: ResolvedPlugin, _ environment: [String: String]) -> Hosted {
        switch plugin.resolution {
            case .missing(let searched):
                return Hosted(plugin.resolution, status: .missing("no plugin folder in \(searched.joined(separator: ", "))"))
            case .invalid(let reason):
                return Hosted(plugin.resolution, status: .invalid(reason))
            case .ok(let dir, let manifest):
                let name = plugin.name
                let log = PluginLog(name: name, dir: logsDir)
                let hosted = Hosted(plugin.resolution, status: .starting)
                let process = PluginProcess(
                    name: name,
                    dir: dir,
                    manifest: manifest,
                    environment: environment.merging(["HYPR_PLUGIN_NAME": name, "HYPR_PLUGIN_DIR": dir]) { _, new in new },
                    timing: timing,
                    log: log,
                    onLine: { [weak self, weak hosted] line in
                        guard let self, let hosted, plugins[name] === hosted else { return } // stale process after reload
                        handle(line, from: name, log: log)
                    },
                    onStatus: { [weak self, weak hosted] status in
                        guard let self, let hosted, plugins[name] === hosted else { return }
                        if case .restarting = status { hosted.restarts += 1 }
                        hosted.status = status
                    },
                )
                hosted.process = process
                process.start()
                return hosted
        }
    }

    private func handle(_ line: PluginLine, from name: String, log: PluginLog) {
        switch line {
            case .update(let patch, let ignored):
                store.apply(patch, to: name)
                for field in ignored { log.write("ignored field '\(field)': wrong type") }
            case .run(let command):
                runCommand(name, command)
            case .invalid(let reason):
                log.write("dropped line: \(reason)")
        }
    }
}
```

`runPluginCommand` is defined in Task 8. For this task, add a temporary stub at the bottom of `PluginHost.swift`, which Task 8 replaces:

```swift
@MainActor func runPluginCommand(_ plugin: String, _ command: String) {}
```

- [ ] **Step 4: Run** the filter. Expected: PASS (12 tests). The likely failure points and how to read them:
  - `testIntervalTimeoutKillsTreeAndGoesFailing` stuck at `failing (1)` means the group kill or EOF handling is broken. Debug it; don't loosen the test.
  - `testDeafPluginQueueStaysBounded` blocking means writes aren't non-blocking.
- [ ] **Step 5: Strict build** `./build-debug.sh -Xswiftc -warnings-as-errors`, fixing `unsafe` and Sendable diagnostics without changing behaviour. Then **commit**: "Add plugin process supervision and plugin host".

---

### Task 7: `hypr list-plugins` and the bundled example plugin

**Files:**
- Create:
  - `docs/aerospace-list-plugins.adoc`
  - `Sources/Common/cmdArgs/impl/ListPluginsCmdArgs.swift`
  - `Sources/AppBundle/command/impl/ListPluginsCommand.swift`
  - `bundled-plugins/example/plugin.toml`
  - `bundled-plugins/example/example.sh`
- Modify:
  - `docs/commands.adoc` (before `== list-windows`)
  - `Sources/Common/cmdArgs/cmdArgsManifest.swift`
  - `Sources/AppBundle/command/cmdManifest.swift`
  - `.gitignore` (`!/bundled-plugins`)
  - `xcode/project.yml` (+ `./generate.sh`)
  - `script/test-integration.sh`
- Test: `Sources/AppBundleTests/plugins/ListPluginsCommandTest.swift`, `Sources/AppBundleTests/plugins/BundledPluginsIntegrationTest.swift`

- [ ] **Step 1: Failing tests.**

`Sources/AppBundleTests/plugins/ListPluginsCommandTest.swift`:

```swift
@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListPluginsCommandTest: XCTestCase {
    func testParse() {
        assertNil(parseCommand("list-plugins").errorOrNil)
        assertNil(parseCommand("list-plugins --json").errorOrNil)
        assertNotNil(parseCommand("list-plugins --nope").errorOrNil)
    }
}
```

`Sources/AppBundleTests/plugins/BundledPluginsIntegrationTest.swift`:

```swift
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
```

- [ ] **Step 2: Run** `swift test --filter 'ListPluginsCommandTest|BundledPluginsIntegrationTest'`. Expected: FAIL: `list-plugins` is an unknown subcommand, and `bundledPluginsDir()` is nil.

- [ ] **Step 3: Implement.**

`docs/aerospace-list-plugins.adoc`:

```asciidoc
= aerospace-list-plugins(1)
include::util/man-attributes.adoc[]
// tag::purpose[]
:manpurpose: Print the plugins placed in the bar and notch, with their status
// end::purpose[]
:manname: aerospace-list-plugins

// =========================================================== Synopsis
== Synopsis
[verse]
// tag::synopsis[]
aerospace list-plugins [-h|--help] [--json]

// end::synopsis[]

// =========================================================== Description
== Description

// tag::body[]
{manpurpose}.
One line per plugin: `name | mode | status | restarts | label`.
Status is one of `starting`, `running`, `failing (n)`, `restarting in Ns`, `stopped: <reason>`, `missing: <reason>`, `invalid: <reason>`.
Each plugin logs to `~/Library/Logs/hyprland-darwin/<name>.log`.

// =========================================================== Options
include::./util/conditional-options-header.adoc[]

-h, --help:: Print help
--json:: Output in JSON format, including the full widget state

// end::body[]

// =========================================================== Footer
include::util/man-footer.adoc[]
```

In `docs/commands.adoc`, before `== list-windows`:

```asciidoc
== list-plugins
----
include::./aerospace-list-plugins.adoc[tags=synopsis]
----
include::./aerospace-list-plugins.adoc[tags=purpose]
include::./aerospace-list-plugins.adoc[tags=body]

```

Run `./generate.sh --ignore-xcodeproj` (it creates `list_plugins_help_generated`).

`Sources/Common/cmdArgs/impl/ListPluginsCmdArgs.swift`:

```swift
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
```

`cmdArgsManifest.swift`:
- after `case listMonitors = "list-monitors"`, add `case listPlugins = "list-plugins"`
- in `initSubcommands()`, after the `.listMonitors` case, add:

```swift
            case .listPlugins:
                result[kind.rawValue] = SubCommandParser(ListPluginsCmdArgs.init)
```

`cmdManifest.swift`, after the `.listMonitors` case:

```swift
            case .listPlugins:
                command = ListPluginsCommand(args: self as! ListPluginsCmdArgs)
```

`Sources/AppBundle/command/impl/ListPluginsCommand.swift`:

```swift
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
```

`bundled-plugins/example/plugin.toml`:

```toml
# Example stream plugin: shows the focused workspace. Copy this folder to start your own.
api = 1
exec = "./example.sh"
mode = "stream"
events = ["workspace"]
```

`bundled-plugins/example/example.sh` (`chmod +x`):

```sh
#!/bin/sh
# Reads one JSON event per line on stdin, writes widget updates as JSON lines on stdout.
# Exits when stdin closes (required for stream plugins).
echo '{"label":"ws ?"}'
while IFS= read -r event; do
    workspace=$(printf '%s' "$event" | sed -n 's/.*"focused":"\([^"]*\)".*/\1/p')
    [ -n "$workspace" ] && printf '{"label":"ws %s"}\n' "$workspace"
done
```

`.gitignore`: add `!/bundled-plugins` under "Top level dirs".

`xcode/project.yml`, under `targets.AeroSpace.sources`, add:

```yaml
      - path: "../bundled-plugins"
        type: folder
        buildPhase: resources
```

Then run `./generate.sh`.

`script/test-integration.sh`, in the app bundle block after the `default-config.toml` check:

```bash
    test -x "$app/Contents/Resources/bundled-plugins/example/example.sh" || fail "missing bundled-plugins/example in the app bundle"
```

- [ ] **Step 4: Run** the filter. Expected: PASS (2 tests). Then run `HYPRDARWIN_CODESIGN_IDENTITY=- ./build-app.sh --no-install && ./script/test-integration.sh --app .release/HyprDarwin.app`. Expected: `✅ Integration tests have passed successfully`.
- [ ] **Step 5: Commit**: "Add list-plugins command and bundled example plugin".

---

### Task 8: Wiring

**Files:**
- Create: `Sources/AppBundle/plugins/startPlugins.swift`
- Modify:
  - `Sources/AppBundle/plugins/PluginHost.swift`: delete the `runPluginCommand` stub
  - `Sources/Common/util/commonUtil.swift`: `case plugin(String)` and its description
  - `ReloadConfigCommand.swift`: after `syncModifierDrag(config)`
  - `initAppBundle.swift`: after `startBorders()`
  - `util/appBundleUtil.swift`: first line of `beforeTermination()`

- [ ] **Step 1:** In `commonUtil.swift`, after `case permissionMonitor` add `case plugin(String)`, and in `description` add `case .plugin(let name): "plugin(\(name))"`.

- [ ] **Step 2:** Create `Sources/AppBundle/plugins/startPlugins.swift`:

```swift
import AppKit
import Common

@MainActor private var pluginObservers: [Any] = []

/// Call once at startup: routes EventBus and system-wake events to plugins, then starts the placed plugins
@MainActor func startPlugins() {
    _ = addEventListener { event in
        if let (kind, line) = pluginEvent(for: event) { PluginHost.shared.send(kind, line) }
    }
    pluginObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
    ) { _ in MainActor.assumeIsolated { PluginHost.shared.send(.wake, encodePluginEvent(.wake)) } })
    syncPlugins(config)
}

@MainActor func syncPlugins(_ config: Config) {
    if isUnitTest { return }
    PluginHost.shared.sync(names: config.placedPluginNames, userDirs: config.plugins.dirs, environment: config.execConfig.envVariables)
}

/// `{"run": "..."}` from a plugin: same rules as a keybinding (not run while tiling is disabled)
@MainActor func runPluginCommand(_ plugin: String, _ command: String) {
    let log = PluginLog(name: plugin)
    guard let token: RunSessionGuard = .isServerEnabled else {
        log.write("run '\(command)' ignored: tiling is disabled")
        return
    }
    switch parseCommand(command, allowExecAndForget: true, allowEval: false) {
        case .cmd(let shell):
            Task.startUnstructured {
                _ = try? await runLightSession(.plugin(plugin), token) { await shell.run(.defaultEnv, .emptyStdin) }
            }
        case .failure(let error):
            log.write("run '\(command)' failed to parse: \(error.msg)")
        case .help:
            log.write("run '\(command)' printed help; nothing ran")
    }
}
```

- [ ] **Step 3:** Delete the `runPluginCommand` stub in `PluginHost.swift`. Add `syncPlugins(config)` after `syncModifierDrag(config)` in `ReloadConfigCommand.swift`. Add `startPlugins()` after `startBorders()` in `initAppBundle.swift`. Make `PluginHost.shared.stopAll(immediately: true)` the first line of `beforeTermination()` in `util/appBundleUtil.swift`.

- [ ] **Step 4: Full gate:** `./build-debug.sh -Xswiftc -warnings-as-errors && ./script/test-unit.sh && ./script/test-integration.sh && ./lint.sh`. Expected: all pass, `* No unused code detected.`
- [ ] **Step 5: Commit**: "Wire plugin host: events, wake, reload sync, run commands, kill on quit".

---

### Task 9: Verification

- [ ] **Step 1:** `./test.sh && ./script/test-integration.sh`, then `HYPRDARWIN_CODESIGN_IDENTITY=- ./build-app.sh --no-install && ./script/test-integration.sh --app .release/HyprDarwin.app`. Expected: all ✅.
- [ ] **Step 2: Manual (the user):**
  1. `mkdir -p ~/.config/hyprland-darwin/plugins/gpu`
  2. Write `plugin.toml`:

     ```toml
     api = 1
     exec = "./gpu.sh"
     mode = "interval"
     interval = 2
     ```

  3. Write `gpu.sh` (`chmod +x`): `echo '{"label":"42%"}'`
  4. Add `bar.right = ['gpu']` to your config.
  5. `hypr list-plugins` shows `gpu | interval | running | 0 | 42%`.
  6. Repeat with a stream plugin that exits, and watch the restarts, then `stopped`.
  7. Repeat with `echo '{"run":"workspace 2"}'`, and workspace 2 gets focus.
