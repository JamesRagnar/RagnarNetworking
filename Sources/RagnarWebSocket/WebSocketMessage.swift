import Foundation

public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}
