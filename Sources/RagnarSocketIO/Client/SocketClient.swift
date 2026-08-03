import Foundation

/// An actor that manages one Socket.IO connection lifecycle and its event subscriptions.
public protocol SocketClient: Actor {
    /// Validates `endpoint` and starts connecting without waiting for handshake completion.
    func connect(to endpoint: SocketIOEndpoint) throws

    /// Closes the active transport while preserving subscriptions and future connection use.
    func disconnect()

    /// Permanently closes the client and finishes all subscriptions.
    func invalidate()

    /// Encodes and emits one event payload on a connected client.
    func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type,
        _ payload: Event.Schema
    ) async throws

    /// Emits an event with no arguments on a connected client.
    func emit<Event: EmittableSocketEvent>(
        _ event: Event.Type
    ) async throws where Event.Schema == SocketEmptyBody

    /// Creates an independent typed subscription using `policy`, or the event's default policy when `policy` is `nil`.
    func events<Event: SocketEvent>(
        for event: Event.Type,
        policy: SocketStreamPolicy?
    ) -> SocketEventStream<Event>

    /// Creates an independent newest-value stream that immediately emits the current status.
    func statusUpdates() -> AsyncStream<SocketConnectionStatus>
}

public extension SocketClient {
    /// Creates an independent typed subscription using the event's default stream policy.
    func events<Event: SocketEvent>(
        for event: Event.Type
    ) -> SocketEventStream<Event> {
        events(for: event, policy: nil)
    }
}
