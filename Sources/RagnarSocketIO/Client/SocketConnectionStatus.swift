import Foundation

/// The current lifecycle state published by `SocketClient.statusUpdates()`.
public enum SocketConnectionStatus: Sendable, Equatable {
    /// No transport is active and the client may connect again.
    case disconnected
    /// The client is establishing the initial transport and namespace connection.
    case connecting
    /// The server accepted the default Socket.IO namespace connection.
    case connected
    /// The client is waiting to start the numbered reconnect attempt.
    case reconnecting(attempt: Int)
    /// The lifecycle ended because of a terminal failure.
    case failed(SocketConnectionFailure)
    /// The client was permanently invalidated.
    case invalidated
}

/// A Sendable description of a terminal Socket.IO connection failure.
public enum SocketConnectionFailure: Sendable, Equatable {
    /// The peer sent data that violates the supported protocol grammar or lifecycle.
    case protocolViolation(String)
    /// The peer requires a recognized capability that the client does not implement.
    case unsupportedCapability(String)
    /// The server rejected the Socket.IO namespace connection.
    case connectError(message: String?)
    /// The WebSocket transport failed. The associated value is the underlying error type name.
    case transport(typeName: String)
    /// The server did not send a ping before the Engine.IO heartbeat deadline.
    case heartbeatTimeout
    /// The server did not accept the default namespace before the configured timeout.
    case namespaceTimeout
    /// The reconnect policy's attempt limit was reached.
    case reconnectExhausted(attempts: Int)
}
