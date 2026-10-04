# Architecture

## Definitions

**SPM.** Swift package manager and Swift build tool. In other words, `swift` CLI tool

## High level project infrastructure overview

- `../Sources`.
  The Swift source code. Managed by SPM `../Package.swift`
- `../Sources/AppBundle/`.
  HyprDarwin.app server. Technically it's an SPM library that the Xcode project wraps into an app bundle.
  Besides the inherited AeroSpace core (`tree/`, `layout/`, `command/`, `config/`), it holds the HyprDarwin
  subsystems:
  `bar/` (status bar and notch panel), `borders/` (window border overlays), `plugins/` (plugin host and protocol),
  `permissions/` (Accessibility window and monitor), `mouse/` (focus follows mouse, modifier drag) and `eventBus.swift`
  (in-process events that borders, bar and plugins subscribe to).
- `../Sources/Cli/`.
  The `hypr` CLI client. Built purely with SPM, no Xcode involved. The SPM product is still named `aerospace`;
  `build-app.sh` copies it to `hypr`.
- `../Sources/Common/`.
  Shared code between server and client: command line args parsing, `hypr init` setup logic and util functions.
- `../xcode/`.
  Small technical directory that defines the entry point for the Xcode project.
  SPM can't build macOS app bundles, so all code lives in the SPM library and Xcode only wraps it.
  `../xcode/AeroSpace.xcodeproj` is generated from `../xcode/project.yml`.
- `../Sources/AppBundleTests/`.
  Tests. Classes named `*IntegrationTest` cross a real boundary (file, process, CLI binary, app bundle) and run in
  `script/test-integration.sh`; the rest are unit tests (`script/test-unit.sh`).
- `../bundled-plugins/`, `../bundled-fonts/`.
  Plugins and the Hack Nerd Font that are copied into the app bundle.
- `../docs/`, `../site/`.
  Command reference sources (Asciidoc, for man pages), design specs and plans (`docs/superpowers/`), release notes
  (`docs/releases/`), and the website with its wiki.

## client/server interaction

`hypr` CLI binary is the client. `HyprDarwin.app` is the server. Client and server talk to each other via a UNIX socket.

Each time you run a CLI command:
1. Args are parsed by the client, args parsing errors are reported if any. Help is shown if `-h`/`--help` is passed.
1. If args are parsed successfully, the args are sent to the server
1. Server parses the args once again, and runs the command
1. Server returns stdout, stderr, and exit code to the client
1. Client shows stdout, stderr, and ends the process with the requested exit code

`hypr init` is the exception: it runs entirely in the client (`Sources/Common/setup/`) because it must work before the
app is running.

## Event bus, borders, bar and plugins

The core publishes typed events (`workspace`, `focus`, `monitor`, ...) through `broadcastEvent`
(`Sources/AppBundle/subscriptions.swift`). It sends them to `hypr subscribe` socket clients and to the in-process
listeners registered with `addEventListener` (`Sources/AppBundle/eventBus.swift`).

- Borders (`borders/`) and the bar (`bar/`) read the AeroSpace model and a `CGWindowList` snapshot. They never block the
  core. Layout decisions are pure functions (`borderPlan`, `barItems`) and AppKit code only applies the result.
- The plugin host (`plugins/`) runs plugin executables off the main thread. Each plugin has a serial queue; results hop
  back to the main actor. The design is in `../docs/superpowers/specs/2026-10-01-plugin-api-design.md`.

## Commands subsystem

todo

../Sources/AppBundle/command/
../Sources/Common/cmdArgs/

Command checklist (docs are still named `aerospace-*`; the generated help and man pages use `hypr`):
- [ ] Documentation in `../docs/aerospace-*` and `../docs/commands.adoc`
  - [ ] Check that site looks alright `./.site/commands.html`
  - [ ] Check that man page looks alright `./.man`
- [ ] Do `--window-id` and/or `--workspace` flags make sense for the command?
- [ ] Shell completion `../grammar/commands-bnf-grammar.txt`

## TOML Config parse subsystem

todo

../Sources/AppBundle/config/

## Tree Model subsystem

todo

../Sources/AppBundle/tree/

## Layout subsystem

todo

../Sources/AppBundle/layout/
