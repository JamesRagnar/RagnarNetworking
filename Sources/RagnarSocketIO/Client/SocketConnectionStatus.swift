import Foundation

public enum SocketConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(SocketConnectionFailure)
    case invalidated
}

public enum SocketConnectionFailure: Sendable, Equatable {
    case protocolViolation(String)
    case unsupportedCapability(String)
    case connectError(message: String?)
    case transport(typeName: String)
    case heartbeatTimeout
    case namespaceTimeout
    case reconnectExhausted(attempts: Int)
}
