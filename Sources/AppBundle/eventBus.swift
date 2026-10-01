/// In-process subscribers to the same events that `aerospace subscribe` socket clients receive.
/// Borders, bar and plugin host listen here instead of going through the socket.
@MainActor private var eventListeners: [UniqueToken: @MainActor (ServerEvent) -> Void] = [:]

@MainActor func addEventListener(_ listener: @escaping @MainActor (ServerEvent) -> Void) -> UniqueToken {
    let token = UniqueToken()
    eventListeners[token] = listener
    return token
}

@MainActor func removeEventListener(_ token: UniqueToken) {
    eventListeners.removeValue(forKey: token)
}

@MainActor func notifyEventListeners(_ event: ServerEvent) {
    for listener in eventListeners.values {
        listener(event)
    }
}
