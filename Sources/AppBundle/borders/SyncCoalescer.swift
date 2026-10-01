import Foundation

/// Merges bursts of requests (e.g. Accessibility move notifications during a drag) into one action per run-loop turn.
@MainActor final class SyncCoalescer {
    private let schedule: @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void
    private let action: @MainActor () -> Void
    private var isScheduled = false

    init(
        schedule: @escaping @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void = SyncCoalescer.nextRunLoopTurn,
        action: @escaping @MainActor () -> Void,
    ) {
        self.schedule = schedule
        self.action = action
    }

    func request() {
        if isScheduled { return }
        isScheduled = true
        schedule { [weak self] in
            guard let self else { return }
            isScheduled = false
            action()
        }
    }

    static func nextRunLoopTurn(_ block: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { block() } }
    }
}
