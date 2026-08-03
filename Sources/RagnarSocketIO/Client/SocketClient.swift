import Foundation

public protocol SocketClient: Actor {
    func connect(to endpoint: SocketIOEndpoint) throws
    func disconnect()
    func invalidate()

    func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type,
        _ payload: Event.Schema
    ) async throws

    func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type
    ) async throws where Event.Schema == SocketEmptyBody

    func events<Event: SocketEvent>(
        for event: Event.Type,
        policy: SocketStreamPolicy?
    ) -> SocketEventStream<Event>

    func statusUpdates() -> AsyncStream<SocketConnectionStatus>
}

public extension SocketClient {
    func events<Event: SocketEvent>(
        for event: Event.Type
    ) -> SocketEventStream<Event> {
        events(for: event, policy: nil)
    }
}
