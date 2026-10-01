import AppKit
import Common
import SwiftUI

@MainActor private var permissionsWindow: NSWindow? = nil

/// Plain NSWindow (not a SwiftUI scene) so it can be opened from anywhere, including during startup.
@MainActor func showPermissionsWindow() {
    if permissionsWindow == nil {
        let window = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView(model: .shared)))
        window.title = "\(aeroSpaceAppName) Permissions"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .normal // Not .floating: it would cover System Settings after "Open Settings"
        permissionsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    permissionsWindow?.center()
    permissionsWindow?.makeKeyAndOrderFront(nil)
}

private struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(aeroSpaceAppName) needs a few permissions").font(.title2).bold()
            ForEach(PermissionKind.allCases, id: \.self) { kind in
                PermissionRow(kind: kind, isGranted: model.isGranted(kind)) {
                    Task.startUnstructured { await model.fix(kind) }
                }
            }
            Divider()
            if model.allRequiredGranted {
                Label("All set", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                HStack {
                    Text("Granted but still ✗? macOS sometimes needs the app restarted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch") { relaunchApp() }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { // Re-check every second while the window is open
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let isGranted: Bool
    let fix: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.isRequired ? kind.title : "\(kind.title) (optional)").bold()
                Text(kind.reason).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !isGranted {
                Button("Open Settings", action: fix)
            }
        }
    }
}

@MainActor private func relaunchApp() {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
    _ = try? process.run()
    terminationHandler?.beforeTermination()
    terminateApp()
}
