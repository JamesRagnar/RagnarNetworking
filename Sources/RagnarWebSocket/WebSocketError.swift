import Foundation

/// A Sendable description of an error reported by the underlying transport.
public struct WebSocketErrorSnapshot: Error, Sendable, Equatable {
    /// The fully qualified type name of the captured error.
    public let typeName: String
    /// The captured error's description.
    public let description: String

    /// Captures the type and description of `error` without retaining it.
    public init(_ error: any Error) {
        typeName = String(reflecting: type(of: error))
        description = String(describing: error)
    }
}

/// Errors reported by a `WebSocketClient` operation.
public enum WebSocketError: Error, Sendable, Equatable {
    /// The request does not contain a `ws` or `wss` URL with a host.
    case invalidRequest
    /// `open(_:)` was called while a task was active.
    case connectionAlreadyActive
    /// An operation requires an active task.
    case noActiveConnection
    /// A second receive operation was started before the first completed.
    case concurrentReceive
    /// The operation's task closed while the operation was suspended.
    case connectionReplacedOrClosed
    /// The underlying transport reported an error.
    case transport(WebSocketErrorSnapshot)
}

extension WebSocketError: LocalizedError {
    /// A description of the failed WebSocket operation.
    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The WebSocket request must contain a ws or wss URL with a host."

        case .connectionAlreadyActive:
            "A WebSocket connection is already active."

        case .noActiveConnection:
            "There is no active WebSocket connection."

        case .concurrentReceive:
            "Only one WebSocket receive operation may be active."

        case .connectionReplacedOrClosed:
            "The WebSocket connection was replaced or closed while the operation was suspended."

        case .transport(let snapshot):
            snapshot.description
        }
    }
}
