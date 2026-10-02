import AppKit
import Common
import SwiftUI

@MainActor final class BarModel: ObservableObject {
    static let shared = BarModel()
    @Published var frontApp: String? = NSWorkspace.shared.frontmostApplication?.localizedName
}

struct BarView: View {
    @ObservedObject var tray: TrayMenuModel
    @ObservedObject var store: WidgetStore
    @ObservedObject var model: BarModel
    let config: BarConfig

    var body: some View {
        HStack(spacing: 0) {
            section(config.left)
            Spacer(minLength: 0)
            section(config.center)
            Spacer(minLength: 0)
            section(config.right)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ names: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(barItems(names: names, workspaces: tray.workspaces, frontApp: model.frontApp, widgets: store.widgets, statuses: store.statuses)) { item in
                BarItemView(item: item, config: config)
            }
        }
    }
}

/// Plugin widgets only, for the notch panel
struct NotchView: View {
    @ObservedObject var store: WidgetStore
    let names: [String]
    let config: BarConfig

    var body: some View {
        HStack(spacing: 0) {
            ForEach(barItems(names: names, workspaces: [], frontApp: nil, widgets: store.widgets, statuses: store.statuses)) { item in
                BarItemView(item: item, config: config)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(Color.black))
    }
}

struct BarItemView: View {
    let item: BarItem
    let config: BarConfig

    private var iconFont: Font { .custom(config.font, size: CGFloat(config.iconSize)).bold() }
    private var labelFont: Font { .custom(config.font, size: CGFloat(config.labelSize)).bold() }
    private var foreground: Color { Color(nsColor(argb: config.foreground)) }

    var body: some View {
        switch item {
            case .workspace(let name, let isFocused):
                Text(name)
                    .font(iconFont)
                    .foregroundColor(foreground)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(height: 25)
                    .background(RoundedRectangle(cornerRadius: 5).fill(isFocused ? Color(nsColor(argb: 0x40FF_FFFF)) : .clear))
                    .padding(.horizontal, 5)
                    .contentShape(Rectangle())
                    .onTapGesture { focusWorkspaceFromBar(name) }
            case .chevron:
                BarIcon(icon: "\u{F054}", config: config, color: foreground).padding(.leading, 8).padding(.trailing, 4).padding(.horizontal, 5)
            case .frontApp(let name):
                Text(name).font(labelFont).foregroundColor(foreground).padding(.horizontal, 5)
            case .plugin(let name, let state):
                HStack(spacing: 0) {
                    if let icon = state.icon, !icon.isEmpty {
                        BarIcon(icon: icon, config: config, color: Color(widgetColor(state.iconColor ?? state.color, fallback: config.foreground)))
                            .padding(.leading, 8).padding(.trailing, 4)
                    }
                    if let label = state.label, !label.isEmpty {
                        Text(label).font(labelFont).foregroundColor(Color(widgetColor(state.color, fallback: config.foreground)))
                    }
                }
                .padding(.horizontal, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(state.background.map { Color(widgetColor($0, fallback: 0)) } ?? .clear))
                .contentShape(Rectangle())
                .onTapGesture { clickPlugin(name, state) }
                .overlay(RightClickCatcher { PluginHost.shared.click(name, button: "right") })
            case .problem(let name, let reason):
                Text("⚠ \(name)").font(labelFont).foregroundColor(.orange).padding(.horizontal, 5).help(reason)
                    .contentShape(Rectangle())
                    // Tooltips need an active app, and HyprDarwin never is: show the reason on click instead
                    .onTapGesture { showMenu([NSMenuItem(title: "\(name): \(reason)", action: nil, keyEquivalent: "")]) }
        }
    }
}

/// An icon laid out by its whole drawing (not its advance width), so the label beside it never overlaps it
private struct BarIcon: View {
    let icon: String
    let config: BarConfig
    let color: Color

    var body: some View {
        let font = barIconNSFont(family: config.font, size: CGFloat(config.iconSize))
        Text(icon)
            .font(Font(font)) // the same NSFont that was measured
            .foregroundColor(color)
            .fixedSize()
            .offset(x: barIconLeadingInset(icon, font: font))
            .frame(width: barIconWidth(icon, font: font), alignment: .leading)
    }
}

@MainActor private func focusWorkspaceFromBar(_ name: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task.startUnstructured {
        try await runLightSession(.menuBarButton, token) { _ = Workspace.get(byName: name).focusWorkspace() }
    }
}

@MainActor private func showMenu(_ items: [NSMenuItem]) {
    let menu = NSMenu()
    items.forEach(menu.addItem)
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
}

/// SwiftUI has no right-click gesture on macOS: this view takes right-mouse-down and lets every other click through
private struct RightClickCatcher: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> RightClickView { RightClickView(action: action) }
    func updateNSView(_ view: RightClickView, context: Context) { view.action = action }
}

final class RightClickView: NSView {
    var action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil // left clicks fall through to SwiftUI
    }

    override func rightMouseDown(with event: NSEvent) { action() }
}

/// Popup items → menu; otherwise a `click` event
@MainActor private func clickPlugin(_ name: String, _ state: WidgetState) {
    guard !state.popup.isEmpty else {
        PluginHost.shared.click(name, button: "left")
        return
    }
    let menu = NSMenu()
    for item in state.popup {
        let menuItem = NSMenuItem(title: item.label, action: item.run == nil ? nil : #selector(PopupTarget.choose(_:)), keyEquivalent: "")
        menuItem.target = PopupTarget.shared
        menuItem.representedObject = item.run.map { [name, $0] }
        menuItem.isEnabled = item.run != nil
        menu.addItem(menuItem)
    }
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
}

@MainActor private final class PopupTarget: NSObject {
    static let shared = PopupTarget()

    @objc func choose(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        runPluginCommand(pair[0], pair[1])
    }
}
