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
