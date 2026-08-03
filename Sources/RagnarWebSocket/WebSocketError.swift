import Foundation

public struct WebSocketErrorSnapshot: Error, Sendable, Equatable {
    public let typeName: String
    public let description: String

    public init(_ error: any Error) {
        typeName = String(reflecting: type(of: error))
        description = String(describing: error)
    }
}

public enum WebSocketError: Error, Sendable, Equatable {
    case invalidRequest
    case connectionAlreadyActive
    case noActiveConnection
    case concurrentReceive
    case connectionReplacedOrClosed
    case transport(WebSocketErrorSnapshot)
}

extension WebSocketError: LocalizedError {
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
