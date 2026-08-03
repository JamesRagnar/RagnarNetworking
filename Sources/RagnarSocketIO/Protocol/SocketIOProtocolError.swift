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
    case missingSocketIOPacketType
    case unknownSocketIOPacketType(String)
    case invalidBinaryAttachmentCount
    case invalidNamespace
    case namespaceMissingComma
    case invalidAcknowledgementID
    case missingAcknowledgementID
    case invalidJSON
    case invalidEventPayload
    case missingEventName
    case invalidConnectPayload
    case invalidConnectErrorPayload
    case unexpectedPayload
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

        case .missingSocketIOPacketType:
            "The Socket.IO packet type is missing."

        case .unknownSocketIOPacketType(let packetType):
            "Socket.IO packet type \(packetType) is unknown."

        case .invalidBinaryAttachmentCount:
            "The Socket.IO binary attachment count is invalid."

        case .invalidNamespace:
            "The Socket.IO namespace is invalid."

        case .namespaceMissingComma:
            "The Socket.IO namespace is missing its terminating comma."

        case .invalidAcknowledgementID:
            "The Socket.IO acknowledgement identifier is invalid."

        case .missingAcknowledgementID:
            "The Socket.IO acknowledgement identifier is missing."

        case .invalidJSON:
            "The Socket.IO packet contains invalid JSON."

        case .invalidEventPayload:
            "The Socket.IO event payload must be a JSON array."

        case .missingEventName:
            "The Socket.IO event payload must begin with a string name."

        case .invalidConnectPayload:
            "The Socket.IO connect payload must be a JSON object."

        case .invalidConnectErrorPayload:
            "The Socket.IO connect-error payload must be a JSON object."

        case .unexpectedPayload:
            "The Socket.IO packet contains an unexpected payload."
        }
    }
}
