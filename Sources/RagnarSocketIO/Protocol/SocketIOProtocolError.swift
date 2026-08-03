import Foundation

public enum SocketIOProtocolError: Error, Sendable, Equatable {
    case invalidEndpoint
    case unsupportedEngineIOVersion(String?)
    case unsupportedTransport(String?)
    case unknownEngineIOPacketType(String?)
    case malformedOpenPayload
    case invalidHeartbeatTiming
    case invalidMaximumPayload
    case messageExceedsMaximumPayload(limit: Int, actual: Int)
    case unsupportedTransportFeature(String)
}

extension SocketIOProtocolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The Socket.IO endpoint is invalid."

        case .unsupportedEngineIOVersion(let version):
            "Engine.IO version \(version ?? "missing") is unsupported."

        case .unsupportedTransport(let transport):
            "Engine.IO transport \(transport ?? "missing") is unsupported."

        case .unknownEngineIOPacketType(let packetType):
            "Engine.IO packet type \(packetType ?? "missing") is unknown."

        case .malformedOpenPayload:
            "The Engine.IO open payload is malformed."

        case .invalidHeartbeatTiming:
            "The Engine.IO heartbeat timing is invalid."

        case .invalidMaximumPayload:
            "The Engine.IO maximum payload is invalid."

        case .messageExceedsMaximumPayload(let limit, let actual):
            "The Engine.IO message contains \(actual) bytes, exceeding the \(limit)-byte limit."

        case .unsupportedTransportFeature(let feature):
            "The Engine.IO transport feature \(feature) is unsupported."
        }
    }
}
