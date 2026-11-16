import AppKit
import SwiftUI

/// A short message at the bottom-centre of a monitor that fades away, like the volume HUD
final class ToastPanel: NSPanelHud {
    @MainActor static let shared = ToastPanel()
    private var timer: Timer?

    override private init() { super.init() }

    @MainActor func show(_ text: String, systemImage: String, on monitor: any MonitorInfo) {
        timer?.invalidate()
        let view = NSHostingView(rootView: ToastView(text: text, systemImage: systemImage))
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        contentView = view
        let screens = NSScreen.screens
        let screen = screens.indices.contains(monitor.monitorAppKitNsScreenScreensId - 1)
            ? screens[monitor.monitorAppKitNsScreenScreensId - 1].frame
            : (screens.first?.frame ?? .zero)
        setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.minY + 80, width: size.width, height: size.height), display: true)
        orderFrontRegardless()
        timer = .scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task.startUnstructured { @MainActor in self?.orderOut(nil) }
        }
    }
}

private struct ToastView: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .fixedSize()
    }
}
