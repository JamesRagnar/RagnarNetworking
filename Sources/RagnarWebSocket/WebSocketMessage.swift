import Foundation

/// A complete text or binary WebSocket message.
public enum WebSocketMessage: Sendable, Equatable {
    /// A UTF-8 text message.
    case text(String)

    /// A binary message.
    case binary(Data)
}
