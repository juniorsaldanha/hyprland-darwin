import AppKit
import Common
import Foundation
import os

let signposter = OSSignposter(subsystem: aeroSpaceAppId, category: .pointsOfInterest)

let myPid = NSRunningApplication.current.processIdentifier
let lockScreenAppBundleId = "com.apple.loginwindow"

@MainActor private var signalSources: [DispatchSourceSignal] = []

/// Clean shutdown on the main thread. A dispatch source, not a C handler: no async-signal-unsafe work in the handler,
/// any delivery thread is fine. If the main thread is stuck (hung AX call), `fallback` still ends the process.
@MainActor func interceptTermination(
    _ sig: Int32,
    fallbackAfter: DispatchTimeInterval = .seconds(2),
    fallback: @escaping @Sendable () -> Void = {},
    shutdown: @escaping @MainActor () -> Void = {},
) {
    signal(sig, SIG_IGN) // else the default action kills us before the source sees it
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    source.setEventHandler { @Sendable in
        DispatchQueue.global().asyncAfter(deadline: .now() + fallbackAfter, execute: fallback)
        DispatchQueue.main.async { MainActor.assumeIsolated { shutdown() } }
    }
    source.resume()
    signalSources.append(source)
}

@MainActor func interceptTermination(_ sig: Int32) {
    interceptTermination(sig, fallback: { _exit(128 + sig) }) {
        terminationHandler?.beforeTermination()
        exit(sig)
    }
}

@MainActor
func initTerminationHandler() {
    unsafe _terminationHandler = AppServerTerminationHandler()
}

private struct AppServerTerminationHandler: TerminationHandler {
    @MainActor
    func beforeTermination() {
        PluginHost.shared.stopAll(immediately: true) // no plugin process may outlive the app
        // Make all windows fullscreen before Quit
        for window in MacWindow.allWindowsMap.values {
            // makeAllWindowsVisibleAndRestoreSize may be invoked when something went wrong (e.g. some windows are unbound)
            // that's why it's not allowed to use `.parent` call in here
            let monitor = window.macApp.getAxRectForTermination(window.windowId)?.center.monitorApproximation ?? mainMonitorInfo
            let monitorVisibleRect = monitor.visibleRect
            let windowSize = window.lastFloatingSize ?? CGSize(width: monitorVisibleRect.width, height: monitorVisibleRect.height)
            let point = CGPoint(
                x: (monitorVisibleRect.width - windowSize.width) / 2,
                y: (monitorVisibleRect.height - windowSize.height) / 2,
            )
            window.macApp.setAxFrameForTermination(window.windowId, point, windowSize)
        }
        if isDebug {
            let semaphore = DispatchSemaphore(value: 0)
            // Use Task.detached to avoid inheriting @MainActor.
            // If @MainActor was inherited, it would cause a deadlock
            Task.detached {
                await toggleReleaseServerIfDebug(.on)
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}

@MainActor
func terminateApp() -> Never {
    NSApplication.shared.terminate(nil)
    die("Unreachable code")
}

extension String {
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(self, forType: .string)
    }
}

func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

func + (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
}

extension CGPoint: ConvenienceMutable {}

extension CGPoint {
    func distance(toOuterFrame rect: Rect) -> CGFloat {
        // Subtract 1 from maxX/maxY because the right/bottom bounds are
        // exclusive.
        let dx = max(rect.minX - x, 0, x - (rect.maxX - 1))
        let dy = max(rect.minY - y, 0, y - (rect.maxY - 1))
        return CGPoint(x: dx, y: dy).vectorLength
    }

    func coerce(in rect: Rect) -> CGPoint? {
        guard let xRange = rect.minX.until(incl: rect.maxX - 1) else { return nil }
        guard let yRange = rect.minY.until(incl: rect.maxY - 1) else { return nil }
        return CGPoint(x: x.coerce(in: xRange), y: y.coerce(in: yRange))
    }

    func addingXOffset(_ offset: CGFloat) -> CGPoint { CGPoint(x: x + offset, y: y) }
    func addingYOffset(_ offset: CGFloat) -> CGPoint { CGPoint(x: x, y: y + offset) }
    func addingOffset(_ orientation: Orientation, _ offset: CGFloat) -> CGPoint { orientation == .h ? addingXOffset(offset) : addingYOffset(offset) }

    func getProjection(_ orientation: Orientation) -> Double { orientation == .h ? x : y }

    var vectorLength: CGFloat { sqrt(x * x + y * y) }

    var monitorApproximation: MonitorInfo { monitorInfos.minByOrDie { distance(toOuterFrame: $0.rect) } }

    var withYAxisFlipped: CGPoint {
        consuming get {
            self.y = mainMonitorInfo.height - self.y
            return self
        }
    }
}

extension CGFloat {
    func div(_ denominator: Int) -> CGFloat? {
        denominator == 0 ? nil : self / CGFloat(denominator)
    }

    func coerce(in range: ClosedRange<CGFloat>) -> CGFloat {
        switch true {
            case self > range.upperBound: range.upperBound
            case self < range.lowerBound: range.lowerBound
            default: self
        }
    }
}

extension CGPoint: @retroactive Hashable { // todo migrate to self written Point
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

#if DEBUG
    let isDebug = true
#else
    let isDebug = false
#endif

@inlinable
func checkCancellation(_ cm: CancellationMode = .cancellable) throws(CancellationError) {
    if cm == .cancellable && Task.isCancelled {
        throw CancellationError()
    }
}

public enum CancellationMode: Equatable, Sendable {
    case cancellable
    case nonCancellable
}
