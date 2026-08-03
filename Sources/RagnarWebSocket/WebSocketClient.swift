import Foundation

/// An actor-isolated transport for one active WebSocket task.
///
/// A conforming type must permit at most one active receive operation. Opening a connection starts the transport but
/// does not imply that the HTTP upgrade has completed.
public protocol WebSocketClient: Actor {
    /// Validates and starts a WebSocket request.
    /// - Throws: `WebSocketError.invalidRequest` for an invalid request, or
    ///   `WebSocketError.connectionAlreadyActive` when a connection is active.
    func open(_ request: URLRequest) throws

    /// Sends one text or binary message on the active connection.
    func send(_ message: WebSocketMessage) async throws

    /// Receives one text or binary message from the active connection.
    /// - Throws: `WebSocketError.concurrentReceive` when another receive operation is active.
    func receive() async throws -> WebSocketMessage

    /// Closes the active connection. Calling this method without an active connection has no effect.
    func close(code: WebSocketCloseCode, reason: Data?)
}
